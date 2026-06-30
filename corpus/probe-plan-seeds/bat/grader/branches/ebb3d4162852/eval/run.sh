#!/bin/bash
set -e

# Install dependencies
echo "Installing test dependencies..."
pip3 install -q pytest pytest-timeout pytest-xdist 2>&1 | grep -v "Requirement already satisfied" || true

# Run tests
echo "Running tests..."
cd eval
pytest --junitxml=results.xml --timeout=5 --timeout-method=thread -n auto -v tests/
TEST_EXIT=$?

# Always exit 0 so the script succeeds even if tests fail
exit 0
