# Argument Parsing Tests for bat

This directory contains behavioral tests for the `bat` executable's argument parsing and validation.

## Running the Tests

Execute the test suite from the repository root:

```bash
./eval/run.sh
```

This script will:
1. Install required pytest dependencies (pytest, pytest-timeout, pytest-xdist)
2. Run all tests with a 5-second timeout per test
3. Generate results in JUnit XML format at `eval/results.xml`

## Test Coverage

The tests cover:
- Flag formats (short `-f`, long `--form`, aliases)
- Required vs optional arguments
- Value validation (integers, strings, special characters)
- Invalid/unknown flags
- Flag combinations and ordering
- Error messages and exit codes
- Boolean flag behavior
- Empty and edge case values

## Requirements

- Python 3.x
- pytest
- pytest-timeout
- pytest-xdist
