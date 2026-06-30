#!/usr/bin/env bash
set -u

# Run from repository root as ./eval/run.sh
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 -m pip install -q --upgrade pip
python3 -m pip install -q pytest pytest-xdist pytest-timeout pytest-dependency

# Always exit 0 as long as tests were executed.
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v || true
