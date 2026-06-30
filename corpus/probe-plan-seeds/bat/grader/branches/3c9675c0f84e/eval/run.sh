#!/usr/bin/env bash
set -euo pipefail

mkdir -p eval

python3 -m pip -q install --upgrade pip
python3 -m pip -q install pytest pytest-xdist pytest-timeout

# Run tests (if any). Always exit 0 as required.
set +e
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v
status=$?
set -e

exit 0
