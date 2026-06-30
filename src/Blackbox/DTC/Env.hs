{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Env
    ( DtcEnv (..)
    , expandPath
    , expandText
    ) where

import qualified Data.Text as T
import           Data.Text (Text)


data DtcEnv = DtcEnv
    { deWorkDir :: FilePath
    , dePort    :: Maybe Int
    } deriving (Eq, Show)


expandPath :: DtcEnv -> FilePath -> FilePath
expandPath env =
    T.unpack . expandText env . T.pack


expandText :: DtcEnv -> Text -> Text
expandText env =
    T.replace "${PORT}" portText
        . T.replace "${WORK}" (T.pack (deWorkDir env))
  where
    portText =
        case dePort env of
            Just port -> T.pack (show port)
            Nothing   -> "${PORT}"
