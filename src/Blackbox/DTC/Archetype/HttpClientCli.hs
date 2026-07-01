{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Archetype.HttpClientCli
    ( HttpClientCliSpec (..)
    , httpClientCliRequirements
    , httpClientCliSteps
    ) where

import qualified Data.Text              as T
import           Data.Text              (Text)

import           Blackbox.DTC.Types


data HttpClientCliSpec = HttpClientCliSpec
    { hcsName                 :: Text
    , hcsSources              :: [CorpusInput]
    , hcsUsageNeedle          :: Text
    , hcsSuccessExitCode      :: Int
    , hcsGetMethodToken       :: Text
    , hcsPostMethodToken      :: Text
    , hcsPutMethodToken       :: Text
    , hcsJsonBodyItems        :: [Text]
    , hcsJsonBodyNeedles      :: [Text]
    , hcsQueryItems           :: [Text]
    , hcsQueryNeedles         :: [Text]
    , hcsHeaderItems          :: [Text]
    , hcsHeaderNeedles        :: [Text]
    , hcsFormFlag             :: Text
    , hcsFormItems            :: [Text]
    , hcsFormNeedles          :: [Text]
    , hcsRawBodyFlag          :: Text
    , hcsRawBodyValue         :: Text
    , hcsRawBodyNeedles       :: [Text]
    , hcsPrettyFalseFlag      :: Text
    , hcsBasicResponseNeedle  :: Text
    , hcsJsonResponseNeedle   :: Text
    , hcsStatusErrorNeedle    :: Text
    } deriving (Eq, Show)


httpClientCliRequirements :: ArchetypeRequirement
httpClientCliRequirements = ArchetypeRequirement
    { arArchetype = HttpClientCli
    , arPurpose = "Validate a CLI that constructs HTTP requests from command arguments, sends them to a server, and renders response evidence to stdout."
    , arFields =
        [ required "name"
            "Stable project or binary name used to prefix generated step ids."
            ["project catalog", "binary name", "task metadata"]
            ["bat"]
        , required "urlArgumentShape"
            "How the CLI accepts the request URL, including whether the URL is positional or behind a flag."
            ["README usage", "--help output", "source argument parser", "grader run helpers"]
            ["METHOD URL", "--url=<url>"]
        , required "methodArgumentShape"
            "How the CLI selects HTTP methods, including explicit method syntax and default method behavior."
            ["README usage", "--help output", "source method parser", "grader method tests"]
            ["GET URL", "-method=POST", "defaults to GET without data and POST with data"]
        , required "getMethodToken"
            "Concrete token used by this CLI flow to request HTTP GET."
            ["README examples", "source method parser", "grader method tests"]
            ["GET"]
        , required "postMethodToken"
            "Concrete token used by this CLI flow to request HTTP POST."
            ["README examples", "source method parser", "grader method tests"]
            ["POST"]
        , required "putMethodToken"
            "Concrete token used by this CLI flow to request HTTP PUT with JSON body items."
            ["README examples", "source method parser", "grader method tests"]
            ["PUT"]
        , required "jsonBodyItems"
            "Whitespace-separated CLI items used by the generated JSON body flow."
            ["README JSON examples", "source item parser", "grader request body tests"]
            ["name=John email=john@example.org"]
        , required "jsonBodyNeedles"
            "Comma-separated substrings the HTTP fixture must observe in the received request body."
            ["source item parser", "grader request body assertions", "chosen local fixture"]
            ["John,john@example.org"]
        , required "queryItems"
            "Whitespace-separated CLI items that should become query parameters for an explicit GET request."
            ["README request items", "source GET item handling", "grader query tests"]
            ["q=bat page=1"]
        , required "queryNeedles"
            "Comma-separated substrings the HTTP fixture must observe in the full request path for the query flow."
            ["source GET item handling", "grader query assertions", "chosen local fixture"]
            ["q=bat,page=1"]
        , required "headerItems"
            "Whitespace-separated CLI items that should become request headers."
            ["README request items", "source header parser", "grader header tests"]
            ["X-HSBB:works"]
        , required "headerNeedles"
            "Comma-separated substrings the HTTP fixture must observe in request headers."
            ["source header parser", "grader header assertions", "chosen local fixture"]
            ["X-HSBB: works"]
        , required "formFlag"
            "Concrete flag that switches request body encoding to form or multipart form."
            ["--help output", "README forms section", "source option parser", "grader form tests"]
            ["-form", "-f"]
        , required "formItems"
            "Whitespace-separated CLI items used by the generated form body flow."
            ["README forms section", "source form parser", "grader form tests"]
            ["name=John email=john@example.org"]
        , required "formNeedles"
            "Comma-separated substrings the HTTP fixture must observe in the form request body."
            ["source form parser", "grader form assertions", "chosen local fixture"]
            ["name=John,email=john%40example.org"]
        , required "rawBodyFlag"
            "Concrete flag prefix used to send raw request body bytes."
            ["--help output", "source option parser", "grader raw body tests"]
            ["-body="]
        , required "rawBodyValue"
            "Raw body payload used by the generated raw-body flow."
            ["README raw body examples", "source body flag parser", "grader raw body tests"]
            ["{\"custom\":\"data\"}"]
        , required "rawBodyNeedles"
            "Comma-separated substrings the HTTP fixture must observe in the raw request body."
            ["source body flag parser", "grader raw body assertions", "chosen local fixture"]
            ["custom,data"]
        , required "prettyFalseFlag"
            "Concrete flag/value that disables JSON pretty printing when the response body is JSON."
            ["--help output", "README output section", "source pretty flag", "grader pretty tests"]
            ["-pretty=false"]
        , required "basicResponseNeedle"
            "Stable response-body substring expected from the basic GET flow."
            ["local fixture expectation", "grader body-output assertions"]
            ["\"ok\""]
        , required "jsonResponseNeedle"
            "Stable response-body substring expected from the JSON body flow."
            ["local fixture expectation", "grader body-output assertions"]
            ["created"]
        , required "statusErrorNeedle"
            "Stable response-body substring expected when the server returns a non-2xx response."
            ["local fixture expectation", "grader status-code assertions", "source response handling"]
            ["not_found"]
        , required "successExitCode"
            "Exit code expected for a successful HTTP response fetch."
            ["grader assertions", "manual probe", "source error handling"]
            ["0"]
        , required "usageNeedle"
            "Stable usage/help text proving invalid or help invocation behavior."
            ["--help output", "source usage text", "grader help tests"]
            ["Usage:"]
        , optional "bodyItemShape"
            "How CLI arguments become request body fields, query parameters, raw JSON, or file-backed values."
            ["README request items", "source item parser", "grader data tests"]
            ["name=John", "age:=29", "field=@file.txt"]
        , optional "headerItemShape"
            "How CLI arguments become request headers."
            ["README request items", "source item parser", "grader header tests"]
            ["X-API-Token:123", "Authorization:Bearer token"]
        , optional "printFlag"
            "Flag that selects which request/response sections are rendered."
            ["--help output", "README output section", "source print parser", "grader output tests"]
            ["-print=b", "-print=Hhb"]
        , optional "authFlag"
            "Flag that supplies HTTP basic authentication material."
            ["--help output", "README authentication section", "source option parser", "grader auth tests"]
            ["-auth=user:pass", "-a user:pass"]
        , optional "downloadFlag"
            "Flag that switches response handling into download-to-file behavior."
            ["--help output", "README download examples", "source option parser", "grader download tests"]
            ["-download", "-d"]
        ]
    }


httpClientCliSteps :: HttpClientCliSpec -> [PlanStep]
httpClientCliSteps spec =
    [ helpStep spec
    , basicGetStep spec
    , autoGetStep spec
    , autoPostStep spec
    , queryItemsStep spec
    , headerItemsStep spec
    , jsonItemsStep spec
    , formItemsStep spec
    , rawBodyStep spec
    , statusBodyStep spec
    , prettyFalseStep spec
    ]


helpStep :: HttpClientCliSpec -> PlanStep
helpStep spec =
    step spec "help" "cli.help" SyncProbe []
        [bs "cli.args", bs "stdout.usage", bs "exit.code"]
        [ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec "app --help" Nothing 5000 RunSync [])
        []
        [ ExpectExit 2
        , ExpectStdoutContains (hcsUsageNeedle spec)
        ]
        [ "CLI shape guard from the HTTP client requirement contract: help/invalid invocation should expose stable usage."
        ]


basicGetStep :: HttpClientCliSpec -> PlanStep
basicGetStep spec =
    step spec "basic_get" "http.get_basic_response" FixtureProbe
        [ StartHttpFixture
            [ HttpRoute
                { hrMethod = "GET"
                , hrPath = "/hello"
                , hrStatus = 200
                , hrBody = "{\"status\":200,\"ok\":true}\n"
                , hrResponseContentType = "application/json"
                , hrRequestPathNeedles = []
                , hrRequestHeaderNeedles = []
                , hrRequestBodyNeedles = []
                }
            ]
        ]
        [bs "http.request.get", bs "http.response.status", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords ["app", hcsGetMethodToken spec, "http://127.0.0.1:${PORT}/hello"])
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains (hcsBasicResponseNeedle spec)
        ]
        [ "Fixture-backed GET flow generated from HttpClientCliSpec."
        ]


autoGetStep :: HttpClientCliSpec -> PlanStep
autoGetStep spec =
    step spec "auto_get" "http.default_get_without_items" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "GET" "/auto-get" 200 "{\"auto\":\"get\"}\n" [] [] []
            ]
        ]
        [bs "http.request.default_get", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            "app http://127.0.0.1:${PORT}/auto-get"
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains "auto"
        ]
        [ "Validates default method behavior without explicit METHOD or item arguments."
        ]


autoPostStep :: HttpClientCliSpec -> PlanStep
autoPostStep spec =
    step spec "auto_post" "http.default_post_with_items" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "POST" "/auto-post" 200 "{\"auto\":\"post\"}\n" [] [] (hcsJsonBodyNeedles spec)
            ]
        ]
        [bs "http.request.default_post", bs "http.request.body", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords (["app", "http://127.0.0.1:${PORT}/auto-post"] <> hcsJsonBodyItems spec))
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains "post"
        ]
        [ "Validates default POST inference when body items are present."
        ]


queryItemsStep :: HttpClientCliSpec -> PlanStep
queryItemsStep spec =
    step spec "query_items" "http.get_query_items" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "GET" "/search" 200 "{\"query\":true}\n" (hcsQueryNeedles spec) [] []
            ]
        ]
        [bs "http.request.get", bs "http.request.query", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords (["app", hcsGetMethodToken spec, "http://127.0.0.1:${PORT}/search"] <> hcsQueryItems spec))
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains "query"
        ]
        [ "Fixture verifies that GET request items are transported in the request path/query surface."
        ]


headerItemsStep :: HttpClientCliSpec -> PlanStep
headerItemsStep spec =
    step spec "header_items" "http.request_headers" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "GET" "/headers" 200 "{\"headers\":true}\n" [] (hcsHeaderNeedles spec) []
            ]
        ]
        [bs "http.request.get", bs "http.request.headers", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords (["app", hcsGetMethodToken spec, "http://127.0.0.1:${PORT}/headers"] <> hcsHeaderItems spec))
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains "headers"
        ]
        [ "Fixture verifies request header item parsing."
        ]


jsonItemsStep :: HttpClientCliSpec -> PlanStep
jsonItemsStep spec =
    step spec "json_items" "http.request_json_items" FixtureProbe
        [ StartHttpFixture
            [ HttpRoute
                { hrMethod = "PUT"
                , hrPath = "/users"
                , hrStatus = 201
                , hrBody = "{\"status\":201,\"created\":true}\n"
                , hrResponseContentType = "application/json"
                , hrRequestPathNeedles = []
                , hrRequestHeaderNeedles = []
                , hrRequestBodyNeedles = hcsJsonBodyNeedles spec
                }
            ]
        ]
        [bs "http.request.put", bs "http.request.body", bs "http.response.status", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords (["app", hcsPutMethodToken spec, "http://127.0.0.1:${PORT}/users"] <> hcsJsonBodyItems spec))
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains (hcsJsonResponseNeedle spec)
        ]
        [ "Fixture-backed JSON item flow generated from HttpClientCliSpec; fixture verifies request-body needles."
        ]


formItemsStep :: HttpClientCliSpec -> PlanStep
formItemsStep spec =
    step spec "form_items" "http.request_form_items" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "POST" "/form" 200 "{\"form\":true}\n" [] ["Content-Type: application/x-www-form-urlencoded"] (hcsFormNeedles spec)
            ]
        ]
        [bs "http.request.post", bs "http.request.form_body", bs "http.request.headers", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords (["app", hcsFormFlag spec, hcsPostMethodToken spec, "http://127.0.0.1:${PORT}/form"] <> hcsFormItems spec))
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains "form"
        ]
        [ "Fixture verifies form mode through both content type and body needles."
        ]


rawBodyStep :: HttpClientCliSpec -> PlanStep
rawBodyStep spec =
    step spec "raw_body" "http.request_raw_body" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "POST" "/raw" 200 "{\"raw\":true}\n" [] [] (hcsRawBodyNeedles spec)
            ]
        ]
        [bs "http.request.post", bs "http.request.raw_body", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords ["app", hcsRawBodyFlag spec <> shellSingleQuote (hcsRawBodyValue spec), hcsPostMethodToken spec, "http://127.0.0.1:${PORT}/raw"])
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains "raw"
        ]
        [ "Fixture verifies raw body flag transport without relying on response-only evidence."
        ]


statusBodyStep :: HttpClientCliSpec -> PlanStep
statusBodyStep spec =
    step spec "status_body" "http.response_non_2xx_body" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "GET" "/missing" 404 "{\"error\":\"not_found\"}\n" [] [] []
            ]
        ]
        [bs "http.request.get", bs "http.response.status_non_2xx", bs "http.response.body"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords ["app", hcsGetMethodToken spec, "http://127.0.0.1:${PORT}/missing"])
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains (hcsStatusErrorNeedle spec)
        ]
        [ "Validates that non-2xx HTTP responses still expose response-body evidence consistently."
        ]


prettyFalseStep :: HttpClientCliSpec -> PlanStep
prettyFalseStep spec =
    step spec "pretty_false" "http.response_json_no_pretty" FixtureProbe
        [ StartHttpFixture
            [ jsonRoute "GET" "/compact" 200 "{\"compact\":true}\n" [] [] []
            ]
        ]
        [bs "http.request.get", bs "http.response.json_rendering", bs "stdout.formatting"]
        [ss "fixture.http", ss "run.cmd", ss "trigger.http_ready", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (T.unwords ["app", hcsPrettyFalseFlag spec, hcsGetMethodToken spec, "http://127.0.0.1:${PORT}/compact"])
            Nothing
            5000
            RunSync
            []
        )
        [TriggerHttpReady]
        [ ExpectExit (hcsSuccessExitCode spec)
        , ExpectStdoutContains "{\"compact\":true}"
        ]
        [ "Validates an output formatting control without making formatting logic part of the DTC runtime."
        ]


jsonRoute :: Text -> Text -> Int -> Text -> [Text] -> [Text] -> [Text] -> HttpRoute
jsonRoute method path status body pathNeedles headerNeedles bodyNeedles =
    HttpRoute
        { hrMethod = method
        , hrPath = path
        , hrStatus = status
        , hrBody = body
        , hrResponseContentType = "application/json"
        , hrRequestPathNeedles = pathNeedles
        , hrRequestHeaderNeedles = headerNeedles
        , hrRequestBodyNeedles = bodyNeedles
        }


shellSingleQuote :: Text -> Text
shellSingleQuote value =
    "'" <> T.replace "'" "'\\''" value <> "'"


step
    :: HttpClientCliSpec
    -> Text
    -> Text
    -> StepKind
    -> [FixtureAction]
    -> [BehaviorSurface]
    -> [SpecSurface]
    -> RunSpec
    -> [TriggerAction]
    -> [Expectation]
    -> [Text]
    -> PlanStep
step spec suffix feature kind setup behaviorSurfaces specSurfaces run triggers expect notes =
    PlanStep
        { psId = hcsName spec <> "." <> suffix
        , psFeature = FeatureId feature
        , psBehaviorSurfaces = behaviorSurfaces
        , psSpecSurfaces = specSurfaces
        , psKind = kind
        , psSetup = setup
        , psRun = run
        , psTriggers = triggers
        , psExpect = expect
        , psSource = hcsSources spec
        , psNotes = notes
        }


bs :: Text -> BehaviorSurface
bs = BehaviorSurface


ss :: Text -> SpecSurface
ss = SpecSurface


required :: Text -> Text -> [Text] -> [Text] -> BindingField
required name description sourceHints examples =
    BindingField name Required description sourceHints examples


optional :: Text -> Text -> [Text] -> [Text] -> BindingField
optional name description sourceHints examples =
    BindingField name Optional description sourceHints examples
