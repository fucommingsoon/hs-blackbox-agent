#!/usr/bin/env bash
set -euo pipefail

python3 -m pip -q install --upgrade pip >/dev/null
python3 -m pip -q install pytest pytest-xdist pytest-timeout >/dev/null

# Run from repo root; write results to eval/results.xml
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v

# Per task requirement: exit 0 if tests executed (even if some fail)
exit 0
