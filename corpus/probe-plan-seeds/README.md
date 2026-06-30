# Probe Plan Seed Corpus

This corpus is for Haskell probe-plan runtime design. It intentionally keeps
"god-view" materials separate from ordinary black-box task inputs.

Do not feed `grader/` into the normal black-box agent loop. It is here so we can
audit real grader behavior while designing deterministic probe execution
primitives.

## Layout

- `entr/`
  - `grader/branches/<branch>/eval/`: raw ProgramBench pytest grader files.
  - `source/github/`: GitHub `eradman/entr` snapshot at commit `8e2e8b4`.
- `bat/`
  - `grader/branches/<branch>/eval/`: raw ProgramBench pytest grader files.
  - `source/github/`: GitHub `astaxie/bat` snapshot at commit `17d1080`.

## Why This Exists

The earlier `haskell-tester/distill_out/*.jsonl` files are useful indexes, but
they are derived artifacts. For this redesign, the risky part is deciding what
the Haskell runtime must be able to execute and observe. That decision should be
grounded in raw pytest grader files and upstream source, not in a condensed
summary.

Initial raw pytest counts from `grader/branches/*/eval/tests`:

- `entr`: 54 `eval/tests/test_*.py` files
- `bat`: 85 `eval/tests/test_*.py` files

Reference Docker check:

- `pbref-real-entr` contains `/workspace` with public docs, `.git`, and the
  reference executable, but no `eval/tests`.
- `pbref-real-bat` contains `/workspace` with task/workspace files and the
  reference executable, but no `eval/tests`.

So Docker reference containers are useful for probing behavior and checking the
workspace shape, but they are not currently the source of grader tests in this
corpus. The grader files here come from the local `programbench/ProgramBench-Tests`
cache, narrowed to only each branch's `eval/` directory.

## Design Boundary

Use this corpus to design and verify:

- fixture setup primitives
- process execution modes
- stdin/stdout/stderr/exit capture
- async process supervision
- file mutation triggers
- local HTTP fixtures
- feature-matrix extraction

Do not use this corpus as evidence that a black-box exploration agent could have
known a behavior without probing it.
