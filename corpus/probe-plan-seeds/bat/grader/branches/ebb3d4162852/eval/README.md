# Test Suite for bat

This directory contains behavioral tests for the `bat` executable, a CLI HTTP client tool for humans.

## Running the Tests

From the repository root, run:

```bash
./eval/run.sh
```

This will:
1. Install required Python dependencies (pytest, pytest-timeout, pytest-xdist)
2. Run all tests with a 5-second timeout per test
3. Generate results in `eval/results.xml` (JUnit XML format)

## Test Structure

- `tests/utils.py` - Utility functions for running the executable
- `tests/test_server.py` - Simple HTTP server for testing
- `tests/test_basic.py` - Version, help, and basic functionality
- `tests/test_http_methods.py` - HTTP methods and URL parsing
- `tests/test_data_input.py` - JSON, forms, headers, and stdin input
- `tests/test_output_control.py` - Output formatting and print options
- `tests/test_authentication.py` - Auth, proxy, and SSL options
- `tests/test_edge_cases.py` - Error handling and edge cases

## Requirements

- Python 3.6+
- pytest
- pytest-timeout
- pytest-xdist
