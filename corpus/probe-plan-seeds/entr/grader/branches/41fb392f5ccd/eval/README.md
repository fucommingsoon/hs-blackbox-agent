# Subcommand Dispatch and Routing Tests

## Overview

This test suite validates subcommand dispatch and routing behavior for the executable.

**Important Finding**: After analysis, the `entr` executable does NOT use a git-style subcommand architecture. It is a file watcher utility with a single mode of operation that takes flags and a utility command to execute.

## Test Coverage

The tests verify:
- The executable does not have a subcommand architecture
- Arguments are treated as utility commands, not subcommands
- Help output is consistent (no subcommand-specific help)
- All flags work uniformly with any utility command
- No routing to different execution modes based on first argument

## Running the Tests

From the repository root:

```bash
./eval/run.sh
```

Or directly with pytest:

```bash
cd eval
pytest tests/test_subcommand_dispatch.py -v --junitxml=results.xml --timeout=5
```

## Requirements

- Python 3.6+
- pytest
- pytest-timeout
- pytest-xdist
