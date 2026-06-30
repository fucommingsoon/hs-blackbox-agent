#!/bin/bash

set -e

# Install pytest and dependencies
python3 -m pip install -q pytest pytest-timeout pytest-xdist 2>/dev/null || true

# Run tests with JUnit XML output
cd "$(dirname "$0")"
python3 -m pytest tests/ \
    --junitxml=results.xml \
    --timeout=5 \
    --timeout-method=thread \
    -n auto \
    -v

exit 0
