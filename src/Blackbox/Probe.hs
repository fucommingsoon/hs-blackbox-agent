{-# LANGUAGE OverloadedStrings #-}

-- Probe wrapper: invokes ./probe (which is a docker exec wrapper provided
-- in each PB task dir).
--
-- Does NOT reach into the container, does NOT read tests.json or anything
-- forbidden — see README anti-cheating manifest.
module Blackbox.Probe
    ( runProbe
    , runProbeWithStdin
    , probeExists
    ) where

import           Control.Exception (try, SomeException)
import qualified Data.Text as T
import           Data.Text (Text)
import qualified Data.Text.IO as TIO
import           Data.Time.Clock (diffUTCTime, getCurrentTime)
import           System.Directory (doesFileExist)
import           System.Exit (ExitCode (..))
import           System.FilePath ((</>))
import qualified System.IO as IO
import           System.Process

import           Blackbox.Types


-- Returns True if the task dir contains an executable ./probe script.
probeExists :: FilePath -> IO Bool
probeExists taskDir = doesFileExist (taskDir </> "probe")


-- Run ./probe with the given args (no stdin).
runProbe :: FilePath -> ProbeCmd -> IO ProbeResult
runProbe taskDir cmd = runProbeWithStdin taskDir cmd ""


-- Run ./probe with args and stdin. Captures stdout, stderr, exit code, wall time.
runProbeWithStdin :: FilePath -> ProbeCmd -> Text -> IO ProbeResult
runProbeWithStdin taskDir cmd stdinBody = do
    let probeBin = "./probe"
        argv     = map T.unpack (pcArgs cmd)
        proc'    = (proc probeBin argv)
                       { cwd     = Just taskDir
                       , std_in  = CreatePipe
                       , std_out = CreatePipe
                       , std_err = CreatePipe
                       }
    t0     <- getCurrentTime
    result <- try $ do
        (Just hin, Just hout, Just herr, ph) <- createProcess proc'
        TIO.hPutStr hin stdinBody
        IO.hClose hin
        out <- TIO.hGetContents hout
        err <- TIO.hGetContents herr
        ec  <- waitForProcess ph
        pure (out, err, ec)
    t1 <- getCurrentTime
    let dur = realToFrac (diffUTCTime t1 t0) :: Double
    case result :: Either SomeException (Text, Text, ExitCode) of
        Left e -> pure $ ProbeResult
            { prCmd      = cmd
            , prStdout   = ""
            , prStderr   = T.pack (show e)
            , prExitCode = 127
            , prDuration = dur
            }
        Right (out, err, ec) -> pure $ ProbeResult
            { prCmd      = cmd { pcStdin = if T.null stdinBody then Nothing else Just stdinBody }
            , prStdout   = out
            , prStderr   = err
            , prExitCode = exitCodeInt ec
            , prDuration = dur
            }
  where
    exitCodeInt ExitSuccess     = 0
    exitCodeInt (ExitFailure n) = n
