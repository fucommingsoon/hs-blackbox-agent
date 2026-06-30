#!/usr/bin/env bash

# Script to run all tests for bat executable help output
# Exit with 0 even if tests fail (only fail on execution errors)

set +e  # Don't exit on test failures

# Change to the directory containing this script
cd "$(dirname "$0")"

echo "Installing pytest dependencies..."
python3 -m pip install -q pytest pytest-timeout pytest-xdist

echo ""
echo "Running tests..."
echo ""

# Run pytest with required options
python3 -m pytest --junitxml=results.xml --timeout=5 --timeout-method=thread -n auto -v tests/

# Capture pytest exit code
PYTEST_EXIT=$?

echo ""
echo "Tests completed. Results saved to eval/results.xml"
echo ""

# Always exit 0 per requirements (even if tests fail)
exit 0
