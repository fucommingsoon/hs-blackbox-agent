#!/bin/bash
set -e

# Install pytest and required plugins if not already installed
echo "Installing test dependencies..."
python3 -m pip install -q pytest pytest-timeout pytest-xdist

# Run the tests from the repository root
echo "Running subcommand dispatch and routing tests..."
cd "$(dirname "$0")/.."
python3 -m pytest eval/tests/test_subcommand_dispatch.py \
    --junitxml=eval/results.xml \
    --timeout=5 \
    --timeout-method=thread \
    -n auto \
    -v

# Always exit with 0 if tests were executed
exit 0
