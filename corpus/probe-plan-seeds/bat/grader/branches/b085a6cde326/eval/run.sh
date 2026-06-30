#!/bin/bash

set -e

# Install pytest if not available
python3 -m pip install -q pytest pytest-timeout pytest-xdist 2>/dev/null || true

# Run tests from workspace root
cd "$(dirname "$0")/.."

# Run pytest with required options
python3 -m pytest eval/tests/ \
    --junitxml=eval/results.xml \
    --timeout=5 \
    --timeout-method=thread \
    -n auto \
    -v \
    "$@"

# Always exit 0 so tests are recorded even if some fail
exit 0
