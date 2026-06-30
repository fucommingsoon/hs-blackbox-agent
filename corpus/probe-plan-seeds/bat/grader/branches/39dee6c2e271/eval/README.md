# Test Suite for bat executable

This directory contains behavioral tests for the bat CLI HTTP client.

## Running the Tests

From the workspace root, run:

```bash
./eval/run.sh
```

Or directly with pytest:

```bash
cd eval
pip install pytest pytest-timeout pytest-xdist pytest-dependency
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v
```

## Test Categories

- **Help and Version**: Tests for --help, -v, --version flags
- **HTTP Methods**: Tests for GET, POST, PUT, DELETE methods
- **Print Options**: Tests for -print flag (H, h, B, b)
- **Request Data**: Tests for key=value, key:value, query params
- **Form Submission**: Tests for -form and -f flags
- **JSON Options**: Tests for -json and -pretty flags
- **Authentication**: Tests for -a flag
- **URL Handling**: Tests for URL parsing and localhost shorthand
- **Other Flags**: Tests for -body, -download, -insecure, -proxy, -bench

## Notes

- The bat CLI uses positional arguments: `bat [flags] METHOD URL [ITEM...]`
- Flags must come before METHOD
- The default scheme is http:// if not specified
- With data, default method is POST; without data, default is GET
