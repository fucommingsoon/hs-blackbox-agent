{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Catalog
    ( batPlan
    , entrPlan
    , planByName
    ) where

import           Data.Text (Text)

import           Blackbox.DTC.Archetype.WatcherCli
import           Blackbox.DTC.Types


entrPlan :: DtcPlan
entrPlan = DtcPlan
    { dpName = "entr"
    , dpInputs = entrInputs
    , dpArchetypes = [WatcherCli, FileInputCli]
    , dpSteps = watcherCliSteps entrWatcherSpec
    }


entrInputs :: [CorpusInput]
entrInputs =
    [ SourceTree "corpus/probe-plan-seeds/entr/source/github"
    , UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
    , GraderTests "corpus/probe-plan-seeds/entr/grader"
    ]


entrWatcherSpec :: WatcherCliSpec
entrWatcherSpec = WatcherCliSpec
    { wcsName = "entr"
    , wcsSources =
        [ UpstreamTests "corpus/probe-plan-seeds/entr/source/github/system_test.sh"
        , GraderTests "corpus/probe-plan-seeds/entr/grader"
        ]
    , wcsNonInteractiveFlag = "-n"
    , wcsOneshotFlag = "-z"
    , wcsPostponeFlag = "-p"
    , wcsDirectoryWatchFlag = "-d"
    , wcsChangedPathToken = "/_"
    , wcsUsageNeedle = "usage:"
    , wcsNoRegularFilesNeedle = "No regular files"
    , wcsUnableToStatNeedle = "unable to stat"
    , wcsDirectoryAlteredNeedle = "directory altered"
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
            , psBehaviorSurfaces =
                [ BehaviorSurface "cli.args"
                , BehaviorSurface "stdout.usage"
                , BehaviorSurface "exit.code"
                ]
            , psSpecSurfaces =
                [ SpecSurface "run.cmd"
                , SpecSurface "expect.exit"
                , SpecSurface "expect.stdout"
                ]
            , psKind = SyncProbe
            , psSetup = []
            , psRun = RunSpec
                { rsCmd = "app --help"
                , rsStdin = Nothing
                , rsTimeoutMs = 3000
                , rsMode = RunSync
                , rsStopWhen = []
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
            , psBehaviorSurfaces =
                [ BehaviorSurface "http.request.get"
                , BehaviorSurface "http.response.status"
                , BehaviorSurface "http.response.body"
                ]
            , psSpecSurfaces =
                [ SpecSurface "fixture.http"
                , SpecSurface "run.cmd"
                , SpecSurface "trigger.http_ready"
                , SpecSurface "expect.exit"
                , SpecSurface "expect.stdout"
                ]
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
                , rsStopWhen = []
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
            , psBehaviorSurfaces =
                [ BehaviorSurface "http.request.put"
                , BehaviorSurface "http.request.body"
                , BehaviorSurface "http.response.status"
                , BehaviorSurface "http.response.body"
                ]
            , psSpecSurfaces =
                [ SpecSurface "fixture.http"
                , SpecSurface "run.cmd"
                , SpecSurface "trigger.http_ready"
                , SpecSurface "expect.exit"
                , SpecSurface "expect.stdout"
                ]
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
                , rsStopWhen = []
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
