#!/bin/bash
set -e
cd "$(dirname "$0")"

# Install test dependencies
pip install pytest pytest-timeout pytest-xdist requests -q 2>/dev/null || true

# Run tests WITHOUT -n auto due to Go coverage bug
# Parallel execution corrupts coverage data
python3 -m pytest tests/ -v --timeout=30 --tb=short --junitxml=results.xml || true
