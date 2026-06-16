{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- Core types for the black-box probe agent.
-- Aligned with the 12-form taxonomy in data/methodology.md (sections 1-3).
module Blackbox.Types
    ( BlackBoxType (..)
    , bbtName
    , bbtAllForms
    , PlanStage (..)
    , psName
    , psPrompt
    , ProbeCmd (..)
    , ProbeResult (..)
    , isSilent
    , isBinary
    , Belief (..)
    , emptyBelief
    , AgentState (..)
    , initialState
    , ProbeStrategy (..)
    , StopReason (..)
    ) where

import qualified Data.Aeson as A
import           Data.Aeson ((.:), (.=))
import qualified Data.ByteString as BS
import           Data.Text (Text)
import qualified Data.Text as T
import           GHC.Generics (Generic)


-- 12-form taxonomy from methodology.md §1
data BlackBoxType
    = F1_PureFunction               -- stdin → stdout pure (shellharden, yj single mode)
    | F2_StatefulDaemon             -- async events (entr)
    | F3_TuiNcursesLocked           -- ncurses init fail (cmatrix)
    | F4_TuiStdoutEmitting          -- FTXUI-style stdout TUI (json-tui)
    | F5_HttpClient                 -- needs reflect target (bat)
    | F6_SilentLinter               -- 倒探 needed (errcheck)
    | F7_FormatConverter            -- 2D N×N matrix (yj)
    | F8_BinaryByteExact            -- compression / encoder (zstd)
    | F9_MultiStagePipeline         -- lexer / style / formatter (chroma)
    | F10_LargeFlagSpace            -- 30+ flag + 厚文档 (ripgrep)
    | F11_StructuredLinter          -- file:line:col diagnostic (dupl)
    | F12_AssetDependent            -- font/template/asset (figlet)
    | FUnknown                      -- fallback when detection inconclusive
    deriving stock (Eq, Show, Ord, Generic)

instance A.ToJSON BlackBoxType
instance A.FromJSON BlackBoxType


bbtName :: BlackBoxType -> Text
bbtName F1_PureFunction         = "pure-function"
bbtName F2_StatefulDaemon       = "stateful-daemon"
bbtName F3_TuiNcursesLocked     = "tui-ncurses-locked"
bbtName F4_TuiStdoutEmitting    = "tui-stdout-emitting"
bbtName F5_HttpClient           = "http-client"
bbtName F6_SilentLinter         = "silent-linter"
bbtName F7_FormatConverter      = "format-converter"
bbtName F8_BinaryByteExact      = "binary-byte-exact"
bbtName F9_MultiStagePipeline   = "multi-stage-pipeline"
bbtName F10_LargeFlagSpace      = "large-flag-space"
bbtName F11_StructuredLinter    = "structured-linter"
bbtName F12_AssetDependent      = "asset-dependent"
bbtName FUnknown                = "unknown"


bbtAllForms :: [BlackBoxType]
bbtAllForms =
    [ F1_PureFunction, F2_StatefulDaemon, F3_TuiNcursesLocked, F4_TuiStdoutEmitting
    , F5_HttpClient, F6_SilentLinter, F7_FormatConverter, F8_BinaryByteExact
    , F9_MultiStagePipeline, F10_LargeFlagSpace, F11_StructuredLinter, F12_AssetDependent
    ]


-- A planned probe step. PlanStage is a high-level intent; the LLM converts
-- it to one or more concrete ProbeCmd invocations.
data PlanStage = PlanStage
    { psId       :: Int            -- order in plan
    , psNameRaw  :: Text           -- e.g. "identity", "matching_modes"
    , psPromptRaw :: Text          -- hint to LLM what this stage probes
    , psDone     :: Bool
    }
    deriving stock (Eq, Show, Generic)

instance A.ToJSON PlanStage
instance A.FromJSON PlanStage

psName :: PlanStage -> Text
psName = psNameRaw

psPrompt :: PlanStage -> Text
psPrompt = psPromptRaw


-- One probe invocation request.
data ProbeCmd = ProbeCmd
    { pcArgs    :: [Text]          -- argv to pass to ./probe
    , pcStdin   :: Maybe Text       -- optional stdin
    , pcReason  :: Text             -- why this probe (for transcript)
    }
    deriving stock (Eq, Show, Generic)

instance A.ToJSON ProbeCmd
instance A.FromJSON ProbeCmd


-- Result of running one probe.
data ProbeResult = ProbeResult
    { prCmd      :: ProbeCmd
    , prStdout   :: Text
    , prStderr   :: Text
    , prExitCode :: Int
    , prDuration :: Double         -- seconds
    }
    deriving stock (Eq, Show, Generic)

instance A.ToJSON ProbeResult
instance A.FromJSON ProbeResult


isSilent :: ProbeResult -> Bool
isSilent pr = T.null (prStdout pr) && T.null (prStderr pr)


-- Heuristic: high ratio of non-printable bytes → binary output.
isBinary :: Text -> Bool
isBinary t =
    let s = T.unpack t
        total = length s
        nonPrintable = length (filter (\c -> not (isPrint c) && c /= '\n' && c /= '\t' && c /= '\r') s)
    in total > 0 && fromIntegral nonPrintable / fromIntegral total > (0.3 :: Double)
  where
    isPrint c = let o = fromEnum c in o >= 32 && o < 127


-- Accumulating belief about the target binary.
-- Output goes to belief.md.
data Belief = Belief
    { bTaskId        :: Text
    , bDetectedType  :: BlackBoxType
    , bIdentity      :: Maybe Text          -- e.g. "shellharden 4.3.1"
    , bCliSurface    :: [Text]              -- flag list
    , bExitCodes     :: [(Int, Text)]       -- (code, meaning)
    , bIoModel       :: Maybe Text          -- stdin/file/arg
    , bErrorBuckets  :: [Text]              -- error message bucket descriptions
    , bBugsToReplica :: [Text]              -- bug-as-contract list
    , bKnownUnknown  :: [Text]              -- explicit unprobeable
    , bProbeFacts    :: [Text]              -- atomic verified facts
    , bLibFingerprint :: [Text]             -- guessed underlying libs
    , bProbeCount    :: Int                 -- how many probes ran
    , bDurationSec   :: Double              -- total wall time
    }
    deriving stock (Eq, Show, Generic)

instance A.ToJSON Belief
instance A.FromJSON Belief


emptyBelief :: Text -> Belief
emptyBelief tid = Belief
    { bTaskId         = tid
    , bDetectedType   = FUnknown
    , bIdentity       = Nothing
    , bCliSurface     = []
    , bExitCodes      = []
    , bIoModel        = Nothing
    , bErrorBuckets   = []
    , bBugsToReplica  = []
    , bKnownUnknown   = []
    , bProbeFacts     = []
    , bLibFingerprint = []
    , bProbeCount     = 0
    , bDurationSec    = 0
    }


-- Strategy chosen at the very start, based on doc volume (methodology §0.1).
data ProbeStrategy
    = StrategyLandscape   -- ≥ 1000 lines doc — read all docs first
    | StrategyHybrid      -- 200-1000 — README + 1-2 probes
    | StrategyDiscovery   -- < 200 — probe first, refine plan on the fly
    deriving stock (Eq, Show, Generic)

instance A.ToJSON ProbeStrategy
instance A.FromJSON ProbeStrategy


-- Why the loop stopped.
data StopReason
    = StopPlanDone               -- all todos complete
    | StopNoveltyExhausted       -- 3 consecutive probes with no new facts
    | StopMaxProbesHit           -- safety cap
    | StopErrored Text           -- LLM error / probe error
    deriving stock (Eq, Show, Generic)

instance A.ToJSON StopReason
instance A.FromJSON StopReason


-- Running state of the inner loop.
data AgentState = AgentState
    { asTaskDir      :: FilePath
    , asBelief       :: Belief
    , asPlan         :: [PlanStage]
    , asCurrentStage :: Int                 -- index into asPlan
    , asHistory      :: [ProbeResult]       -- in reverse order (newest first)
    , asStrategy     :: ProbeStrategy
    , asProbeCap     :: Int                 -- safety: max probes
    , asNoveltyWindow :: Int                -- novelty exhaustion threshold
    }
    deriving stock (Eq, Show, Generic)

instance A.ToJSON AgentState
instance A.FromJSON AgentState


initialState :: FilePath -> Text -> AgentState
initialState dir tid = AgentState
    { asTaskDir       = dir
    , asBelief        = emptyBelief tid
    , asPlan          = []
    , asCurrentStage  = 0
    , asHistory       = []
    , asStrategy      = StrategyHybrid
    , asProbeCap      = 60
    , asNoveltyWindow = 3
    }
