#!/usr/bin/env bash
set -eu

cd "$(dirname "$0")/.."

python3 -m pip install -q --upgrade pip
python3 -m pip install -q pytest pytest-xdist pytest-timeout

# Execute tests; always exit 0 as long as tests were executed.
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v || true
