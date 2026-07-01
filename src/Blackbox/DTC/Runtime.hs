{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Runtime
    ( DtcRunResult (..)
    , RunOptions (..)
    , Verdict (..)
    , runPlan
    ) where

import           Control.Monad          (forM)
import           Control.Exception      (finally)
import qualified Data.Aeson             as A
import qualified Data.ByteString.Lazy   as BL
import qualified Data.Text              as T
import           Data.Text              (Text)
import           Data.Time.Clock        (getCurrentTime)
import           Data.Time.Format       (defaultTimeLocale, formatTime)
import           System.Directory       (createDirectoryIfMissing,
                                          getTemporaryDirectory)
import           System.FilePath        ((</>))

import           Blackbox.DTC
import           Blackbox.DTC.Env
import           Blackbox.DTC.Fixture
import           Blackbox.DTC.Result
import           Blackbox.DTC.Runner
import           Blackbox.DTC.Trigger
import           Blackbox.DTC.Verifier


data RunOptions = RunOptions
    { roOutputDir :: Maybe FilePath
    } deriving (Eq, Show)


runPlan :: RunOptions -> FilePath -> DtcPlan -> IO [DtcRunResult]
runPlan opts appPath plan = do
    runDir <- createRunDir opts plan
    forM (dpSteps plan) $ \step -> do
        let workDir = runDir </> T.unpack (psId step)
        createDirectoryIfMissing True workDir
        result <- runStep (DtcEnv workDir Nothing) appPath step
        persistResult opts runDir result
        pure result


runStep :: DtcEnv -> FilePath -> PlanStep -> IO DtcRunResult
runStep env appPath step = do
    fixtureState <- setupFixtures env (psSetup step)
    runWithFixtures fixtureState `finally` fsCleanup fixtureState
  where
    runWithFixtures fixtureState = do
        let stepEnv = fsEnv fixtureState
            unsupported = fsUnsupported fixtureState <> triggerUnsupported (psTriggers step)
        if not (null unsupported)
            then pure (unsupportedResult stepEnv step unsupported)
            else do
                capture <- runSpec stepEnv appPath (psRun step) (psTriggers step)
                let failures = verifyExpectations (psExpect step) capture
                    verdict =
                        case failures of
                            [] -> Pass
                            xs -> Fail xs
                pure (captureResult stepEnv step verdict capture)


unsupportedResult :: DtcEnv -> PlanStep -> [Text] -> DtcRunResult
unsupportedResult env step reasons =
    DtcRunResult
        { drrStepId = psId step
        , drrWorkDir = deWorkDir env
        , drrBehaviorSurfaces = psBehaviorSurfaces step
        , drrSpecSurfaces = psSpecSurfaces step
        , drrExit = Nothing
        , drrStdout = ""
        , drrStderr = ""
        , drrDurationMs = 0
        , drrStopReason = NotRun
        , drrVerdict = Unsupported reasons
        }


captureResult :: DtcEnv -> PlanStep -> Verdict -> ProcessCapture -> DtcRunResult
captureResult env step verdict capture =
    DtcRunResult
        { drrStepId = psId step
        , drrWorkDir = deWorkDir env
        , drrBehaviorSurfaces = psBehaviorSurfaces step
        , drrSpecSurfaces = psSpecSurfaces step
        , drrExit = pcExit capture
        , drrStdout = pcStdout capture
        , drrStderr = pcStderr capture
        , drrDurationMs = pcDurationMs capture
        , drrStopReason = pcStopReason capture
        , drrVerdict = verdict
        }


createRunDir :: RunOptions -> DtcPlan -> IO FilePath
createRunDir opts plan = do
    base <- case roOutputDir opts of
        Just dir -> pure dir
        Nothing  -> (</> "hsbb-dtc") <$> getTemporaryDirectory
    stamp <- formatTime defaultTimeLocale "%Y%m%d-%H%M%S-%q" <$> getCurrentTime
    let runDir = base </> T.unpack (dpName plan) </> stamp
    createDirectoryIfMissing True runDir
    pure runDir


persistResult :: RunOptions -> FilePath -> DtcRunResult -> IO ()
persistResult opts runDir result =
    case roOutputDir opts of
        Nothing -> pure ()
        Just _  -> BL.appendFile (runDir </> "results.jsonl") (A.encode result <> "\n")
