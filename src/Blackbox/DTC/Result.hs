{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Result
    ( DtcRunResult (..)
    , ProcessCapture (..)
    , Verdict (..)
    ) where

import qualified Data.Aeson   as A
import           Data.Text    (Text)
import           GHC.Generics (Generic)


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
    } deriving (Eq, Show, Generic)

instance A.ToJSON ProcessCapture


data DtcRunResult = DtcRunResult
    { drrStepId     :: Text
    , drrExit       :: Maybe Int
    , drrStdout     :: Text
    , drrStderr     :: Text
    , drrDurationMs :: Int
    , drrVerdict    :: Verdict
    } deriving (Eq, Show, Generic)

instance A.ToJSON DtcRunResult
