{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- Haskell DTC is the deterministic testing core.  It is meant to absorb
-- reusable flows from upstream regression suites, PB graders, and later
-- project-specific runners while keeping LLM calls outside the hot path.
module Blackbox.DTC
    ( Archetype (..)
    , CorpusInput (..)
    , DtcPlan (..)
    , Expectation (..)
    , FeatureId (..)
    , FixtureAction (..)
    , HttpRoute (..)
    , PlanStep (..)
    , RunMode (..)
    , RunSpec (..)
    , StepKind (..)
    , TriggerAction (..)
    , batPlan
    , dtcFlowMermaid
    , entrPlan
    , planByName
    ) where

import qualified Data.Aeson as A
import           Data.Text  (Text)
import           GHC.Generics (Generic)


data CorpusInput
    = SourceTree FilePath
    | UpstreamTests FilePath
    | GraderTests FilePath
    deriving (Eq, Show, Generic)

instance A.ToJSON CorpusInput


newtype FeatureId = FeatureId { unFeatureId :: Text }
    deriving (Eq, Ord, Show, Generic)

instance A.ToJSON FeatureId


data Archetype
    = WatcherCli
    | HttpClientCli
    | FileInputCli
    | StdoutFormatterCli
    deriving (Eq, Show, Generic)

instance A.ToJSON Archetype


data DtcPlan = DtcPlan
    { dpName       :: Text
    , dpInputs     :: [CorpusInput]
    , dpArchetypes :: [Archetype]
    , dpSteps      :: [PlanStep]
    } deriving (Eq, Show, Generic)

instance A.ToJSON DtcPlan


data PlanStep = PlanStep
    { psId       :: Text
    , psFeature  :: FeatureId
    , psKind     :: StepKind
    , psSetup    :: [FixtureAction]
    , psRun      :: RunSpec
    , psTriggers :: [TriggerAction]
    , psExpect   :: [Expectation]
    , psSource   :: [CorpusInput]
    , psNotes    :: [Text]
    } deriving (Eq, Show, Generic)

instance A.ToJSON PlanStep


data StepKind
    = SyncProbe
    | AsyncProbe
    | FixtureProbe
    deriving (Eq, Show, Generic)

instance A.ToJSON StepKind


data FixtureAction
    = TouchFile FilePath
    | WriteFileText FilePath Text
    | AppendFileText FilePath Text
    | StartHttpFixture [HttpRoute]
    | SleepMs Int
    deriving (Eq, Show, Generic)

instance A.ToJSON FixtureAction


data HttpRoute = HttpRoute
    { hrMethod :: Text
    , hrPath   :: Text
    , hrStatus :: Int
    , hrBody   :: Text
    } deriving (Eq, Show, Generic)

instance A.ToJSON HttpRoute


data RunSpec = RunSpec
    { rsCmd       :: Text
    , rsStdin     :: Maybe Text
    , rsTimeoutMs :: Int
    , rsMode      :: RunMode
    } deriving (Eq, Show, Generic)

instance A.ToJSON RunSpec


data RunMode
    = RunSync
    | RunAsync
    deriving (Eq, Show, Generic)

instance A.ToJSON RunMode


data TriggerAction
    = TriggerAppend FilePath Text Int
    | TriggerHttpReady
    deriving (Eq, Show, Generic)

instance A.ToJSON TriggerAction


data Expectation
    = ExpectExit Int
    | ExpectStdoutContains Text
    | ExpectStderrContains Text
    | ExpectStdoutEmpty
    | ExpectStderrEmpty
    | ExpectCompletesWithinMs Int
    deriving (Eq, Show, Generic)

instance A.ToJSON Expectation


entrPlan :: DtcPlan
entrPlan = DtcPlan
    { dpName = "entr"
    , dpInputs =
        [ SourceTree "corpus/probe-plan-seeds/entr/source/github"
        , UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
        , GraderTests "corpus/probe-plan-seeds/entr/grader"
        ]
    , dpArchetypes = [WatcherCli, FileInputCli]
    , dpSteps =
        [ PlanStep
            { psId = "entr.no_regular_files"
            , psFeature = FeatureId "exit.no_regular_files"
            , psKind = SyncProbe
            , psSetup = []
            , psRun = RunSpec
                { rsCmd = "app -z echo ok"
                , rsStdin = Just "/tmp/hsbb-entr-missing\n"
                , rsTimeoutMs = 3000
                , rsMode = RunSync
                }
            , psTriggers = []
            , psExpect =
                [ ExpectExit 1
                , ExpectStderrContains "unable to stat"
                , ExpectStderrContains "No regular files"
                ]
            , psSource =
                [ UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
                , GraderTests "corpus/probe-plan-seeds/entr/grader"
                ]
            , psNotes =
                [ "Error-path flow. It proves input validation, not stdout passthrough."
                ]
            }
        , PlanStep
            { psId = "entr.stdout_child_passthrough"
            , psFeature = FeatureId "io.stdout_child_passthrough"
            , psKind = SyncProbe
            , psSetup = [TouchFile "/tmp/hsbb-entr-file"]
            , psRun = RunSpec
                { rsCmd = "app -n -z echo ok"
                , rsStdin = Just "/tmp/hsbb-entr-file\n"
                , rsTimeoutMs = 3000
                , rsMode = RunSync
                }
            , psTriggers = []
            , psExpect =
                [ ExpectExit 0
                , ExpectStdoutContains "ok"
                ]
            , psSource =
                [ UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
                , GraderTests "corpus/probe-plan-seeds/entr/grader"
                ]
            , psNotes =
                [ "Creates the watched file before probing; this avoids treating setup failure as program behavior."
                ]
            }
        , PlanStep
            { psId = "entr.file_change_trigger"
            , psFeature = FeatureId "watcher.reacts_to_file_change"
            , psKind = AsyncProbe
            , psSetup = [TouchFile "/tmp/hsbb-entr-watch"]
            , psRun = RunSpec
                { rsCmd = "app -n echo changed"
                , rsStdin = Just "/tmp/hsbb-entr-watch\n"
                , rsTimeoutMs = 4000
                , rsMode = RunAsync
                }
            , psTriggers = [TriggerAppend "/tmp/hsbb-entr-watch" "x\n" 300]
            , psExpect =
                [ ExpectStdoutContains "changed"
                , ExpectCompletesWithinMs 4000
                ]
            , psSource =
                [ UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
                , GraderTests "corpus/probe-plan-seeds/entr/grader"
                ]
            , psNotes =
                [ "Canonical watcher flow: async process plus file mutation trigger."
                ]
            }
        ]
    }


batPlan :: DtcPlan
batPlan = DtcPlan
    { dpName = "bat"
    , dpInputs =
        [ SourceTree "corpus/probe-plan-seeds/bat/source/github"
        , UpstreamTests "corpus/probe-plan-seeds/bat/source/github/httplib/httplib_test.go"
        , GraderTests "corpus/probe-plan-seeds/bat/grader"
        ]
    , dpArchetypes = [HttpClientCli, StdoutFormatterCli]
    , dpSteps =
        [ PlanStep
            { psId = "bat.help"
            , psFeature = FeatureId "cli.help"
            , psKind = SyncProbe
            , psSetup = []
            , psRun = RunSpec
                { rsCmd = "app --help"
                , rsStdin = Nothing
                , rsTimeoutMs = 3000
                , rsMode = RunSync
                }
            , psTriggers = []
            , psExpect =
                [ ExpectExit 2
                , ExpectStdoutContains "Usage"
                ]
            , psSource =
                [ SourceTree "corpus/probe-plan-seeds/bat/source/github/bat.go"
                , GraderTests "corpus/probe-plan-seeds/bat/grader"
                ]
            , psNotes =
                [ "Upstream tests barely cover the CLI; this flow is grader-led and source-confirmed."
                ]
            }
        , PlanStep
            { psId = "bat.basic_get"
            , psFeature = FeatureId "http.get_basic_response"
            , psKind = FixtureProbe
            , psSetup =
                [ StartHttpFixture
                    [ HttpRoute
                        { hrMethod = "GET"
                        , hrPath = "/hello"
                        , hrStatus = 200
                        , hrBody = "{\"ok\":true}\n"
                        }
                    ]
                ]
            , psRun = RunSpec
                { rsCmd = "app GET http://127.0.0.1:${PORT}/hello"
                , rsStdin = Nothing
                , rsTimeoutMs = 5000
                , rsMode = RunSync
                }
            , psTriggers = [TriggerHttpReady]
            , psExpect =
                [ ExpectExit 0
                , ExpectStdoutContains "200"
                , ExpectStdoutContains "\"ok\""
                ]
            , psSource =
                [ UpstreamTests "corpus/probe-plan-seeds/bat/source/github/httplib/httplib_test.go"
                , GraderTests "corpus/probe-plan-seeds/bat/grader"
                ]
            , psNotes =
                [ "Requires runtime-managed local HTTP fixture and port interpolation."
                ]
            }
        , PlanStep
            { psId = "bat.json_items"
            , psFeature = FeatureId "http.request_json_items"
            , psKind = FixtureProbe
            , psSetup =
                [ StartHttpFixture
                    [ HttpRoute
                        { hrMethod = "PUT"
                        , hrPath = "/users"
                        , hrStatus = 201
                        , hrBody = "{\"created\":true}\n"
                        }
                    ]
                ]
            , psRun = RunSpec
                { rsCmd = "app PUT http://127.0.0.1:${PORT}/users name=John email=john@example.org"
                , rsStdin = Nothing
                , rsTimeoutMs = 5000
                , rsMode = RunSync
                }
            , psTriggers = [TriggerHttpReady]
            , psExpect =
                [ ExpectExit 0
                , ExpectStdoutContains "201"
                , ExpectStdoutContains "created"
                ]
            , psSource =
                [ SourceTree "corpus/probe-plan-seeds/bat/source/github/http.go"
                , GraderTests "corpus/probe-plan-seeds/bat/grader"
                ]
            , psNotes =
                [ "Runtime should capture inbound request body in the next implementation pass."
                ]
            }
        ]
    }


planByName :: Text -> Maybe DtcPlan
planByName "entr" = Just entrPlan
planByName "bat"  = Just batPlan
planByName _      = Nothing


dtcFlowMermaid :: Text
dtcFlowMermaid = mconcat
    [ "## Build Flow\n"
    , "```mermaid\n"
    , "flowchart TD\n"
    , "    Corpus[Seed corpus<br/>source + upstream tests + grader] --> Read\n"
    , "    Read[Haskell readers<br/>source/test/grader adapters] --> Surface\n"
    , "    Surface[Behavior surfaces<br/>CLI flags / IO channels / fixtures / errors] --> Archetype\n"
    , "    Archetype[Flow archetypes<br/>watcher CLI / HTTP client CLI / formatter CLI] --> Calibrate\n"
    , "    Calibrate{Optional LLM calibration<br/>business direction + priority only} --> Plan\n"
    , "    Plan[DTC plan library<br/>PlanStep fixture/run/trigger/expect/source] --> Review\n"
    , "    Review[Human/code review<br/>remove low-value or overfit flows] --> Versioned[Versioned Haskell plan]\n"
    , "```\n\n"
    , "## Agent Run Flow\n"
    , "```mermaid\n"
    , "flowchart TD\n"
    , "    Input[DTC plan + app binary] --> Select\n"
    , "    Select[Select PlanStep] --> Setup\n"
    , "    Setup[Fixture setup<br/>files / HTTP server / temp workspace] --> Run\n"
    , "    Run[Run app args<br/>stdin + timeout + sync/async process] --> Trigger\n"
    , "    Trigger[Trigger actions<br/>file append / HTTP ready / future events] --> Capture\n"
    , "    Capture[Capture evidence<br/>stdout / stderr / exit / duration / artifacts] --> Verify\n"
    , "    Verify[Haskell verifier<br/>expectations -> pass/fail/unsupported] --> Result\n"
    , "    Result[DTC run result JSON<br/>per-step verdict + gaps] --> Report\n"
    , "    Report{Optional LLM report<br/>organize findings only} --> Done[Verified feature report]\n"
    , "```\n"
    ]
