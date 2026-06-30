#!/usr/bin/env bash
set -euo pipefail

python3 -m pip -q install --upgrade pip >/dev/null
python3 -m pip -q install pytest pytest-xdist pytest-timeout >/dev/null

# Run tests. Exit status must be 0 if tests executed.
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v || true
