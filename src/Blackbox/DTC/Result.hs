{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Result
    ( CaptureStopReason (..)
    , DtcRunResult (..)
    , ProcessCapture (..)
    , Verdict (..)
    ) where

import qualified Data.Aeson   as A
import           Data.Text    (Text)
import           GHC.Generics (Generic)

import           Blackbox.DTC.Types (BehaviorSurface, SpecSurface)


data Verdict
    = Pass
    | Fail [Text]
    | Unsupported [Text]
    deriving (Eq, Show, Generic)

instance A.ToJSON Verdict


data ProcessCapture = ProcessCapture
    { pcExit       :: Maybe Int
    , pcStdout     :: Text
    , pcStderr     :: Text
    , pcDurationMs :: Int
    , pcStopReason :: CaptureStopReason
    } deriving (Eq, Show, Generic)

instance A.ToJSON ProcessCapture


data CaptureStopReason
    = NotRun
    | ProcessExited
    | TimedOut
    | EvidenceMatched
    deriving (Eq, Show, Generic)

instance A.ToJSON CaptureStopReason


data DtcRunResult = DtcRunResult
    { drrStepId     :: Text
    , drrWorkDir    :: FilePath
    , drrBehaviorSurfaces :: [BehaviorSurface]
    , drrSpecSurfaces     :: [SpecSurface]
    , drrExit       :: Maybe Int
    , drrStdout     :: Text
    , drrStderr     :: Text
    , drrDurationMs :: Int
    , drrStopReason :: CaptureStopReason
    , drrVerdict    :: Verdict
    } deriving (Eq, Show, Generic)

instance A.ToJSON DtcRunResult
