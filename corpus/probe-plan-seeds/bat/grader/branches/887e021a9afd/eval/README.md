# Bat Executable Tests - Environment Variables and Configuration

This test suite validates environment variable handling and configuration behavior for the `bat` executable.

## Test Coverage

- **Environment Variables**: HTTP_PROXY, HTTPS_PROXY, NO_PROXY
- **Command-line Flags**: All major flags including --proxy, -a, -f, -j, -p, -print, etc.
- **Configuration Precedence**: CLI flags override environment variables
- **Default Behavior**: User-Agent, Accept headers, HTTP methods, etc.
- **Error Handling**: Invalid URLs, malformed input, connection errors
- **URL Parsing**: Localhost shorthand, protocol defaults
- **Request Items**: Headers, data fields, JSON, forms

## Running Tests

```bash
./eval/run.sh
```

The script will:
1. Install pytest and required dependencies
2. Run all tests with timeout enforcement (5s per test)
3. Generate JUnit XML results in `eval/results.xml`

## Requirements

- Python 3.6+
- pytest
- pytest-timeout
- pytest-xdist
- Network connectivity (tests use httpbin.org)
