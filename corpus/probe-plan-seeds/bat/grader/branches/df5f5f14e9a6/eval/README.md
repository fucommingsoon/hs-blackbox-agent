# Help Output Tests for bat Executable

This directory contains behavioral tests for the help and usage output of the `bat` executable.

## Running the Tests

From the repository root, run:

```bash
./eval/run.sh
```

This script will:
1. Install required pytest dependencies
2. Run all tests with a 5-second timeout per test
3. Generate results in JUnit XML format at `eval/results.xml`

## Test Structure

- `conftest.py` - Shared fixtures and utilities
- `test_help_flags.py` - Tests for help flags (--help, -h) and exit codes
- `test_help_structure.py` - Tests for help output structure and sections
- `test_help_flags_content.py` - Tests for flag documentation completeness
- `test_help_sections.py` - Tests for content of each help section
- `test_help_formatting.py` - Tests for formatting and whitespace
- `test_help_baseline.py` - Full baseline comparison tests
- `test_version_flag.py` - Tests for version flag behavior
- `help_baseline.txt` - Baseline help output for comparison

## Requirements

- Python 3.6+
- pytest
- pytest-timeout
- pytest-xdist (for parallel execution)
