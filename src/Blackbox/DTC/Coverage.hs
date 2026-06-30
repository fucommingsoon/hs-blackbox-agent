{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Coverage
    ( CoverageSummary (..)
    , Readiness (..)
    , summarizePlanCoverage
    ) where

import qualified Data.Aeson as A
import           Data.List  (nub, sort)
import           Data.Text  (Text)
import           GHC.Generics (Generic)

import           Blackbox.DTC.Types


data Readiness
    = ReadinessLow
    | ReadinessMedium
    | ReadinessHigh
    deriving (Eq, Show, Generic)

instance A.ToJSON Readiness


data CoverageSummary = CoverageSummary
    { csPlanName                :: Text
    , csStepCount               :: Int
    , csBehaviorSurfacesCovered :: [BehaviorSurface]
    , csSpecSurfacesCovered     :: [SpecSurface]
    , csBehaviorSurfacesMissing :: [BehaviorSurface]
    , csSpecSurfacesMissing     :: [SpecSurface]
    , csReadiness               :: Readiness
    } deriving (Eq, Show, Generic)

instance A.ToJSON CoverageSummary


summarizePlanCoverage :: DtcPlan -> CoverageSummary
summarizePlanCoverage plan =
    CoverageSummary
        { csPlanName = dpName plan
        , csStepCount = length (dpSteps plan)
        , csBehaviorSurfacesCovered = behaviorCovered
        , csSpecSurfacesCovered = specCovered
        , csBehaviorSurfacesMissing = missing requiredBehavior behaviorCovered
        , csSpecSurfacesMissing = missing requiredSpec specCovered
        , csReadiness =
            readiness
                (missing requiredBehavior behaviorCovered)
                (missing requiredSpec specCovered)
        }
  where
    behaviorCovered = uniqueSorted (concatMap psBehaviorSurfaces (dpSteps plan))
    specCovered = uniqueSorted (concatMap psSpecSurfaces (dpSteps plan))
    (requiredBehavior, requiredSpec) = requiredSurfaces plan


requiredSurfaces :: DtcPlan -> ([BehaviorSurface], [SpecSurface])
requiredSurfaces plan
    | WatcherCli `elem` dpArchetypes plan = watcherRequiredSurfaces
    | otherwise = ([], [])


watcherRequiredSurfaces :: ([BehaviorSurface], [SpecSurface])
watcherRequiredSurfaces =
    ( map BehaviorSurface
        [ "cli.args"
        , "stdin.watch_list"
        , "watch_list.empty"
        , "watch_list.missing_file"
        , "fixture.file.touch"
        , "fixture.file.write"
        , "trigger.file.append"
        , "trigger.file.create"
        , "child.stdout"
        , "child.exit_code"
        , "oneshot.exit"
        , "substitution.changed_path"
        , "directory.altered"
        , "exit.code"
        , "stderr.error"
        ]
    , map SpecSurface
        [ "plan.id"
        , "fixture.shape"
        , "run.cmd"
        , "run.stdin"
        , "trigger.shape"
        , "expect.exit"
        , "expect.stdout"
        , "expect.stderr"
        , "expect.duration"
        , "runtime.evidence_stop"
        ]
    )


readiness :: [BehaviorSurface] -> [SpecSurface] -> Readiness
readiness [] [] = ReadinessHigh
readiness [] _  = ReadinessMedium
readiness _  [] = ReadinessMedium
readiness _  _  = ReadinessLow


missing :: Ord a => [a] -> [a] -> [a]
missing required covered =
    filter (`notElem` covered) required


uniqueSorted :: Ord a => [a] -> [a]
uniqueSorted =
    nub . sort
