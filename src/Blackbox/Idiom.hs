{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- Structured idiom library.
--
-- Each idiom is one of three shapes:
--   1. ProbeAction  — produces a ProbeCmd to run, optionally with a stdin payload
--   2. PostProcess  — analyzes a ProbeResult and emits Facts
--   3. Rule         — pure decision rule, exposed as text to LLM/agent logic
--
-- See methodology.md §4 for the 34 canonical idioms.
module Blackbox.Idiom
    ( Idiom (..)
    , IdiomAction (..)
    , IdiomCategory (..)
    , Fact (..)
    , factText
    , allIdioms
    , idiomById
    , idiomsFor
    , runProbeAction
    , runPostProcess
    ) where

import           Data.List (find, isInfixOf, isPrefixOf)
import qualified Data.Text as T
import           Data.Text (Text)
import           GHC.Generics (Generic)

import           Blackbox.Types


-- ---------------------------------------------------------------
-- Idiom data model
-- ---------------------------------------------------------------

data IdiomCategory
    = CatGeneral        -- idioms 1-6
    | CatStatefulAsync  -- 7-12
    | CatByteVisual     -- 13-16
    | CatSilentInvert   -- 17-18
    | CatMatrix         -- 19-21
    | CatBinaryExact    -- 22-25
    | CatPipeline       -- 26-27
    | CatLargeSpace     -- 28-29
    | CatContainerFs    -- 30-32
    | CatAssetDep       -- 33-34
    deriving stock (Eq, Show, Ord, Generic)


-- An atomic fact extracted by an idiom's PostProcess.
-- Goes into the belief Markdown.
data Fact
    = FactIdentity Text                    -- "shellharden 4.3.1"
    | FactCli [Text]                       -- discovered flag names
    | FactExit Int Text                    -- exit code → semantic
    | FactErrorBucket Text                 -- error message bucket label
    | FactLibFingerprint Text              -- "nlohmann/json"
    | FactBug Text                         -- bug-as-contract entry
    | FactKnownUnknown Text                -- physically unprobeable
    | FactByteAtom Text                    -- generic "name: value" string
    | FactKAT { katInput :: Text, katFlags :: [Text], katExpectedHex :: Text }
    deriving stock (Eq, Show, Generic)


factText :: Fact -> Text
factText (FactIdentity s)        = "identity: " <> s
factText (FactCli xs)            = "cli_surface: " <> T.intercalate ", " xs
factText (FactExit n s)          = "exit " <> T.pack (show n) <> ": " <> s
factText (FactErrorBucket s)     = "error_bucket: " <> s
factText (FactLibFingerprint s)  = "library_fingerprint: " <> s
factText (FactBug s)             = "bug_to_replicate: " <> s
factText (FactKnownUnknown s)    = "known_unknown: " <> s
factText (FactByteAtom s)        = s
factText (FactKAT i fl h)        = "KAT: probe " <> T.unwords fl <> "  in=" <> T.take 40 i <> "  out=" <> T.take 60 h


-- The action an idiom performs.
data IdiomAction
    -- A concrete probe to run (template already filled with args).
    = ActProbe { actArgs :: [Text], actStdin :: Maybe Text }

    -- A family of probes to try — agent picks variants until one succeeds.
    -- Useful for "try --version OR -V OR -v OR -version".
    | ActProbeFamily { actVariants :: [([Text], Maybe Text)] }

    -- A post-processor: looks at one ProbeResult, emits facts.
    | ActPostProcess { actPP :: ProbeResult -> [Fact] }

    -- A decision rule, surfaced as text in the LLM prompt.
    | ActRule { actRuleDoc :: Text }


data Idiom = Idiom
    { iId         :: Text
    , iName       :: Text
    , iCategory   :: IdiomCategory
    , iAppliesTo  :: [BlackBoxType]   -- empty = applies to all forms
    , iAppliesStg :: [Text]            -- empty = applies to any stage
    , iSummary    :: Text              -- one-line hint shown in LLM prompt
    , iAction     :: IdiomAction
    }


-- ---------------------------------------------------------------
-- Idiom registry
-- ---------------------------------------------------------------

-- Look up by ID.
idiomById :: Text -> Maybe Idiom
idiomById tid = find (\i -> iId i == tid) allIdioms


-- Filter idioms applicable to a given form and (optionally) plan stage.
idiomsFor :: BlackBoxType -> Maybe Text -> [Idiom]
idiomsFor form mStage = filter applies allIdioms
  where
    applies i =
        (null (iAppliesTo i)  || form `elem` iAppliesTo i)
        &&
        (null (iAppliesStg i) || maybe True (\s -> any (`T.isInfixOf` s) (iAppliesStg i)) mStage)


-- Run a probe action (Probe or first ProbeFamily variant).
-- Returns the ProbeCmd to execute, or Nothing for non-probe idioms.
runProbeAction :: Idiom -> Maybe ProbeCmd
runProbeAction i = case iAction i of
    ActProbe args mStdin -> Just ProbeCmd
        { pcArgs   = args
        , pcStdin  = mStdin
        , pcReason = "idiom " <> iId i <> ": " <> iName i
        }
    ActProbeFamily variants ->
        case variants of
            (args, mStdin) : _ -> Just ProbeCmd
                { pcArgs   = args
                , pcStdin  = mStdin
                , pcReason = "idiom " <> iId i <> " (1st variant): " <> iName i
                }
            [] -> Nothing
    _ -> Nothing


-- Apply a PostProcess idiom to a probe result.
runPostProcess :: Idiom -> ProbeResult -> [Fact]
runPostProcess i pr = case iAction i of
    ActPostProcess f -> f pr
    _                -> []


-- ---------------------------------------------------------------
-- The 34 idioms
-- ---------------------------------------------------------------

allIdioms :: [Idiom]
allIdioms =
    -- §4.1 General
    [ idiom_exit_capture
    , idiom_stream_split
    , idiom_visible_bytes
    , idiom_set_x_loop
    , idiom_safe_printf
    , idiom_empty_literalize

    -- §4.2 Stateful / Async
    , idiom_async_trigger
    , idiom_timeout_124_signal
    , idiom_container_redirect
    , idiom_proc_scan_no_pgrep
    , idiom_env_matrix
    , idiom_debug_env_sniff

    -- §4.3 Byte-level
    , idiom_repeat_2x_const_check
    , idiom_ansi_csi_strip
    , idiom_ansi_csi_dcs_strip
    , idiom_row_width_quant

    -- §4.4 Silent invert
    , idiom_error_path_inversion
    , idiom_silent_exit_semantics

    -- §4.5 Matrix
    , idiom_minimal_input_cross
    , idiom_round_trip_identity
    , idiom_type_ambiguity_for

    -- §4.6 Binary byte-exact
    , idiom_binary_visualize
    , idiom_cmp_round_trip
    , idiom_determinism_2x
    , idiom_kat_record

    -- §4.7 Pipeline
    , idiom_intermediate_dump_discovery
    , idiom_list_enumeration

    -- §4.8 Large space + self-describe
    , idiom_pipeline_exit_pitfall
    , idiom_self_describe_harvest

    -- §4.9 Container / FS
    , idiom_container_data_scan
    , idiom_stdin_as_path
    , idiom_controlled_delta_synthetic

    -- §4.10 Asset-dependent
    , idiom_task_dir_asset_ls
    , idiom_literal_default_value
    ]


-- ---------------------------------------------------------------
-- §4.1 General (universal)
-- ---------------------------------------------------------------

idiom_exit_capture :: Idiom
idiom_exit_capture = Idiom
    { iId         = "exit_capture"
    , iName       = "Capture exit code"
    , iCategory   = CatGeneral
    , iAppliesTo  = []
    , iAppliesStg = []
    , iSummary    = "Every probe — record exit code. CLI tools encode 50%+ of contract in exit."
    , iAction     = ActRule "Always include exit code in ProbeResult; never discard."
    }

idiom_stream_split :: Idiom
idiom_stream_split = Idiom
    { iId         = "stream_split"
    , iName       = "Confirm stderr vs stdout routing"
    , iCategory   = CatGeneral
    , iAppliesTo  = []
    , iAppliesStg = ["stream", "error", "output"]
    , iSummary    = "When unsure which stream an output goes to, run probe with 2>/dev/null and 1>/dev/null separately."
    , iAction     = ActRule "Compare stdout-only vs stderr-only captures to confirm routing."
    }

idiom_visible_bytes :: Idiom
idiom_visible_bytes = Idiom
    { iId         = "visible_bytes"
    , iName       = "Visualize control bytes"
    , iCategory   = CatGeneral
    , iAppliesTo  = []
    , iAppliesStg = []
    , iSummary    = "Reveal invisible bytes by piping output through xxd / od -c."
    , iAction     = ActPostProcess $ \pr ->
        if T.any (\c -> let o = fromEnum c in o < 32 && c /= '\n' && c /= '\r' && c /= '\t') (prStdout pr)
            then [FactByteAtom ("control_bytes_present: yes (first " <> tshow (T.length (prStdout pr)) <> " bytes)")]
            else []
    }

idiom_set_x_loop :: Idiom
idiom_set_x_loop = Idiom
    { iId         = "set_x_loop"
    , iName       = "set -x for loop annotation"
    , iCategory   = CatGeneral
    , iAppliesTo  = []
    , iAppliesStg = ["matrix", "edge_cases"]
    , iSummary    = "When iterating inputs in a probe batch, set -x auto-prints each input to stderr."
    , iAction     = ActRule "Wrap multi-input loops in `set -x; for x in ...; do ./probe ...; done`."
    }

idiom_safe_printf :: Idiom
idiom_safe_printf = Idiom
    { iId         = "safe_printf"
    , iName       = "printf instead of echo"
    , iCategory   = CatGeneral
    , iAppliesTo  = []
    , iAppliesStg = []
    , iSummary    = "Use `printf '%s\\n'` instead of `echo` — cross-shell safe (echo varies)."
    , iAction     = ActRule "echo handling of \\n / \\t / backslashes differs across shells; printf is portable."
    }

idiom_empty_literalize :: Idiom
idiom_empty_literalize = Idiom
    { iId         = "empty_literalize"
    , iName       = "Literalize empty output"
    , iCategory   = CatGeneral
    , iAppliesTo  = []
    , iAppliesStg = ["silent_confirm"]
    , iSummary    = "When checking for empty output, use `out=$(cmd); echo \"out='$out'\"` to see ''."
    , iAction     = ActRule "Distinguish empty-string output from unset / suppressed via explicit quoting."
    }


-- ---------------------------------------------------------------
-- §4.2 Stateful / Async (F2 daemon)
-- ---------------------------------------------------------------

idiom_async_trigger :: Idiom
idiom_async_trigger = Idiom
    { iId         = "async_trigger"
    , iName       = "Background trigger + foreground probe"
    , iCategory   = CatStatefulAsync
    , iAppliesTo  = [F2_StatefulDaemon]
    , iAppliesStg = ["async", "event", "trigger"]
    , iSummary    = "( sleep 1 && <trigger> ) & ; ./probe ...; wait — for reactive daemons."
    , iAction     = ActRule "Spawn background event trigger, run probe in foreground; wait at end."
    }

idiom_timeout_124_signal :: Idiom
idiom_timeout_124_signal = Idiom
    { iId         = "timeout_124_signal"
    , iName       = "EXIT=124 is normal for daemons"
    , iCategory   = CatStatefulAsync
    , iAppliesTo  = [F2_StatefulDaemon]
    , iAppliesStg = []
    , iSummary    = "For reactive tools, EXIT=124 (timeout) means 'still listening', not failure."
    , iAction     = ActPostProcess $ \pr ->
        if prExitCode pr == 124 && not (T.null (prStdout pr))
            then [FactByteAtom "exit_124_with_output: tool responsive but timeout — normal for reactive form"]
            else []
    }

idiom_container_redirect :: Idiom
idiom_container_redirect = Idiom
    { iId         = "container_redirect"
    , iName       = "Redirect inside container, then cat"
    , iCategory   = CatStatefulAsync
    , iAppliesTo  = []
    , iAppliesStg = []
    , iSummary    = "docker exec <ctr> bash -c '{cmd} 2>/tmp/err 1>/tmp/out; cat /tmp/out; cat /tmp/err'"
    , iAction     = ActRule "When probe wrapper distorts stream routing, redirect inside the container."
    }

idiom_proc_scan_no_pgrep :: Idiom
idiom_proc_scan_no_pgrep = Idiom
    { iId         = "proc_scan_no_pgrep"
    , iName       = "/proc scan when pgrep absent"
    , iCategory   = CatStatefulAsync
    , iAppliesTo  = [F2_StatefulDaemon]
    , iAppliesStg = []
    , iSummary    = "for p in /proc/[0-9]*/comm; do echo $(basename $(dirname $p)) $(cat $p); done | grep <name>"
    , iAction     = ActRule "Busybox containers lack pgrep — read /proc/*/comm directly."
    }

idiom_env_matrix :: Idiom
idiom_env_matrix = Idiom
    { iId         = "env_matrix"
    , iName       = "Env var matrix"
    , iCategory   = CatStatefulAsync
    , iAppliesTo  = [F2_StatefulDaemon]
    , iAppliesStg = ["env"]
    , iSummary    = "for v in TERM SIGUSR1 15 usr1; do CMD_WITH_ENV=$v; done"
    , iAction     = ActRule "Loop over likely env-var value forms; observe accept vs reject."
    }

idiom_debug_env_sniff :: Idiom
idiom_debug_env_sniff = Idiom
    { iId         = "debug_env_sniff"
    , iName       = "Sniff hidden debug env vars"
    , iCategory   = CatStatefulAsync
    , iAppliesTo  = []
    , iAppliesStg = ["env"]
    , iSummary    = "Try DEBUG=1, VERBOSE=1, *_TRACE=1 — undocumented debug switches are common gold."
    , iAction     = ActRule "For each likely DEBUG-style var (DEBUG, VERBOSE, *_TRACE), run probe with it set."
    }


-- ---------------------------------------------------------------
-- §4.3 Byte / character level
-- ---------------------------------------------------------------

idiom_repeat_2x_const_check :: Idiom
idiom_repeat_2x_const_check = Idiom
    { iId         = "repeat_2x_const_check"
    , iName       = "Repeat probe to detect compile-time literal"
    , iCategory   = CatByteVisual
    , iAppliesTo  = []
    , iAppliesStg = ["identity"]
    , iSummary    = "Run same probe twice; identical output → compile-time literal (reimpl must reproduce verbatim)."
    , iAction     = ActRule "Compare two runs of the same probe; differences = runtime-dependent fields."
    }

idiom_ansi_csi_strip :: Idiom
idiom_ansi_csi_strip = Idiom
    { iId         = "ansi_csi_strip"
    , iName       = "Strip ANSI CSI (colors)"
    , iCategory   = CatByteVisual
    , iAppliesTo  = [F4_TuiStdoutEmitting]
    , iAppliesStg = ["render", "color"]
    , iSummary    = "sed 's/\\\\x1b\\\\[[0-9;]*m//g' — single layer, drop SGR colors."
    , iAction     = ActPostProcess $ \pr ->
        let stripped = stripCsi (prStdout pr)
        in if T.length stripped < T.length (prStdout pr)
              then [FactByteAtom ("ansi_csi_codes_present: yes; stripped_length=" <> tshow (T.length stripped))]
              else []
    }

idiom_ansi_csi_dcs_strip :: Idiom
idiom_ansi_csi_dcs_strip = Idiom
    { iId         = "ansi_csi_dcs_strip"
    , iName       = "Strip ANSI CSI + DCS"
    , iCategory   = CatByteVisual
    , iAppliesTo  = [F4_TuiStdoutEmitting]
    , iAppliesStg = ["control_seq", "render"]
    , iSummary    = "sed -E 's/\\\\x1b\\\\[[0-9;?]*[a-zA-Z]//g; s/\\\\x1bP[^\\\\x1b]*\\\\x1b\\\\\\\\//g' — double layer (FTXUI startup sends DCS)."
    , iAction     = ActRule "TUI startup sequences include DCS (Device Control String) beyond CSI. Strip both."
    }

idiom_row_width_quant :: Idiom
idiom_row_width_quant = Idiom
    { iId         = "row_width_quant"
    , iName       = "Quantify row widths"
    , iCategory   = CatByteVisual
    , iAppliesTo  = [F4_TuiStdoutEmitting, F12_AssetDependent]
    , iAppliesStg = ["render", "layout"]
    , iSummary    = "awk '{ printf \"[%d] >%s<\\\\n\", length($0), $0 }' — confirm right-padding to uniform width."
    , iAction     = ActPostProcess $ \pr ->
        let ls       = T.lines (prStdout pr)
            widths   = map T.length ls
            same     = case widths of
                         (w:rest) -> all (== w) rest
                         _        -> False
        in if length ls >= 2 && same
              then [FactByteAtom "row_widths: uniform (right-padded layout)"]
              else []
    }


-- ---------------------------------------------------------------
-- §4.4 Silent invert (F6)
-- ---------------------------------------------------------------

idiom_error_path_inversion :: Idiom
idiom_error_path_inversion = Idiom
    { iId         = "error_path_inversion"
    , iName       = "Inverted probing via error paths"
    , iCategory   = CatSilentInvert
    , iAppliesTo  = [F6_SilentLinter]
    , iAppliesStg = ["invert", "error"]
    , iSummary    = "Force errors to learn CLI surface: unknown flag → usage; missing arg → type; bad enum → legal values."
    , iAction     = ActProbeFamily
        [ (["-nosuch"],                Nothing)   -- unknown flag
        , (["--bogus"],                Nothing)
        , (["-XYZ"],                   Nothing)
        ]
    }

idiom_silent_exit_semantics :: Idiom
idiom_silent_exit_semantics = Idiom
    { iId         = "silent_exit_semantics"
    , iName       = "Silent exit code semantics"
    , iCategory   = CatSilentInvert
    , iAppliesTo  = [F6_SilentLinter]
    , iAppliesStg = ["exit_code_semantics"]
    , iSummary    = "For silent tools, EXIT alone is the signal: 0=silent_accept, 1=found_issue, 2=usage_err, 124=walking/timeout."
    , iAction     = ActPostProcess $ \pr ->
        case prExitCode pr of
            0 | isSilent pr   -> [FactExit 0 "silent acceptance (clean)"]
            1                  -> [FactExit 1 "issue found"]
            2                  -> [FactExit 2 "usage / parse error"]
            124                -> [FactExit 124 "timeout — may be walking large input"]
            _                  -> []
    }


-- ---------------------------------------------------------------
-- §4.5 Matrix (F1, F7)
-- ---------------------------------------------------------------

idiom_minimal_input_cross :: Idiom
idiom_minimal_input_cross = Idiom
    { iId         = "minimal_input_cross"
    , iName       = "Minimal input × all output cells"
    , iCategory   = CatMatrix
    , iAppliesTo  = [F7_FormatConverter]
    , iAppliesStg = ["matrix", "minimal_input"]
    , iSummary    = "Fire a single minimal input ({\"a\":1}) through every (in, out) format pair; xxd byte-diff."
    , iAction     = ActRule "For each output format, run with the same canonical input and inspect byte-level."
    }

idiom_round_trip_identity :: Idiom
idiom_round_trip_identity = Idiom
    { iId         = "round_trip_identity"
    , iName       = "Round-trip identity"
    , iCategory   = CatMatrix
    , iAppliesTo  = [F7_FormatConverter, F8_BinaryByteExact]
    , iAppliesStg = ["round_trip", "identity"]
    , iSummary    = "Convert X → X; non-identity reveals normalization drift (1.0 → 1, folded → literal)."
    , iAction     = ActRule "Identity transform that's NOT identity = reimpl must reproduce drift."
    }

idiom_type_ambiguity_for :: Idiom
idiom_type_ambiguity_for = Idiom
    { iId         = "type_ambiguity_for"
    , iName       = "Type ambiguity for-loop"
    , iCategory   = CatMatrix
    , iAppliesTo  = [F7_FormatConverter]
    , iAppliesStg = ["type", "ambiguity"]
    , iSummary    = "for v in yes Yes YES no true True ...; do probe with input ; done — bool/null/number mapping."
    , iAction     = ActRule "Enumerate literal-value variants to map type-coercion behavior."
    }


-- ---------------------------------------------------------------
-- §4.6 Binary byte-exact (F8)
-- ---------------------------------------------------------------

idiom_binary_visualize :: Idiom
idiom_binary_visualize = Idiom
    { iId         = "binary_visualize"
    , iName       = "Force binary byte visualization"
    , iCategory   = CatBinaryExact
    , iAppliesTo  = [F8_BinaryByteExact]
    , iAppliesStg = []
    , iSummary    = "host: xxd; container: od -An -t x1 (busybox has no xxd)."
    , iAction     = ActPostProcess $ \pr ->
        if isBinary (prStdout pr)
            then [FactByteAtom ("binary_output_hex_head: " <> T.take 80 (toHex (prStdout pr)))]
            else []
    }

idiom_cmp_round_trip :: Idiom
idiom_cmp_round_trip = Idiom
    { iId         = "cmp_round_trip"
    , iName       = "cmp byte-exact round trip"
    , iCategory   = CatBinaryExact
    , iAppliesTo  = [F8_BinaryByteExact]
    , iAppliesStg = ["round_trip"]
    , iSummary    = "compress → decompress; cmp orig vs decoded (NOT diff — diff misreads binary)."
    , iAction     = ActRule "For lossless tools, byte-exact round-trip via cmp is mandatory."
    }

idiom_determinism_2x :: Idiom
idiom_determinism_2x = Idiom
    { iId         = "determinism_2x"
    , iName       = "Two-run determinism check"
    , iCategory   = CatBinaryExact
    , iAppliesTo  = [F8_BinaryByteExact]
    , iAppliesStg = ["determinism"]
    , iSummary    = "Run probe twice with same input; cmp -s A B → deterministic? If not, identify which bytes change."
    , iAction     = ActRule "Determinism = grader can byte-diff; non-deterministic bytes need wildcarding."
    }

idiom_kat_record :: Idiom
idiom_kat_record = Idiom
    { iId         = "kat_record"
    , iName       = "Known-Answer Test record"
    , iCategory   = CatBinaryExact
    , iAppliesTo  = [F8_BinaryByteExact]
    , iAppliesStg = ["kat", "summarize"]
    , iSummary    = "Pin one (input, flags) → expected bytes hex. Use as reimpl unit test."
    , iAction     = ActPostProcess $ \pr ->
        if isBinary (prStdout pr) && prExitCode pr == 0
            then [FactKAT
                    { katInput        = maybe "(no stdin)" (T.take 60) (pcStdin (prCmd pr))
                    , katFlags        = pcArgs (prCmd pr)
                    , katExpectedHex  = T.take 120 (toHex (prStdout pr))
                    }]
            else []
    }


-- ---------------------------------------------------------------
-- §4.7 Pipeline (F9)
-- ---------------------------------------------------------------

idiom_intermediate_dump_discovery :: Idiom
idiom_intermediate_dump_discovery = Idiom
    { iId         = "intermediate_dump_discovery"
    , iName       = "Find intermediate-stage dump interface"
    , iCategory   = CatPipeline
    , iAppliesTo  = [F9_MultiStagePipeline]
    , iAppliesStg = ["intermediate"]
    , iSummary    = "Try -f tokens / --ast / --dump-ir / --print-stage=N / --trace. If found, decompose pipeline."
    , iAction     = ActProbeFamily
        [ (["-f", "tokens"],     Nothing)
        , (["--ast"],            Nothing)
        , (["--dump-ast"],       Nothing)
        , (["--dump-ir"],        Nothing)
        , (["--emit", "ast"],    Nothing)
        , (["--trace"],          Nothing)
        ]
    }

idiom_list_enumeration :: Idiom
idiom_list_enumeration = Idiom
    { iId         = "list_enumeration"
    , iName       = "Enumerate configurable units"
    , iCategory   = CatPipeline
    , iAppliesTo  = [F9_MultiStagePipeline, F10_LargeFlagSpace]
    , iAppliesStg = ["inventory", "list_enum"]
    , iSummary    = "--list / --list-lexers / --type-list / --list-themes — capture full configuration space."
    , iAction     = ActProbeFamily
        [ (["--list"],         Nothing)
        , (["--list-all"],     Nothing)
        , (["--type-list"],    Nothing)
        , (["--list-lexers"],  Nothing)
        , (["--list-styles"],  Nothing)
        ]
    }


-- ---------------------------------------------------------------
-- §4.8 Large space + self-describe
-- ---------------------------------------------------------------

idiom_pipeline_exit_pitfall :: Idiom
idiom_pipeline_exit_pitfall = Idiom
    { iId         = "pipeline_exit_pitfall"
    , iName       = "Pipeline EXIT pitfall"
    , iCategory   = CatLargeSpace
    , iAppliesTo  = []
    , iAppliesStg = ["exit_code"]
    , iSummary    = "`cmd | head; echo $?` returns head's exit. Use $PIPESTATUS[0] / pipefail / separate runs."
    , iAction     = ActRule "When EXIT looks wrong, isolate from pipeline; trust standalone run only."
    }

idiom_self_describe_harvest :: Idiom
idiom_self_describe_harvest = Idiom
    { iId         = "self_describe_harvest"
    , iName       = "Harvest self-describe outputs"
    , iCategory   = CatLargeSpace
    , iAppliesTo  = [F10_LargeFlagSpace, F12_AssetDependent]
    , iAppliesStg = ["self_describe", "inventory"]
    , iSummary    = "--generate=man / --generate complete-bash / --show-defaults / -I N — tool's own inventory."
    , iAction     = ActProbeFamily
        [ (["--generate=man"],            Nothing)
        , (["--generate", "complete-bash"], Nothing)
        , (["--show-defaults"],           Nothing)
        , (["--print-defaults"],          Nothing)
        ]
    }


-- ---------------------------------------------------------------
-- §4.9 Container / filesystem (F11)
-- ---------------------------------------------------------------

idiom_container_data_scan :: Idiom
idiom_container_data_scan = Idiom
    { iId         = "container_data_scan"
    , iName       = "Scan container for existing test data"
    , iCategory   = CatContainerFs
    , iAppliesTo  = [F11_StructuredLinter, F6_SilentLinter]
    , iAppliesStg = ["find_test_inputs"]
    , iSummary    = "Try /usr/local/<lang>/src, /usr/share/doc, /etc — container often bundles test corpora."
    , iAction     = ActProbeFamily
        [ (["/usr/local/go/src"],            Nothing)
        , (["/usr/share/doc"],               Nothing)
        , (["/etc"],                         Nothing)
        ]
    }

idiom_stdin_as_path :: Idiom
idiom_stdin_as_path = Idiom
    { iId         = "stdin_as_path"
    , iName       = "/dev/stdin as path"
    , iCategory   = CatContainerFs
    , iAppliesTo  = [F11_StructuredLinter]
    , iAppliesStg = []
    , iSummary    = "Pipe synthetic content into ./probe /dev/stdin — backdoor for tools that only accept path args."
    , iAction     = ActRule "When tool accepts paths but not stdin, /dev/stdin is the universal injection point."
    }

idiom_controlled_delta_synthetic :: Idiom
idiom_controlled_delta_synthetic = Idiom
    { iId         = "controlled_delta_synthetic"
    , iName       = "Controlled-delta synthetic matrix"
    , iCategory   = CatContainerFs
    , iAppliesTo  = [F11_StructuredLinter]
    , iAppliesStg = ["synthetic_delta"]
    , iSummary    = "Pair (base, delta) inputs differing in 1 axis (rename / literal / op / type / structure) — reveal algorithm normalization."
    , iAction     = ActRule "For static analyzers, craft minimal pairs to map what the algorithm normalizes."
    }


-- ---------------------------------------------------------------
-- §4.10 Asset dependence (F12)
-- ---------------------------------------------------------------

idiom_task_dir_asset_ls :: Idiom
idiom_task_dir_asset_ls = Idiom
    { iId         = "task_dir_asset_ls"
    , iName       = "List task-dir assets first"
    , iCategory   = CatAssetDep
    , iAppliesTo  = [F12_AssetDependent]
    , iAppliesStg = ["list_task_dir_assets"]
    , iSummary    = "Before any probe, ls assets/ fonts/ data/ templates/ — see what the tool needs."
    , iAction     = ActRule "Asset-dependent tools' default fontdir often doesn't exist in cleanroom; must pass -d."
    }

idiom_literal_default_value :: Idiom
idiom_literal_default_value = Idiom
    { iId         = "literal_default_value"
    , iName       = "Literal default value"
    , iCategory   = CatAssetDep
    , iAppliesTo  = [F12_AssetDependent]
    , iAppliesStg = ["infocode", "default_value"]
    , iSummary    = "Tool-reported default paths (-I 2 / --print-defaults) are STRINGS — reimpl mirrors verbatim, not validates."
    , iAction     = ActPostProcess $ \pr ->
        let s = T.strip (prStdout pr)
            looksLikePath = T.isPrefixOf "/" s && not (T.isInfixOf "\n" s) && T.length s < 200
        in if looksLikePath
              then [FactByteAtom ("literal_default_value: " <> s <> " (reimpl must return this string verbatim, regardless of validity)")]
              else []
    }


-- ---------------------------------------------------------------
-- Utility
-- ---------------------------------------------------------------

stripCsi :: Text -> Text
stripCsi = T.pack . go . T.unpack
  where
    go []           = []
    go ('\x1b':'[':rest) = go (drop 1 (dropWhile (\c -> c < '@' || c > '~') rest))
    go (c:rest)     = c : go rest


toHex :: Text -> Text
toHex t = T.pack $ concatMap byteHex (T.unpack t)
  where
    byteHex c =
        let n = fromEnum c
            h1 = nibble (n `div` 16)
            h2 = nibble (n `mod` 16)
        in [h1, h2, ' ']
    nibble n
        | n < 10    = toEnum (fromEnum '0' + n)
        | otherwise = toEnum (fromEnum 'a' + n - 10)


tshow :: Show a => a -> Text
tshow = T.pack . show
