#!/usr/bin/env bash
set -euo pipefail

# Run from repo root as ./eval/run.sh
cd "$(dirname "$0")/.."

python3 -m pip install -q --upgrade pip
python3 -m pip install -q pytest pytest-xdist pytest-timeout

mkdir -p eval
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -v || true

exit 0
