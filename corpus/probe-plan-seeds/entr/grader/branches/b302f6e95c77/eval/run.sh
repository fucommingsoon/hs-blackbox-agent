#!/usr/bin/env bash
set -euo pipefail

# Run from repo root (as required)
cd "$(dirname "$0")/.."

python3 -m pip install -q --upgrade pip
python3 -m pip install -q pytest pytest-xdist pytest-timeout

pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v

# Per requirements: exit 0 if tests were executed, even if some failed.
exit 0
