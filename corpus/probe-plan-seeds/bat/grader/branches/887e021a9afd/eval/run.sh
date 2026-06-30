#!/bin/bash
set -e

# Navigate to script directory
cd "$(dirname "$0")"

# Install dependencies
echo "Installing pytest dependencies..."
python3 -m pip install -q pytest pytest-timeout pytest-xdist 2>&1 | grep -v "Requirement already satisfied" || true

# Run tests
echo "Running tests..."
python3 -m pytest tests/test_env_and_config.py \
    --junitxml=results.xml \
    --timeout=5 \
    --timeout-method=thread \
    -n auto \
    -v

# Ensure exit code 0 even if tests fail
exit 0
