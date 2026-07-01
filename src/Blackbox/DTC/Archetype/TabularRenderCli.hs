{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Archetype.TabularRenderCli
    ( ErrorRenderSpec (..)
    , StdinRenderSpec (..)
    , TabularRenderCliSpec (..)
    , tabularRenderCliRequirements
    , tabularRenderCliSteps
    ) where

import           Data.Text              (Text)

import           Blackbox.DTC.Types


data TabularRenderCliSpec = TabularRenderCliSpec
    { trsName                   :: Text
    , trsSources                :: [CorpusInput]
    , trsSuccessExitCode        :: Int
    , trsUsageNeedle            :: Text
    , trsCsvStdinText           :: Text
    , trsCsvStdinNeedles        :: [Text]
    , trsFileInputPath          :: FilePath
    , trsFileInputText          :: Text
    , trsFileRenderCommand      :: Text
    , trsFileRenderNeedles      :: [Text]
    , trsTsvStdinText           :: Text
    , trsTsvRenderCommand       :: Text
    , trsTsvRenderNeedles       :: [Text]
    , trsMissingFileCommand     :: Text
    , trsMissingFileErrorNeedle :: Text
    , trsVersionCommand         :: Maybe Text
    , trsVersionNeedle          :: Maybe Text
    , trsNoHeaderRender         :: Maybe StdinRenderSpec
    , trsSequenceRender         :: Maybe StdinRenderSpec
    , trsLayoutRender           :: Maybe StdinRenderSpec
    , trsWideCharRender         :: Maybe StdinRenderSpec
    , trsMalformedInput         :: Maybe ErrorRenderSpec
    } deriving (Eq, Show)


data StdinRenderSpec = StdinRenderSpec
    { srsCommand :: Text
    , srsInput   :: Text
    , srsNeedles :: [Text]
    } deriving (Eq, Show)


data ErrorRenderSpec = ErrorRenderSpec
    { ersCommand      :: Text
    , ersInput        :: Text
    , ersExitCode     :: Int
    , ersStderrNeedle :: Text
    } deriving (Eq, Show)


tabularRenderCliRequirements :: ArchetypeRequirement
tabularRenderCliRequirements = ArchetypeRequirement
    { arArchetype = TabularRenderCli
    , arPurpose = "Validate a CLI that reads delimited tabular data from stdin or files and renders formatted table output with dialect/style flags and file error handling."
    , arFields =
        [ required "name"
            "Stable project or binary name used to prefix generated step ids."
            ["task metadata", "binary name", "help output"]
            ["table-viewer"]
        , required "successExitCode"
            "Exit code expected for successful render commands."
            ["grader assertions", "manual probes", "source error handling"]
            ["0"]
        , required "usageNeedle"
            "Stable help text proving this is the expected tabular rendering CLI."
            ["--help output", "source argument parser", "grader help tests"]
            ["Usage:"]
        , required "csvStdinText"
            "Small CSV fixture sent through stdin for the default render flow."
            ["README examples", "grader stdin tests", "manual probe"]
            ["name,age\\nAda,36\\nBob,41\\n"]
        , required "csvStdinNeedles"
            "Comma-separated substrings expected in stdout for the default stdin CSV flow."
            ["manual probe output", "grader stdout assertions"]
            ["name,Ada,Bob"]
        , required "fileInputPath"
            "Fixture file path for file-input rendering. Use ${WORK}/... for isolation."
            ["grader file-input tests", "manual probe"]
            ["${WORK}/input.csv"]
        , required "fileInputText"
            "Delimited fixture text written before the file-input render command."
            ["README examples", "grader delimiter tests", "manual probe"]
            ["a;b\\n1;2\\n"]
        , required "fileRenderCommand"
            "Command tail that renders the fixture file and any dialect/style flags. May reference ${WORK}."
            ["--help output", "source argument parser", "grader delimiter/style tests"]
            ["-d ';' -s none ${WORK}/input.csv"]
        , required "fileRenderNeedles"
            "Comma-separated substrings expected in stdout for the file render flow."
            ["manual probe output", "grader stdout assertions"]
            ["a,b,1,2"]
        , required "tsvStdinText"
            "Small TSV fixture sent through stdin for the alternate delimiter/style flow."
            ["grader tsv tests", "--help output", "manual probe"]
            ["name\\tage\\nAda\\t36\\n"]
        , required "tsvRenderCommand"
            "Command tail that selects TSV or an equivalent delimiter plus a non-default style."
            ["--help output", "source argument parser", "grader tsv/style tests"]
            ["-t -s markdown"]
        , required "tsvRenderNeedles"
            "Comma-separated substrings expected in stdout for the TSV/style flow."
            ["manual probe output", "grader stdout assertions"]
            ["| name | age |,| Ada"]
        , required "missingFileCommand"
            "Command tail that attempts to read a nonexistent file."
            ["grader error tests", "manual probe"]
            ["${WORK}/missing.csv"]
        , required "missingFileErrorNeedle"
            "Stable substring expected on stderr for nonexistent file handling."
            ["manual probe stderr", "source error handling", "grader error tests"]
            ["No such file or directory"]
        , optional "versionCommand"
            "Command tail used to print version information, if supported."
            ["grader version tests", "--help output", "source parser"]
            ["--version"]
        , optional "versionNeedle"
            "Stable substring expected from version output, if supported."
            ["manual probe", "grader version assertions"]
            ["1.0"]
        , optional "noHeaderCommand"
            "Command tail that renders stdin data while treating all rows as body rows rather than consuming the first row as headers."
            ["--help output", "source header handling", "grader no-header tests"]
            ["-H -s ascii", "--no-header"]
        , optional "noHeaderInputText"
            "Small delimited stdin fixture for the no-header flow."
            ["grader no-header fixtures", "manual probe"]
            ["Ada,36\\nBob,41\\n"]
        , optional "noHeaderNeedles"
            "Comma-separated stdout substrings proving first-row-as-data behavior."
            ["manual probe output", "grader stdout assertions"]
            ["Ada,Bob"]
        , optional "sequenceCommand"
            "Command tail that renders a row-number or sequence column, if supported."
            ["--help output", "source row-number option", "grader line-number tests"]
            ["-n", "--number"]
        , optional "sequenceInputText"
            "Small delimited stdin fixture for the sequence/row-number flow."
            ["grader line-number fixtures", "manual probe"]
            ["name,age\\nAda,36\\nBob,41\\n"]
        , optional "sequenceNeedles"
            "Comma-separated stdout substrings proving sequence column behavior."
            ["manual probe output", "grader stdout assertions"]
            ["#,1,Ada,2,Bob"]
        , optional "layoutCommand"
            "Command tail that exercises generic layout controls such as padding, indentation, or column alignment."
            ["--help output", "source layout/style builder", "grader formatting tests"]
            ["-p 0 -i 2 --header-align left --body-align right"]
        , optional "layoutInputText"
            "Small delimited stdin fixture for the layout-control flow."
            ["grader formatting fixtures", "manual probe"]
            ["a,b\\n1,22\\n"]
        , optional "layoutNeedles"
            "Comma-separated stdout substrings proving layout controls took effect."
            ["manual probe output", "grader stdout assertions"]
            ["  ┌,│a│b,│1│22"]
        , optional "wideCharCommand"
            "Command tail that renders wide Unicode characters, if the CLI claims Unicode/CJK/emoji-aware table layout."
            ["project description", "source width calculation", "grader unicode tests"]
            [""]
        , optional "wideCharInputText"
            "Small delimited stdin fixture containing wide characters."
            ["grader unicode fixtures", "manual probe"]
            ["name,city,emoji\\n李磊,四川省成都市,💍\\n"]
        , optional "wideCharNeedles"
            "Comma-separated stdout substrings proving wide-character cells survive rendering."
            ["manual probe output", "grader stdout assertions"]
            ["李磊,四川省成都市,💍"]
        , optional "malformedInputCommand"
            "Command tail used with malformed delimited stdin to exercise parser/data error handling."
            ["source parser errors", "grader malformed-input tests"]
            [""]
        , optional "malformedInputText"
            "Malformed delimited stdin fixture that should produce a parser/data error."
            ["grader malformed-input fixtures", "manual probe"]
            ["a,b\\n1,2,3\\n"]
        , optional "malformedInputExitCode"
            "Expected exit code for malformed input."
            ["manual probe", "source error handling", "grader assertions"]
            ["1"]
        , optional "malformedInputStderrNeedle"
            "Stable stderr substring expected for malformed input."
            ["manual probe stderr", "source error handling", "grader assertions"]
            ["CSV error"]
        ]
    }


tabularRenderCliSteps :: TabularRenderCliSpec -> [PlanStep]
tabularRenderCliSteps spec =
    [ helpStep spec
    , csvStdinStep spec
    , fileRenderStep spec
    , tsvRenderStep spec
    , missingFileStep spec
    ]
    <> versionSteps spec
    <> maybe [] ((: []) . noHeaderStep spec) (trsNoHeaderRender spec)
    <> maybe [] ((: []) . sequenceStep spec) (trsSequenceRender spec)
    <> maybe [] ((: []) . layoutStep spec) (trsLayoutRender spec)
    <> maybe [] ((: []) . wideCharStep spec) (trsWideCharRender spec)
    <> maybe [] ((: []) . malformedInputStep spec) (trsMalformedInput spec)


helpStep :: TabularRenderCliSpec -> PlanStep
helpStep spec =
    step spec "help" "cli.tabular_help" SyncProbe []
        [bs "cli.help", bs "cli.options", bs "stdout.usage", bs "exit.code"]
        [ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec "app --help" Nothing 5000 RunSync [])
        []
        [ ExpectExit (trsSuccessExitCode spec)
        , ExpectStdoutContains (trsUsageNeedle spec)
        ]
        [ "Top-level usage guard generated from TabularRenderCliSpec."
        ]


csvStdinStep :: TabularRenderCliSpec -> PlanStep
csvStdinStep spec =
    step spec "stdin_csv" "table.render_stdin_csv" SyncProbe []
        [bs "stdin.input", bs "table.csv", bs "stdout.table", bs "exit.code"]
        [ss "stdin.shape", ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec "app" (Just (trsCsvStdinText spec)) 5000 RunSync [])
        []
        (ExpectExit (trsSuccessExitCode spec) : map ExpectStdoutContains (trsCsvStdinNeedles spec))
        [ "Validates default delimited data rendering from stdin."
        ]


fileRenderStep :: TabularRenderCliSpec -> PlanStep
fileRenderStep spec =
    step spec "file_render" "table.render_file_dialect_style" SyncProbe
        [ WriteFileText (trsFileInputPath spec) (trsFileInputText spec)
        ]
        [bs "file.input", bs "table.delimiter", bs "table.style", bs "stdout.table", bs "exit.code"]
        [ss "fixture.file", ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec ("app " <> trsFileRenderCommand spec) Nothing 5000 RunSync [])
        []
        (ExpectExit (trsSuccessExitCode spec) : map ExpectStdoutContains (trsFileRenderNeedles spec))
        [ "Validates file input plus non-default delimiter/style options."
        ]


tsvRenderStep :: TabularRenderCliSpec -> PlanStep
tsvRenderStep spec =
    step spec "stdin_tsv_style" "table.render_stdin_tsv_style" SyncProbe []
        [bs "stdin.input", bs "table.tsv", bs "table.style", bs "stdout.table", bs "exit.code"]
        [ss "stdin.shape", ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec ("app " <> trsTsvRenderCommand spec) (Just (trsTsvStdinText spec)) 5000 RunSync [])
        []
        (ExpectExit (trsSuccessExitCode spec) : map ExpectStdoutContains (trsTsvRenderNeedles spec))
        [ "Validates alternate delimiter input and a non-default table rendering style."
        ]


missingFileStep :: TabularRenderCliSpec -> PlanStep
missingFileStep spec =
    step spec "missing_file" "table.input_file_missing" SyncProbe []
        [bs "file.error", bs "stderr.error", bs "exit.code"]
        [ss "run.cmd", ss "expect.exit", ss "expect.stderr"]
        (RunSpec ("app " <> trsMissingFileCommand spec) Nothing 5000 RunSync [])
        []
        [ ExpectExit 1
        , ExpectStderrContains (trsMissingFileErrorNeedle spec)
        ]
        [ "Validates a real file-input error path instead of only happy-path rendering."
        ]


versionSteps :: TabularRenderCliSpec -> [PlanStep]
versionSteps spec =
    case (trsVersionCommand spec, trsVersionNeedle spec) of
        (Just command, Just needle) ->
            [ step spec "version" "cli.version" SyncProbe []
                [bs "cli.version", bs "stdout.metadata", bs "exit.code"]
                [ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
                (RunSpec ("app " <> command) Nothing 5000 RunSync [])
                []
                [ ExpectExit (trsSuccessExitCode spec)
                , ExpectStdoutContains needle
                ]
                [ "Optional version metadata guard generated from TabularRenderCliSpec."
                ]
            ]
        _ -> []


noHeaderStep :: TabularRenderCliSpec -> StdinRenderSpec -> PlanStep
noHeaderStep spec renderSpec =
    stdinRenderStep spec renderSpec "no_header" "table.render_no_header"
        [bs "stdin.input", bs "table.no_header", bs "stdout.table", bs "exit.code"]
        [ "Validates first-row-as-data behavior for tabular CLIs that support disabling header parsing."
        ]


sequenceStep :: TabularRenderCliSpec -> StdinRenderSpec -> PlanStep
sequenceStep spec renderSpec =
    stdinRenderStep spec renderSpec "sequence_column" "table.render_sequence_column"
        [bs "stdin.input", bs "table.sequence_column", bs "stdout.table", bs "exit.code"]
        [ "Validates row-number or sequence-column rendering when the CLI exposes that generic table option."
        ]


layoutStep :: TabularRenderCliSpec -> StdinRenderSpec -> PlanStep
layoutStep spec renderSpec =
    stdinRenderStep spec renderSpec "layout_controls" "table.render_layout_controls"
        [bs "stdin.input", bs "table.padding", bs "table.indent", bs "table.alignment", bs "stdout.table", bs "exit.code"]
        [ "Validates generic layout controls such as padding, indentation, and alignment without assuming a project-specific style."
        ]


wideCharStep :: TabularRenderCliSpec -> StdinRenderSpec -> PlanStep
wideCharStep spec renderSpec =
    stdinRenderStep spec renderSpec "wide_characters" "table.render_wide_characters"
        [bs "stdin.input", bs "table.unicode_width", bs "stdout.table", bs "exit.code"]
        [ "Validates wide-character table rendering for CLIs whose source or docs claim Unicode-aware layout."
        ]


stdinRenderStep
    :: TabularRenderCliSpec
    -> StdinRenderSpec
    -> Text
    -> Text
    -> [BehaviorSurface]
    -> [Text]
    -> PlanStep
stdinRenderStep spec renderSpec suffixText feature behavior notes =
    step spec suffixText feature SyncProbe []
        behavior
        [ss "stdin.shape", ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec ("app " <> srsCommand renderSpec) (Just (srsInput renderSpec)) 5000 RunSync [])
        []
        (ExpectExit (trsSuccessExitCode spec) : map ExpectStdoutContains (srsNeedles renderSpec))
        notes


malformedInputStep :: TabularRenderCliSpec -> ErrorRenderSpec -> PlanStep
malformedInputStep spec errorSpec =
    step spec "malformed_input" "table.input_malformed_error" SyncProbe []
        [bs "stdin.input", bs "table.parser_error", bs "stderr.error", bs "exit.code"]
        [ss "stdin.shape", ss "run.cmd", ss "expect.exit", ss "expect.stderr"]
        (RunSpec ("app " <> ersCommand errorSpec) (Just (ersInput errorSpec)) 5000 RunSync [])
        []
        [ ExpectExit (ersExitCode errorSpec)
        , ExpectStderrContains (ersStderrNeedle errorSpec)
        ]
        [ "Validates malformed delimited input handling through a parser/data error path."
        ]


step
    :: TabularRenderCliSpec
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
step spec suffixText feature kind setup behaviorSurfaces specSurfaces run triggers expect notes =
    PlanStep
        { psId = trsName spec <> "." <> suffixText
        , psFeature = FeatureId feature
        , psBehaviorSurfaces = behaviorSurfaces
        , psSpecSurfaces = specSurfaces
        , psKind = kind
        , psSetup = setup
        , psRun = run
        , psTriggers = triggers
        , psExpect = expect
        , psSource = trsSources spec
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
