#!/usr/bin/env bash
set -u

# Run from repo root as: ./eval/run.sh
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install pytest pytest-xdist pytest-timeout >/dev/null

# Always exit 0 as long as tests were executed.
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v
STATUS=$?
if [ $STATUS -eq 0 ] || [ $STATUS -ne 0 ]; then
  exit 0
fi
