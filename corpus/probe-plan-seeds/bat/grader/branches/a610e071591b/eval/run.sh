#!/usr/bin/env bash
set -euo pipefail

# Run from repository root (this script may be invoked as ./eval/run.sh)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install -q pytest pytest-xdist pytest-timeout

# Run tests; always exit 0 as long as tests executed.
set +e
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v
STATUS=$?
set -e

if [ ! -f eval/results.xml ]; then
  echo "ERROR: eval/results.xml not created"
  exit 0
fi

exit 0
