{-# LANGUAGE OverloadedStrings #-}

-- Core types shared across modules.
-- Oracle / probe records use Aeson.Object internally for flexible yaml/json mapping.
module Blackbox.Types
    ( -- LLM decision result
      Action (..)
    , parseAction
      -- Probe execution result
    , ProbeOutcome (..)
      -- Last result (in-memory between rounds)
    , LastResult (..)
    , makeLastResult
      -- Slot id constants
    , universalSlots
      -- Slicing constants
    , maxStdoutSlice
    , maxStderrSlice
    ) where

import qualified Data.Aeson as A
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import           Data.Text (Text)
import qualified Data.Text as T


-- ---------------------------------------------------------------
-- Action — what LLM decides each round
-- ---------------------------------------------------------------

data Action
    = ActProbe Text Text         -- cmd, why
    | ActGrep  Text [Text] Text  -- pattern, files, why
    | ActOther Text Text Text    -- kind, cmd, why
    | ActStop  Text              -- why
    deriving (Eq, Show)


-- Parse an action JSON object emitted by the LLM.
parseAction :: A.Value -> Maybe Action
parseAction (A.Object o) = do
    A.String tag <- KM.lookup "action" o
    let getStr k = case KM.lookup k o of
                       Just (A.String s) -> Just s
                       _                 -> Nothing
        getArr k = case KM.lookup k o of
                       Just (A.Array v) -> Just [s | A.String s <- foldr (:) [] v]
                       _                -> Nothing
        why = maybe "" id (getStr "why")
    case tag of
        "probe" -> do c <- getStr "cmd"
                      pure (ActProbe c why)
        "grep"  -> do p <- getStr "pattern"
                      let fs = maybe [] id (getArr "files")
                      pure (ActGrep p fs why)
        "other" -> do k <- getStr "kind"
                      c <- getStr "cmd"
                      pure (ActOther k c why)
        "stop"  -> pure (ActStop why)
        _       -> Nothing
parseAction _ = Nothing


-- ---------------------------------------------------------------
-- Probe execution outcome (post-execution, pre-slicing)
-- ---------------------------------------------------------------

data ProbeOutcome = ProbeOutcome
    { poCmd        :: Text
    , poExit       :: Int
    , poStdout     :: Text
    , poStderr     :: Text
    , poDurationMs :: Int
    } deriving (Show)


-- ---------------------------------------------------------------
-- LastResult — the sliced view that goes into next prompt
-- ---------------------------------------------------------------

data LastResult = LastResult
    { lrProbeId      :: Text
    , lrCmd          :: Text
    , lrExit         :: Int
    , lrStdoutSlice  :: Text   -- ≤ maxStdoutSlice
    , lrStderrSlice  :: Text   -- ≤ maxStderrSlice
    , lrStdoutBytes  :: Int    -- original size
    , lrStderrBytes  :: Int
    } deriving (Show)


makeLastResult :: Text -> ProbeOutcome -> LastResult
makeLastResult pid po = LastResult
    { lrProbeId     = pid
    , lrCmd         = poCmd po
    , lrExit        = poExit po
    , lrStdoutSlice = T.take maxStdoutSlice (poStdout po)
    , lrStderrSlice = T.take maxStderrSlice (poStderr po)
    , lrStdoutBytes = T.length (poStdout po)
    , lrStderrBytes = T.length (poStderr po)
    }


-- ---------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------

-- 7 universal slot ids.
universalSlots :: [Text]
universalSlots =
    [ "identity"
    , "cli_flags"
    , "io_channels"
    , "exit_codes"
    , "error_buckets"
    , "impl_fingerprint"
    , "known_unknowns"
    ]


maxStdoutSlice :: Int
maxStdoutSlice = 2048   -- 2 KB

maxStderrSlice :: Int
maxStderrSlice = 1024   -- 1 KB
