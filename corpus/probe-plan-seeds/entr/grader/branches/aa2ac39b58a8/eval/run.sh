#!/bin/bash
set -euo pipefail

# Install dependencies
pip install -q pytest pytest-timeout pytest-xdist 2>/dev/null || true

# Run tests
cd eval
pytest --junitxml=results.xml --timeout=5 --timeout-method=thread -n auto -v tests/
