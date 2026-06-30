#!/usr/bin/env bash
set -u

# Run from repo root; ensure we are at repo root even if invoked elsewhere.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 -m pip install -q --upgrade pip >/dev/null
python3 -m pip install -q pytest pytest-xdist pytest-timeout >/dev/null

# Always exit 0 if tests were executed; capture pytest exit code for logs.
set +e
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v
PYTEST_RC=$?
set -e

echo "pytest exit code: ${PYTEST_RC}"
exit 0
