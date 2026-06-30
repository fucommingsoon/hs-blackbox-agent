#!/usr/bin/env bash
set -euo pipefail

python3 -m pip install -q --upgrade pip
python3 -m pip install -q pytest pytest-xdist pytest-timeout

# Run from repo root; write JUnit XML to eval/results.xml
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v

# Per task requirements: exit 0 if tests were executed
exit 0
