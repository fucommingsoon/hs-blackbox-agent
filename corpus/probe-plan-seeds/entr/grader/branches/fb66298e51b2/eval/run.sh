#!/bin/bash

set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "========================================="
echo "entr Interactive Behavior Test Suite"
echo "========================================="
echo ""

# Install Python dependencies
echo "Installing dependencies..."
pip install -q pytest pytest-timeout pytest-dependency libtmux 2>&1 | grep -v "Requirement already satisfied" || true

echo ""
echo "Running tests..."
echo ""

# Change to repo root to ensure relative paths work
cd "$REPO_ROOT"

# Run pytest with proper options
pytest eval/tests/ \
    --junitxml=eval/results.xml \
    --timeout=5 \
    --timeout-method=thread \
    -v \
    "$@"

# Capture exit code
EXIT_CODE=$?

echo ""
echo "========================================="
echo "Test execution complete"
echo "Results saved to: eval/results.xml"
echo "========================================="

# Exit with 0 even if tests fail (as per requirements)
exit 0
