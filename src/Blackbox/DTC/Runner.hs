{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Runner
    ( runSpec
    ) where

import           Control.Concurrent      (forkIO)
import           Control.Exception       (evaluate)
import qualified Data.Text               as T
import           Data.Text               (Text)
import           Data.Time.Clock         (diffUTCTime, getCurrentTime)
import           System.Exit             (ExitCode (..))
import           System.IO               (Handle, hClose, hGetContents,
                                           hPutStr)
import           System.Process          (CreateProcess (..), StdStream (..),
                                           createProcess,
                                           readCreateProcessWithExitCode,
                                           shell, terminateProcess,
                                           waitForProcess)
import           System.Timeout          (timeout)

import           Blackbox.DTC
import           Blackbox.DTC.Result
import           Blackbox.DTC.Trigger    (runTriggers)


runSpec :: FilePath -> RunSpec -> [TriggerAction] -> IO ProcessCapture
runSpec appPath spec triggers =
    case rsMode spec of
        RunSync  -> runSync appPath spec
        RunAsync -> runAsync appPath spec triggers


runSync :: FilePath -> RunSpec -> IO ProcessCapture
runSync appPath spec = do
    start <- getCurrentTime
    outcome <- timeout (rsTimeoutMs spec * 1000) $
        readCreateProcessWithExitCode
            (shell (renderCmd appPath (rsCmd spec)))
            (maybe "" T.unpack (rsStdin spec))
    end <- getCurrentTime
    let durMs = floor (diffUTCTime end start * 1000)
    case outcome of
        Nothing ->
            pure ProcessCapture
                { pcExit = Nothing
                , pcStdout = ""
                , pcStderr = "timeout"
                , pcDurationMs = durMs
                }
        Just (exitCode, out, err) ->
            pure ProcessCapture
                { pcExit = Just (exitCodeToInt exitCode)
                , pcStdout = T.pack out
                , pcStderr = T.pack err
                , pcDurationMs = durMs
                }


runAsync :: FilePath -> RunSpec -> [TriggerAction] -> IO ProcessCapture
runAsync appPath spec triggers = do
    start <- getCurrentTime
    let cp = (shell (renderCmd appPath (rsCmd spec)))
            { std_in = CreatePipe
            , std_out = CreatePipe
            , std_err = CreatePipe
            }
    (mIn, mOut, mErr, ph) <- createProcess cp
    writeStdin mIn (rsStdin spec)
    _ <- forkIO (runTriggers triggers)
    outcome <- timeout (rsTimeoutMs spec * 1000) (waitForProcess ph)
    end <- getCurrentTime
    let durMs = floor (diffUTCTime end start * 1000)
    case outcome of
        Nothing -> do
            terminateProcess ph
            out <- forceRead mOut
            err <- forceRead mErr
            pure ProcessCapture
                { pcExit = Nothing
                , pcStdout = out
                , pcStderr = if T.null err then "timeout" else err <> "\ntimeout"
                , pcDurationMs = durMs
                }
        Just exitCode -> do
            out <- forceRead mOut
            err <- forceRead mErr
            pure ProcessCapture
                { pcExit = Just (exitCodeToInt exitCode)
                , pcStdout = out
                , pcStderr = err
                , pcDurationMs = durMs
                }


writeStdin :: Maybe Handle -> Maybe Text -> IO ()
writeStdin Nothing _ = pure ()
writeStdin (Just h) input = do
    hPutStr h (maybe "" T.unpack input)
    hClose h


forceRead :: Maybe Handle -> IO Text
forceRead Nothing = pure ""
forceRead (Just h) = do
    txt <- hGetContents h
    _ <- evaluate (length txt)
    pure (T.pack txt)


renderCmd :: FilePath -> Text -> String
renderCmd appPath cmd =
    T.unpack (replaceAppPrefix (T.pack (shellQuote appPath)) cmd)


replaceAppPrefix :: Text -> Text -> Text
replaceAppPrefix app cmd =
    case T.stripPrefix "app " cmd of
        Just rest -> app <> " " <> rest
        Nothing | T.strip cmd == "app" -> app
        Nothing -> cmd


shellQuote :: FilePath -> String
shellQuote s = "'" ++ concatMap quoteChar s ++ "'"
  where
    quoteChar '\'' = "'\\''"
    quoteChar c    = [c]


exitCodeToInt :: ExitCode -> Int
exitCodeToInt ExitSuccess     = 0
exitCodeToInt (ExitFailure n) = n
