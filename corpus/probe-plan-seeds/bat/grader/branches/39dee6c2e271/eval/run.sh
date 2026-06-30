#!/bin/bash
set -e

# Get the workspace root directory (parent of eval)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Install pytest and dependencies
pip install pytest pytest-timeout pytest-dependency 2>/dev/null

# Run pytest with the specified options from the workspace root
# Results are written to eval/results.xml
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -v
