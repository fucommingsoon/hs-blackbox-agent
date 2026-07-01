{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Archetype.StructuredSubcommandCli
    ( StructuredSubcommandCliSpec (..)
    , structuredSubcommandCliRequirements
    , structuredSubcommandCliSteps
    ) where

import qualified Data.Text              as T
import           Data.Text              (Text)

import           Blackbox.DTC.Types


data StructuredSubcommandCliSpec = StructuredSubcommandCliSpec
    { scsName                 :: Text
    , scsSources              :: [CorpusInput]
    , scsSuccessExitCode      :: Int
    , scsUsageNeedle          :: Text
    , scsTopLevelNeedles      :: [Text]
    , scsNestedHelpCommands   :: [Text]
    , scsCompletionCommand    :: Text
    , scsCompletionNeedle     :: Text
    , scsVersionCommand       :: Text
    , scsVersionNeedle        :: Text
    , scsLicenseCommand       :: Text
    , scsLicenseNeedle        :: Text
    , scsFormatInputPath      :: FilePath
    , scsFormatInputText      :: Text
    , scsFormatCommand        :: Text
    , scsFormatCheckNeedle    :: Text
    , scsMigrationDirPath     :: FilePath
    , scsMigrationNewCommand  :: Text
    , scsMigrationFileNeedle  :: Text
    } deriving (Eq, Show)


structuredSubcommandCliRequirements :: ArchetypeRequirement
structuredSubcommandCliRequirements = ArchetypeRequirement
    { arArchetype = StructuredSubcommandCli
    , arPurpose = "Validate a CLI organized around top-level and nested subcommands, including help dispatch, shell completion, stable metadata commands, and file-system side effects."
    , arFields =
        [ required "name"
            "Stable project or binary name used to prefix generated step ids."
            ["task metadata", "binary name", "help output"]
            ["atlas"]
        , required "successExitCode"
            "Exit code expected for successful commands."
            ["grader assertions", "manual probes", "source command runner"]
            ["0"]
        , required "usageNeedle"
            "Stable top-level help text proving this is the expected CLI."
            ["--help output", "source cobra/argparse setup", "grader help tests"]
            ["Usage:"]
        , required "topLevelNeedles"
            "Comma-separated substrings expected in top-level help for important subcommands."
            ["--help output", "grader help tests", "source command registration"]
            ["migrate,schema,completion,version,license"]
        , required "nestedHelpCommands"
            "Comma-separated subcommands whose --help output should be routed correctly."
            ["grader nested help tests", "--help output", "source command tree"]
            ["migrate,schema"]
        , required "completionCommand"
            "Command tail used to generate shell completion output."
            ["grader completion tests", "--help output", "source completion command"]
            ["completion bash"]
        , required "completionNeedle"
            "Stable substring expected from completion output."
            ["grader completion assertions", "manual probe"]
            ["# bash completion"]
        , required "versionCommand"
            "Command tail used to print version information."
            ["grader version tests", "--help output", "source version command"]
            ["version"]
        , required "versionNeedle"
            "Stable substring expected from version output."
            ["grader version assertions", "manual probe"]
            ["atlas unofficial version"]
        , required "licenseCommand"
            "Command tail used to print license information."
            ["grader license tests", "--help output", "source license command"]
            ["license"]
        , required "licenseNeedle"
            "Stable substring expected from license output."
            ["grader license assertions", "manual probe"]
            ["LICENSE"]
        , required "formatInputPath"
            "Fixture file path for a formatter-style side effect. Use ${WORK}/... for isolation."
            ["grader formatting tests", "source formatter command", "manual probe"]
            ["${WORK}/schema.hcl"]
        , required "formatInputText"
            "Unformatted fixture text written before running the format command."
            ["grader formatting fixtures", "source parser examples", "manual probe"]
            ["schema \"users\"{\\ncolumn \"id\"{type=int}\\n}\\n"]
        , required "formatCommand"
            "Command tail that formats the fixture file in place. May reference ${WORK}."
            ["grader formatting tests", "--help output", "manual probe"]
            ["schema fmt ${WORK}/schema.hcl"]
        , required "formatCheckNeedle"
            "Substring that must appear in the formatted file after the command runs."
            ["grader formatting assertions", "manual probe"]
            ["type = int"]
        , required "migrationDirPath"
            "Fixture directory path for migration/file-generation side effects. Use ${WORK}/... for isolation."
            ["grader migration tests", "source migration command", "manual probe"]
            ["${WORK}/migrations"]
        , required "migrationNewCommand"
            "Command tail that creates a migration file and manifest. May reference ${WORK}."
            ["grader migration-new tests", "--help output", "manual probe"]
            ["migrate new --dir file://${WORK}/migrations create_users"]
        , required "migrationFileNeedle"
            "Substring expected in generated migration file names."
            ["grader migration-new assertions", "manual probe"]
            ["create_users"]
        ]
    }


structuredSubcommandCliSteps :: StructuredSubcommandCliSpec -> [PlanStep]
structuredSubcommandCliSteps spec =
    [ topLevelHelpStep spec
    , versionStep spec
    , licenseStep spec
    , completionStep spec
    ]
    <> map (nestedHelpStep spec) (scsNestedHelpCommands spec)
    <> [ formatFileStep spec
       , migrationNewStep spec
       ]


topLevelHelpStep :: StructuredSubcommandCliSpec -> PlanStep
topLevelHelpStep spec =
    step spec "help" "cli.structured_help" SyncProbe []
        [bs "cli.help", bs "cli.subcommands", bs "stdout.usage", bs "exit.code"]
        [ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec "app --help" Nothing 5000 RunSync [])
        []
        (ExpectExit (scsSuccessExitCode spec)
            : ExpectStdoutContains (scsUsageNeedle spec)
            : map ExpectStdoutContains (scsTopLevelNeedles spec)
        )
        [ "Top-level command tree guard generated from StructuredSubcommandCliSpec."
        ]


nestedHelpStep :: StructuredSubcommandCliSpec -> Text -> PlanStep
nestedHelpStep spec command =
    step spec ("help_" <> suffix command) "cli.nested_help" SyncProbe []
        [bs "cli.nested_help", bs "cli.subcommand.routing", bs "stdout.usage", bs "exit.code"]
        [ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec (T.unwords ["app", command, "--help"]) Nothing 5000 RunSync [])
        []
        [ ExpectExit (scsSuccessExitCode spec)
        , ExpectStdoutContains (scsUsageNeedle spec)
        , ExpectStdoutContains command
        ]
        [ "Nested help routing guard for a structured subcommand CLI."
        ]


versionStep :: StructuredSubcommandCliSpec -> PlanStep
versionStep spec =
    simpleCommandStep spec "version" "cli.version" (scsVersionCommand spec) (scsVersionNeedle spec)
        [bs "cli.version", bs "stdout.metadata", bs "exit.code"]


licenseStep :: StructuredSubcommandCliSpec -> PlanStep
licenseStep spec =
    simpleCommandStep spec "license" "cli.license" (scsLicenseCommand spec) (scsLicenseNeedle spec)
        [bs "cli.license", bs "stdout.metadata", bs "exit.code"]


completionStep :: StructuredSubcommandCliSpec -> PlanStep
completionStep spec =
    simpleCommandStep spec "completion" "cli.completion" (scsCompletionCommand spec) (scsCompletionNeedle spec)
        [bs "cli.completion", bs "stdout.script", bs "exit.code"]


simpleCommandStep
    :: StructuredSubcommandCliSpec
    -> Text
    -> Text
    -> Text
    -> Text
    -> [BehaviorSurface]
    -> PlanStep
simpleCommandStep spec suffixText feature command needle behaviorSurfaces =
    step spec suffixText feature SyncProbe []
        behaviorSurfaces
        [ss "run.cmd", ss "expect.exit", ss "expect.stdout"]
        (RunSpec ("app " <> command) Nothing 5000 RunSync [])
        []
        [ ExpectExit (scsSuccessExitCode spec)
        , ExpectStdoutContains needle
        ]
        [ "Stable metadata/subcommand behavior generated from StructuredSubcommandCliSpec."
        ]


formatFileStep :: StructuredSubcommandCliSpec -> PlanStep
formatFileStep spec =
    step spec "format_file" "file.format_in_place" SyncProbe
        [ WriteFileText (scsFormatInputPath spec) (scsFormatInputText spec)
        ]
        [bs "file.input", bs "file.format_in_place", bs "cli.file_argument", bs "exit.code"]
        [ss "fixture.file", ss "run.cmd", ss "expect.exit", ss "artifact.file"]
        (RunSpec
            (T.unwords
                [ "app"
                , scsFormatCommand spec
                , "&& grep -q"
                , shellSingleQuote (scsFormatCheckNeedle spec)
                , T.pack (scsFormatInputPath spec)
                , "&& echo format-ok"
                ]
            )
            Nothing
            5000
            RunSync
            []
        )
        []
        [ ExpectExit (scsSuccessExitCode spec)
        , ExpectStdoutContains "format-ok"
        ]
        [ "Validates an in-place file formatting side effect with shell-level artifact check until DTC gains native file expectations."
        ]


migrationNewStep :: StructuredSubcommandCliSpec -> PlanStep
migrationNewStep spec =
    step spec "migration_new" "file.migration_generation" SyncProbe
        [ WriteFileText (scsMigrationDirPath spec <> "/.keep") ""
        ]
        [bs "file.output", bs "file.manifest", bs "cli.file_argument", bs "exit.code"]
        [ss "fixture.directory", ss "run.cmd", ss "expect.exit", ss "artifact.file"]
        (RunSpec
            (T.unwords
                [ "app"
                , scsMigrationNewCommand spec
                , "&& test -f"
                , T.pack (scsMigrationDirPath spec) <> "/atlas.sum"
                , "&& ls"
                , T.pack (scsMigrationDirPath spec)
                , "| grep -q"
                , shellSingleQuote (scsMigrationFileNeedle spec)
                , "&& echo migration-new-ok"
                ]
            )
            Nothing
            5000
            RunSync
            []
        )
        []
        [ ExpectExit (scsSuccessExitCode spec)
        , ExpectStdoutContains "migration-new-ok"
        ]
        [ "Validates migration-style file generation and manifest creation with shell-level artifact checks until DTC gains native artifact expectations."
        ]


step
    :: StructuredSubcommandCliSpec
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
        { psId = scsName spec <> "." <> suffixText
        , psFeature = FeatureId feature
        , psBehaviorSurfaces = behaviorSurfaces
        , psSpecSurfaces = specSurfaces
        , psKind = kind
        , psSetup = setup
        , psRun = run
        , psTriggers = triggers
        , psExpect = expect
        , psSource = scsSources spec
        , psNotes = notes
        }


suffix :: Text -> Text
suffix =
    T.map replaceChar
  where
    replaceChar c
        | c == '-' || c == '_' || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z') || ('0' <= c && c <= '9') = c
        | otherwise = '_'


shellSingleQuote :: Text -> Text
shellSingleQuote value =
    "'" <> T.replace "'" "'\\''" value <> "'"


bs :: Text -> BehaviorSurface
bs = BehaviorSurface


ss :: Text -> SpecSurface
ss = SpecSurface


required :: Text -> Text -> [Text] -> [Text] -> BindingField
required name description sourceHints examples =
    BindingField name Required description sourceHints examples
