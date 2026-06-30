# Externalized end-to-end tests

This repository's internal tests are implemented as a shell-based system test suite (`system_test.sh`).
These tests drive the compiled `entr` executable by providing file lists on stdin, modifying watched files,
and asserting on exit codes and output.

We externalize those behaviors into black-box pytest tests that invoke the compiled binary at `./executable`.

## How to run

From repository root:

```bash
./eval/run.sh
```

This produces JUnit XML at `eval/results.xml`.

## Externalized test mapping

| Original test (system_test.sh) | External pytest test | Upward trace (CLI/input path) | Downward trace (output path) |
|---|---|---|---|
| no arguments | `test_ext_no_arguments_usage` | `main()` arg parsing sees argc==1 | `usage()` -> stderr contains `usage:` and exit 1 |
| display option summary | `test_ext_display_option_summary_help` | `-h` flag triggers help path | summary printed to stdout, usage to stderr, exit 1 |
| no input | `test_ext_no_input_exits_1` | stdin file list is empty/newline only | input validation fails -> exit 1 |
| reload and clear options with no utility to run | `test_ext_reload_and_clear_no_utility` | `-r -c` but no utility args | option parsing aborts -> exit 1 |
| empty input | `test_ext_empty_input_exits_1` | stdin empty string provides no files | exits 1 |
| no regular files provided as input | `test_ext_no_regular_files_in_input_exits_1` | stdin contains a directory path w/out `-d` | rejected watch list -> exit 1 |
| invalid signal number set | `test_ext_invalid_restart_signal_env_rejected` | `-r` reads `ENTR_RESTART_SIGNAL` | invalid value -> exit 1 |
| install default status script | `test_ext_install_default_status_script` | `-x` + `ENTR_STATUS_SCRIPT` missing triggers creation | creation message + formatted exit code printed to stdout |
| status script not compatible with restart option | `test_ext_status_script_incompatible_with_restart` | `-r -x` combination | aborts with exit 1 |
| block unsafe status script | `test_ext_block_unsafe_status_script` | `-x` runs custom awk from `ENTR_STATUS_SCRIPT` | safety check errors -> stderr contains `awk: system is unsafe` |
| allow unsafe status script | `test_ext_allow_unsafe_status_script_with_xx` | `-x -x` (xx) allows unsafe | no safety error in stderr |
| use custom status script | `test_ext_custom_status_script_formats_exit_code` | `-x` runs awk on child completion | awk output printed to stdout |
| abort if status script terminates | `test_ext_status_process_termination_aborts` | `-x` starts awk helper which exits immediately | `entr: status process terminated` on stderr |
| exec a command using the first file to change | `test_ext_one_shot_exec_cat_first_changed_file` | `/_' substitution uses first changed file | utility stdout forwarded; we verify content |

Note: `system_test.sh` contains additional TTY- and OS-dependent tests (tmux/vim/nc/etc.). Those can also
be externalized, but this initial external suite focuses on deterministic, non-interactive behaviors that
run reliably within 5 seconds.
