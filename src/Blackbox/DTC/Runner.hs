{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Runner
    ( runSpec
    ) where

import           Control.Concurrent      (MVar, forkIO, newEmptyMVar,
                                           putMVar, takeMVar, threadDelay,
                                           tryReadMVar)
import           Control.Exception       (IOException, catch)
import           Data.IORef              (IORef, modifyIORef', newIORef,
                                           readIORef)
import qualified Data.Text               as T
import           Data.Text               (Text)
import           Data.Time.Clock         (diffUTCTime, getCurrentTime)
import           System.Exit             (ExitCode (..))
import           System.IO               (Handle, hClose, hGetChar,
                                           hPutStr, hWaitForInput)
import           System.Process          (CreateProcess (..), StdStream (..),
                                           ProcessHandle, createProcess,
                                           readCreateProcessWithExitCode,
                                           shell, terminateProcess,
                                           waitForProcess)
import           System.Timeout          (timeout)

import           Blackbox.DTC
import           Blackbox.DTC.Env
import           Blackbox.DTC.Result
import           Blackbox.DTC.Trigger    (runTriggers)


runSpec :: DtcEnv -> FilePath -> RunSpec -> [TriggerAction] -> IO ProcessCapture
runSpec env appPath spec triggers =
    case rsMode spec of
        RunSync  -> runSync env appPath spec
        RunAsync -> runAsync env appPath spec triggers


runSync :: DtcEnv -> FilePath -> RunSpec -> IO ProcessCapture
runSync env appPath spec = do
    start <- getCurrentTime
    outcome <- timeout (rsTimeoutMs spec * 1000) $
        readCreateProcessWithExitCode
            (shell (renderCmd env appPath (rsCmd spec)))
            (maybe "" (T.unpack . expandText env) (rsStdin spec))
    end <- getCurrentTime
    let durMs = floor (diffUTCTime end start * 1000)
    case outcome of
        Nothing ->
            pure ProcessCapture
                { pcExit = Nothing
                , pcStdout = ""
                , pcStderr = "timeout"
                , pcDurationMs = durMs
                , pcStopReason = TimedOut
                }
        Just (exitCode, out, err) ->
            pure ProcessCapture
                { pcExit = Just (exitCodeToInt exitCode)
                , pcStdout = T.pack out
                , pcStderr = T.pack err
                , pcDurationMs = durMs
                , pcStopReason = ProcessExited
                }


runAsync :: DtcEnv -> FilePath -> RunSpec -> [TriggerAction] -> IO ProcessCapture
runAsync env appPath spec triggers = do
    start <- getCurrentTime
    let cp = (shell (renderCmd env appPath (rsCmd spec)))
            { std_in = CreatePipe
            , std_out = CreatePipe
            , std_err = CreatePipe
            }
    (mIn, mOut, mErr, ph) <- createProcess cp
    writeStdin env mIn (rsStdin spec)
    outRef <- newIORef ""
    errRef <- newIORef ""
    _ <- forkIO (streamHandle outRef mOut)
    _ <- forkIO (streamHandle errRef mErr)
    exitVar <- newEmptyMVar
    _ <- forkIO (waitForProcess ph >>= putMVar exitVar)
    _ <- forkIO (runTriggers env triggers)
    outcome <- monitorProcess ph exitVar outRef errRef (rsTimeoutMs spec) (rsStopWhen spec)
    end <- getCurrentTime
    let durMs = floor (diffUTCTime end start * 1000)
    threadDelay 50000
    out <- readIORef outRef
    err <- readIORef errRef
    pure ProcessCapture
        { pcExit = captureExit outcome
        , pcStdout = out
        , pcStderr = case outcome of
            AsyncTimedOut | T.null err -> "timeout"
            AsyncTimedOut              -> err <> "\ntimeout"
            _                          -> err
        , pcDurationMs = durMs
        , pcStopReason = captureStopReason outcome
        }


data AsyncOutcome
    = AsyncExited ExitCode
    | AsyncTimedOut
    | AsyncEvidenceMatched


monitorProcess
    :: ProcessHandle
    -> MVar ExitCode
    -> IORef Text
    -> IORef Text
    -> Int
    -> [StopCondition]
    -> IO AsyncOutcome
monitorProcess ph exitVar outRef errRef timeoutMs stopWhen =
    timeout (timeoutMs * 1000) loop >>= maybe onTimeout pure
  where
    onTimeout = do
        terminateProcess ph
        _ <- timeout 500000 (takeMVar exitVar)
        pure AsyncTimedOut

    loop = do
        mexit <- tryReadMVar exitVar
        case mexit of
            Just exitCode -> pure (AsyncExited exitCode)
            Nothing -> do
                out <- readIORef outRef
                err <- readIORef errRef
                if stopMatched stopWhen out err
                    then do
                        terminateProcess ph
                        _ <- timeout 500000 (takeMVar exitVar)
                        pure AsyncEvidenceMatched
                    else do
                        threadDelay 50000
                        loop


streamHandle :: IORef Text -> Maybe Handle -> IO ()
streamHandle _ Nothing = pure ()
streamHandle ref (Just h) = loop `catch` ignoreIo
  where
    loop = do
        ready <- hWaitForInput h 50
        if ready
            then do
                ch <- hGetChar h
                modifyIORef' ref (`T.snoc` ch)
                loop
            else loop
    ignoreIo :: IOException -> IO ()
    ignoreIo _ = pure ()


stopMatched :: [StopCondition] -> Text -> Text -> Bool
stopMatched conditions out err =
    any matched conditions
  where
    matched (StopWhenStdoutContains needle) = needle `T.isInfixOf` out
    matched (StopWhenStderrContains needle) = needle `T.isInfixOf` err


captureExit :: AsyncOutcome -> Maybe Int
captureExit (AsyncExited exitCode) = Just (exitCodeToInt exitCode)
captureExit AsyncTimedOut = Nothing
captureExit AsyncEvidenceMatched = Nothing


captureStopReason :: AsyncOutcome -> CaptureStopReason
captureStopReason (AsyncExited _) = ProcessExited
captureStopReason AsyncTimedOut = TimedOut
captureStopReason AsyncEvidenceMatched = EvidenceMatched


writeStdin :: DtcEnv -> Maybe Handle -> Maybe Text -> IO ()
writeStdin _ Nothing _ = pure ()
writeStdin env (Just h) input = do
    hPutStr h (maybe "" (T.unpack . expandText env) input)
    hClose h


renderCmd :: DtcEnv -> FilePath -> Text -> String
renderCmd env appPath cmd =
    T.unpack (replaceAppPrefix (T.pack (shellQuote appPath)) (expandText env cmd))


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
