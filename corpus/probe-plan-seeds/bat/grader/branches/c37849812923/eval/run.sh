#!/bin/bash
set -e

# Install dependencies
pip install pytest pytest-timeout pytest-xdist libtmux

# Run the tests
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v eval/tests/

# Exit with 0
exit 0
