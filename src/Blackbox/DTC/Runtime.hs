{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Runtime
    ( DtcRunResult (..)
    , Verdict (..)
    , runPlan
    ) where

import           Control.Monad          (forM)
import           Data.Text              (Text)

import           Blackbox.DTC
import           Blackbox.DTC.Fixture
import           Blackbox.DTC.Result
import           Blackbox.DTC.Runner
import           Blackbox.DTC.Trigger
import           Blackbox.DTC.Verifier


runPlan :: FilePath -> DtcPlan -> IO [DtcRunResult]
runPlan appPath plan =
    forM (dpSteps plan) (runStep appPath)


runStep :: FilePath -> PlanStep -> IO DtcRunResult
runStep appPath step = do
    fixtureState <- setupFixtures (psSetup step)
    let unsupported = fsUnsupported fixtureState <> triggerUnsupported (psTriggers step)
    if not (null unsupported)
        then pure (unsupportedResult step unsupported)
        else do
            capture <- runSpec appPath (psRun step) (psTriggers step)
            let failures = verifyExpectations (psExpect step) capture
                verdict =
                    case failures of
                        [] -> Pass
                        xs -> Fail xs
            pure (captureResult step verdict capture)


unsupportedResult :: PlanStep -> [Text] -> DtcRunResult
unsupportedResult step reasons =
    DtcRunResult
        { drrStepId = psId step
        , drrExit = Nothing
        , drrStdout = ""
        , drrStderr = ""
        , drrDurationMs = 0
        , drrVerdict = Unsupported reasons
        }


captureResult :: PlanStep -> Verdict -> ProcessCapture -> DtcRunResult
captureResult step verdict capture =
    DtcRunResult
        { drrStepId = psId step
        , drrExit = pcExit capture
        , drrStdout = pcStdout capture
        , drrStderr = pcStderr capture
        , drrDurationMs = pcDurationMs capture
        , drrVerdict = verdict
        }
