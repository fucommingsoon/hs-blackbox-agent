{-# LANGUAGE OverloadedStrings #-}

module Blackbox.DTC.Archetype.WatcherCli
    ( WatcherCliSpec (..)
    , watcherCliRequirements
    , watcherCliSteps
    ) where

import qualified Data.Text          as T
import           Data.Text          (Text)

import           Blackbox.DTC.Types


data WatcherCliSpec = WatcherCliSpec
    { wcsName                   :: Text
    , wcsSources                :: [CorpusInput]
    , wcsNonInteractiveFlag     :: Text
    , wcsOneshotFlag            :: Text
    , wcsPostponeFlag           :: Text
    , wcsDirectoryWatchFlag     :: Text
    , wcsChangedPathToken       :: Text
    , wcsUsageNeedle            :: Text
    , wcsNoRegularFilesNeedle   :: Text
    , wcsUnableToStatNeedle     :: Text
    , wcsDirectoryAlteredNeedle :: Text
    } deriving (Eq, Show)


watcherCliRequirements :: ArchetypeRequirement
watcherCliRequirements = ArchetypeRequirement
    { arArchetype = WatcherCli
    , arPurpose = "Validate a CLI that reads watched paths from stdin, runs a child command on file changes, and reports watcher-specific error paths."
    , arFields =
        [ required "name"
            "Stable project or binary name used to prefix generated step ids."
            ["project catalog", "binary name", "task metadata"]
            ["entr"]
        , required "nonInteractiveFlag"
            "Flag that disables interactive keyboard handling or screen control so the app is probe-friendly."
            ["--help output", "manpage", "upstream tests", "source option parser"]
            ["-n"]
        , required "oneshotFlag"
            "Flag that runs the child command once and exits after the watched input is ready or changed."
            ["--help output", "manpage", "upstream tests", "source option parser"]
            ["-z"]
        , required "postponeFlag"
            "Flag that postpones the first child execution until a watch event occurs."
            ["--help output", "manpage", "upstream tests", "source option parser"]
            ["-p"]
        , required "changedPathToken"
            "Token substituted by the watcher with the first changed path when building the child command."
            ["manpage", "README", "source substitution logic", "regression tests"]
            ["/_"]
        , required "usageNeedle"
            "Stable stderr/stdout text proving the app rejected a missing utility or invalid invocation with usage."
            ["--help output", "no-arg probe", "grader expected output"]
            ["usage:"]
        , required "noRegularFilesNeedle"
            "Stable diagnostic emitted when stdin contains no usable regular files."
            ["source errors", "upstream tests", "grader expected output"]
            ["No regular files"]
        , required "unableToStatNeedle"
            "Stable diagnostic emitted for a missing path from the watch list."
            ["source errors", "upstream tests", "grader expected output"]
            ["unable to stat"]
        , optional "directoryWatchFlag"
            "Flag that enables directory alteration reporting, if the watcher supports it."
            ["--help output", "manpage", "source option parser", "directory tests"]
            ["-d"]
        , optional "directoryAlteredNeedle"
            "Stable diagnostic emitted when a watched directory is altered."
            ["source errors", "upstream tests", "grader expected output"]
            ["directory altered"]
        ]
    }


watcherCliSteps :: WatcherCliSpec -> [PlanStep]
watcherCliSteps spec =
    [ noArguments spec
    , noRegularFiles spec
    , emptyInput spec
    , stdoutChildPassthrough spec
    , childExitCode spec
    , fileChangeTrigger spec
    , oneshotAfterFileChange spec
    , firstChangedFileSubstitution spec
    , directoryAltered spec
    ]


noArguments :: WatcherCliSpec -> PlanStep
noArguments spec =
    step spec "no_arguments" "cli.usage_without_arguments" SyncProbe []
        [bs "cli.args", bs "stderr.usage", bs "exit.code"]
        [ss "plan.id", ss "run.cmd", ss "expect.exit", ss "expect.stderr"]
        (RunSpec "app" Nothing 3000 RunSync [])
        []
        [ ExpectExit 1
        , ExpectStderrContains (wcsUsageNeedle spec)
        ]
        [ "CLI shape guard: a watcher CLI should reject missing utility/watch input with usage."
        ]


noRegularFiles :: WatcherCliSpec -> PlanStep
noRegularFiles spec =
    step spec "no_regular_files" "exit.no_regular_files" SyncProbe []
        [bs "stdin.watch_list", bs "watch_list.missing_file", bs "stderr.error", bs "exit.code"]
        [ss "run.cmd", ss "run.stdin", ss "expect.exit", ss "expect.stderr"]
        (RunSpec
            (cmd spec [wcsOneshotFlag spec, "echo ok"])
            (Just "${WORK}/missing\n")
            3000
            RunSync
            []
        )
        []
        [ ExpectExit 1
        , ExpectStderrContains (wcsUnableToStatNeedle spec)
        , ExpectStderrContains (wcsNoRegularFilesNeedle spec)
        ]
        [ "Error-path flow. It proves input validation, not stdout passthrough."
        ]


emptyInput :: WatcherCliSpec -> PlanStep
emptyInput spec =
    step spec "empty_input" "input.empty_watch_list" SyncProbe []
        [bs "stdin.watch_list", bs "watch_list.empty", bs "stderr.error", bs "exit.code"]
        [ss "run.cmd", ss "run.stdin", ss "expect.exit", ss "expect.stderr"]
        (RunSpec
            (cmd spec [wcsNonInteractiveFlag spec, "echo vroom"])
            (Just "\n")
            3000
            RunSync
            []
        )
        []
        [ ExpectExit 1
        , ExpectStderrContains (wcsNoRegularFilesNeedle spec)
        ]
        [ "Rejects an empty watch list before running the child utility."
        ]


stdoutChildPassthrough :: WatcherCliSpec -> PlanStep
stdoutChildPassthrough spec =
    step spec "stdout_child_passthrough" "io.stdout_child_passthrough" SyncProbe
        [TouchFile "${WORK}/file"]
        [bs "fixture.file.touch", bs "stdin.watch_list", bs "child.stdout", bs "exit.code"]
        [ss "fixture.shape", ss "run.cmd", ss "run.stdin", ss "expect.exit", ss "expect.stdout"]
        (RunSpec
            (cmd spec [wcsNonInteractiveFlag spec, wcsOneshotFlag spec, "echo ok"])
            (Just "${WORK}/file\n")
            3000
            RunSync
            []
        )
        []
        [ ExpectExit 0
        , ExpectStdoutContains "ok"
        ]
        [ "Creates the watched file before probing; this avoids treating setup failure as program behavior."
        ]


childExitCode :: WatcherCliSpec -> PlanStep
childExitCode spec =
    step spec "child_exit_code" "process.child_exit_code" SyncProbe
        [ TouchFile "${WORK}/file1"
        , TouchFile "${WORK}/file2"
        ]
        [bs "fixture.file.touch", bs "stdin.watch_list", bs "child.exit_code", bs "stdout.empty", bs "stderr.empty"]
        [ss "fixture.shape", ss "run.cmd", ss "run.stdin", ss "expect.exit", ss "expect.stdout", ss "expect.stderr"]
        (RunSpec
            (cmd spec [wcsNonInteractiveFlag spec, wcsOneshotFlag spec, "sh -c 'exit 4'"])
            (Just "${WORK}/file1\n${WORK}/file2\n")
            3000
            RunSync
            []
        )
        []
        [ ExpectExit 4
        , ExpectStdoutEmpty
        , ExpectStderrEmpty
        ]
        [ "One-shot mode should propagate the child process exit code."
        ]


fileChangeTrigger :: WatcherCliSpec -> PlanStep
fileChangeTrigger spec =
    step spec "file_change_trigger" "watcher.reacts_to_file_change" AsyncProbe
        [TouchFile "${WORK}/watch"]
        [bs "fixture.file.touch", bs "stdin.watch_list", bs "trigger.file.append", bs "child.stdout", bs "evidence.stop"]
        [ss "fixture.shape", ss "run.cmd", ss "run.stdin", ss "trigger.shape", ss "expect.stdout", ss "runtime.evidence_stop"]
        (RunSpec
            (cmd spec [wcsNonInteractiveFlag spec, wcsPostponeFlag spec, "echo changed"])
            (Just "${WORK}/watch\n")
            1200
            RunAsync
            [StopWhenStdoutContains "changed"]
        )
        [TriggerAppend "${WORK}/watch" "x\n" 300]
        [ExpectStdoutContains "changed"]
        [ "Continuous watcher flow: evidence is stdout after mutation; runtime stops once the evidence appears."
        ]


oneshotAfterFileChange :: WatcherCliSpec -> PlanStep
oneshotAfterFileChange spec =
    step spec "oneshot_after_file_change" "watcher.oneshot_after_file_change" AsyncProbe
        [WriteFileText "${WORK}/file2" ""]
        [bs "fixture.file.write", bs "stdin.watch_list", bs "trigger.file.append", bs "oneshot.exit", bs "child.stdout"]
        [ss "fixture.shape", ss "run.cmd", ss "run.stdin", ss "trigger.shape", ss "expect.exit", ss "expect.stdout", ss "expect.stderr", ss "expect.duration"]
        (RunSpec
            (cmd spec [wcsNonInteractiveFlag spec, wcsOneshotFlag spec, wcsPostponeFlag spec, "cat ${WORK}/file2"])
            (Just "${WORK}/file2\n")
            4000
            RunAsync
            []
        )
        [TriggerAppend "${WORK}/file2" "456\n" 300]
        [ ExpectExit 0
        , ExpectStdoutContains "456"
        , ExpectStderrEmpty
        , ExpectCompletesWithinMs 4000
        ]
        [ "General one-shot watcher flow: wait for file mutation, run utility, exit cleanly."
        ]


firstChangedFileSubstitution :: WatcherCliSpec -> PlanStep
firstChangedFileSubstitution spec =
    step spec "first_changed_file_substitution" "watcher.first_changed_file_substitution" AsyncProbe
        [ TouchFile "${WORK}/file1"
        , WriteFileText "${WORK}/file2" ""
        ]
        [bs "fixture.file.touch", bs "fixture.file.write", bs "stdin.watch_list", bs "trigger.file.append", bs "substitution.changed_path", bs "child.stdout", bs "evidence.stop"]
        [ss "fixture.shape", ss "run.cmd", ss "run.stdin", ss "trigger.shape", ss "expect.stdout", ss "runtime.evidence_stop"]
        (RunSpec
            (cmd spec [wcsNonInteractiveFlag spec, wcsPostponeFlag spec, "cat " <> wcsChangedPathToken spec])
            (Just "${WORK}/file1\n${WORK}/file2\n")
            1200
            RunAsync
            [StopWhenStdoutContains "substitution-ok"]
        )
        [TriggerAppend "${WORK}/file2" "substitution-ok\n" 300]
        [ExpectStdoutContains "substitution-ok"]
        [ "Changed-path token should resolve to the first changed path. This is a continuous watcher evidence flow."
        ]


directoryAltered :: WatcherCliSpec -> PlanStep
directoryAltered spec =
    step spec "directory_altered" "watcher.directory_altered" AsyncProbe
        [ TouchFile "${WORK}/file1"
        , TouchFile "${WORK}/file2"
        ]
        [bs "fixture.file.touch", bs "stdin.watch_list", bs "trigger.file.create", bs "directory.altered", bs "child.stdout", bs "stderr.error"]
        [ss "fixture.shape", ss "run.cmd", ss "run.stdin", ss "trigger.shape", ss "expect.stdout", ss "expect.stderr", ss "expect.duration"]
        (RunSpec
            (cmd spec [wcsNonInteractiveFlag spec, wcsDirectoryWatchFlag spec, wcsPostponeFlag spec, "sh -c 'echo ping'"])
            (Just "${WORK}/file1\n${WORK}/file2\n")
            4000
            RunAsync
            []
        )
        [TriggerTouch "${WORK}/newfile" 300]
        [ ExpectStdoutContains "ping"
        , ExpectStderrContains (wcsDirectoryAlteredNeedle spec)
        , ExpectCompletesWithinMs 4000
        ]
        [ "Directory-watch flow: adding a file should report directory alteration and run the utility."
        ]


step
    :: WatcherCliSpec
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
step spec suffix feature kind setup behavior specSurfaces run triggers expect notes =
    PlanStep
        { psId = wcsName spec <> "." <> suffix
        , psFeature = FeatureId feature
        , psBehaviorSurfaces = behavior
        , psSpecSurfaces = specSurfaces
        , psKind = kind
        , psSetup = setup
        , psRun = run
        , psTriggers = triggers
        , psExpect = expect
        , psSource = wcsSources spec
        , psNotes = notes
        }


cmd :: WatcherCliSpec -> [Text] -> Text
cmd _ parts =
    T.unwords ("app" : filter (not . T.null) parts)


bs :: Text -> BehaviorSurface
bs = BehaviorSurface


ss :: Text -> SpecSurface
ss = SpecSurface


required :: Text -> Text -> [Text] -> [Text] -> BindingField
required name description hints examples =
    BindingField name Required description hints examples


optional :: Text -> Text -> [Text] -> [Text] -> BindingField
optional name description hints examples =
    BindingField name Optional description hints examples
