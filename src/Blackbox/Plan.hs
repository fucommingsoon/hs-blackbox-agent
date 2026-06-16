{-# LANGUAGE OverloadedStrings #-}

-- Plan templates per black-box form (methodology §3).
-- Each form maps to a list of high-level stages; the LLM converts each
-- stage to one or more concrete ProbeCmd invocations.
module Blackbox.Plan
    ( planFor
    ) where

import qualified Data.Text as T
import           Data.Text (Text)

import           Blackbox.Types


-- Look up the plan template for a detected form.
planFor :: BlackBoxType -> [PlanStage]
planFor bt = zipWith mk [0..] (rawStages bt)
  where
    mk i (n, p) = PlanStage
        { psId        = i
        , psNameRaw   = n
        , psPromptRaw = p
        , psDone      = False
        }


-- Raw stage list per form. Tuple = (stage-name, LLM hint).
rawStages :: BlackBoxType -> [(Text, Text)]
rawStages F1_PureFunction =
    [ ("identity",        "Run --version / -h / -V to capture identity string and CLI surface.")
    , ("default_behavior", "Run with no args; empty stdin; minimal sane input. Note EXIT codes.")
    , ("matching_modes",  "If applicable: case / word / line / fixed / invert flag matrix.")
    , ("input_shape_matrix", "stdin vs arg vs file input — try all three with the same content.")
    , ("output_format",   "line numbers / heading / filename / color flags. Use cat -v or sed for ANSI.")
    , ("exit_codes",      "Match / no-match / error — what EXIT do they each give?")
    , ("edge_cases",      "Empty input / unicode / CRLF / binary input.")
    , ("summarize",       "Write belief.md with all the above.")
    ]

rawStages F2_StatefulDaemon =
    [ ("identity",            "-h, -v.")
    , ("io_model",            "stdin format? arg format? env vars (DEBUG, *_TRACE)?")
    , ("tty_dependency",      "Run without -n / -q flag — does it require a TTY?")
    , ("async_event_idiom",   "( sleep 1 && trigger ) & ; ./probe ...; wait. EXIT 124 = listening normally.")
    , ("per_flag_with_state", "-r restart, -d dir, etc — each may spawn child or change state.")
    , ("spawn_child_inspect", "Does it fork awk/sh? Look in /proc.")
    , ("env_vars",            "DOC'd env vars + sniff DEBUG/VERBOSE/*_TRACE.")
    , ("signal_handling",     "SIGINT / SIGTERM behavior.")
    , ("edge_cases",          "File deleted / unstat / signal during run.")
    , ("summarize",           "Belief + explicit known-unknown list.")
    ]

rawStages F3_TuiNcursesLocked =
    [ ("identity",       "-V, -v, -h, --version etc.")
    , ("cli_only_probe", "Flag parsing / exit codes / error formats. TUI itself unprobeable.")
    , ("doc_vs_help_diff", "Compare README option descriptions vs actual -h output. Probe wins.")
    , ("error_path_inversion", "Try -foo / missing arg / bad enum to extract usage banner.")
    , ("bug_repro_3x",   "Re-run any segfault / abnormal exit 3 times to confirm stability.")
    , ("summarize",      "List unprobeable surface explicitly (rendering, keyboard, etc).")
    ]

rawStages F4_TuiStdoutEmitting =
    [ ("identity", "-V, -h.")
    , ("tui_type_detection", "od -c first probe output — confirm \\x1b control bytes present.")
    , ("ansi_strip_setup", "sed -E 's/\\x1b\\[[0-9;?]*[a-zA-Z]//g; s/\\x1bP[^\\x1b]*\\x1b\\\\//g'")
    , ("render_matrix", "Vary input (single value / array / nested / edge) × output.")
    , ("color_per_type", "Same value, vary style/lexer — extract type → color mapping.")
    , ("default_state", "Collapse depth / sort order / wrap rules.")
    , ("control_seq_trace", "Capture startup/teardown SGR sequences with od -c.")
    , ("library_fingerprint", "FTXUI / ratatui / blessed — from sequence patterns + error strings.")
    , ("summarize", "")
    ]

rawStages F5_HttpClient =
    [ ("identity", "")
    , ("find_test_target", "which python3 nc curl socat — inside container.")
    , ("build_echo_server", "python3 http.server with JSON-reflect handler in /tmp/echo.py.")
    , ("request_construction", "method / URL / headers / body — read reflect server output.")
    , ("output_modes", "Is -print / -p TTY-gated? Use docker exec -t to test.")
    , ("input_syntax", "ITEM parsing: key=value / key:header / key==query / key@file.")
    , ("error_format", "Log style, file:line markers, exit codes.")
    , ("cleanup", "pkill -f /tmp/echo before summary.")
    , ("summarize", "")
    ]

rawStages F6_SilentLinter =
    [ ("identity", "May fail; that's fine.")
    , ("silent_confirm", "Try 2-3 plausible inputs; if all silent + EXIT 0, confirmed silent.")
    , ("invert_probe", "Now invert: unknown flag → usage; missing arg → field type; bad enum → legal values.")
    , ("exit_code_semantics", "Distinguish 0 / 1 / 2 / 124 semantics.")
    , ("error_bucket_classification", "Group all error strings into 3-5 buckets by prefix/banner/EXIT.")
    , ("summarize_with_workaround", "Include 'next step would be to drop X into container'.")
    ]

rawStages F7_FormatConverter =
    [ ("identity", "")
    , ("matrix_axis_discovery", "From -h, list all input formats and output formats.")
    , ("minimal_input_n_by_n", "Fire {\"a\":1} or equivalent through every legal cell; xxd byte-diff.")
    , ("per_format_edge_cases", "Type ambiguity (yes/no), special floats, escape chars.")
    , ("modifier_flag_compat", "-e / -i / -k each × each output format — compatibility matrix.")
    , ("round_trip_identity", "X→X for each format; expect non-identity (drift); record drift rules.")
    , ("type_ambiguity_matrix", "for v in {true,True,yes,Yes,...}; do probe with input; done")
    , ("quoting_heuristics", "Vary string value chars (control / special / leading-dash) for output quoting rules.")
    , ("error_paths_per_format", "Each input format × malformed input.")
    , ("library_fingerprint", "yaml.v2 / BurntSushi-toml / nlohmann etc.")
    , ("summarize", "")
    ]

rawStages F8_BinaryByteExact =
    [ ("identity", "")
    , ("binary_detection", "od -c / xxd first output to confirm binary.")
    , ("round_trip_equivalence", "compress → decompress; cmp orig vs decoded.")
    , ("determinism_check", "Run twice; cmp two outputs.")
    , ("matrix_byte_diff", "Level / config flag × xxd output diff.")
    , ("fixed_offset_field_id", "Same input via file vs stdin vs stdout → byte diff at fixed offset = protocol field.")
    , ("format_variant_compat", "--format=X for each declared format; test real acceptance.")
    , ("kat_generation", "Record ≥ 1 (input, flags, expected_bytes hex) tuple.")
    , ("error_path_format", "Each error category verbatim string.")
    , ("container_workdir_pipeline", "Use docker exec sh -c '...' for multi-step pipelines.")
    , ("summarize_to_markdown", "Big spec to /tmp/<task>_requirements.md.")
    ]

rawStages F9_MultiStagePipeline =
    [ ("identity", "")
    , ("inventory_via_list", "--list, --list-X — capture full configurable space.")
    , ("intermediate_dump_discovery", "Try -f tokens / --ast / --dump-ir / --print-stage=N / --trace.")
    , ("stage1_isolation", "Fix other stages; vary stage 1 input.")
    , ("stage2_isolation", "Same for stage 2 — only if stage1 dump exists.")
    , ("stage3_isolation", "Output formatters; byte-diff their wire.")
    , ("domain_catalogue", "Per domain (lang/format/codec) at least one sample.")
    , ("variant_byte_diff", "Same family of formatters — diff byte output.")
    , ("stage_interaction", "Flags that affect multiple stages (e.g., --prefix).")
    , ("error_paths", "Per stage, feed bad input.")
    , ("library_fingerprint", "")
    , ("summarize_to_markdown", "")
    ]

rawStages F10_LargeFlagSpace =
    [ ("doc_skim", "Read README + GUIDE + FAQ + full --help BEFORE planning further.")
    , ("sandbox_basics", "exit codes / no-args / unknown flag / regex error.")
    , ("feature_group_matching", "All matching flags in ONE batch.")
    , ("feature_group_output", "All output formatting flags in one batch.")
    , ("feature_group_filtering", "All filter/walk flags in one batch.")
    , ("feature_group_output_modes", "All output mode flags (json/vimgrep/count) in one batch.")
    , ("feature_group_context", "Context flags (-A/-B/-C and separator).")
    , ("feature_group_edge", "Replace / multiline / binary / encoding edge cases.")
    , ("feature_group_errors", "Error path / quiet / stdin defaults.")
    , ("harvest_self_describe", "Try --generate=man, --type-list, --show-default etc.")
    , ("summarize_to_markdown", "")
    ]

rawStages F11_StructuredLinter =
    [ ("identity_and_inventory", "-h, -v, examples in README.")
    , ("find_test_inputs", "Scan container for /usr/local/<lang>/src, /usr/share/doc.")
    , ("default_output_format", "Run on real input; capture wire byte-level.")
    , ("alternative_output_modes", "-plumbing / -json / -html — byte-level each.")
    , ("output_mode_mutex", "Pairwise: do mode flags collide? -html -plumbing etc.")
    , ("threshold_config_matrix", "Numeric param boundaries: small/large/negative/zero/non-numeric.")
    , ("synthetic_delta_matrix", "Controlled deltas: rename / literal / operator / structure / type.")
    , ("stderr_stdout_routing", "Where does log / result / error each go?")
    , ("edge_cases", "Non-input file / unicode / empty stdin / duplicate input.")
    , ("summarize", "")
    ]

rawStages F12_AssetDependent =
    [ ("list_task_dir_assets", "ls assets/ fonts/ data/ templates/ first.")
    , ("probe_default_behavior", "./probe with NO flags — likely fails. Capture EXIT + error.")
    , ("find_required_path_flag", "Test -d / --asset-dir / --font-path to point at task assets.")
    , ("infocode_or_list_enum", "If tool has -I N or --list, enumerate all.")
    , ("asset_format_matrix", "For each format (.flf/.flc/.tlf or similar), at least one sample.")
    , ("layout_render_matrix", "Layout/style flags × samples.")
    , ("control_files_or_modifier", "Control / modifier flag accumulation (-C ... -C ... -N).")
    , ("getopt_old_quirks", "-foo → -f oo? option-after-msg? -h vs invalid?")
    , ("stream_routing", "")
    , ("summarize_to_tmp", "Write spec to /tmp/<task>_requirements.md NOT into task dir.")
    ]

rawStages FUnknown =
    [ ("identity", "")
    , ("explore_freely", "No form detected — generic exploration. Use idioms 1-6.")
    , ("classify_after_probes", "After ~5 probes, attempt re-classification.")
    , ("summarize", "")
    ]
