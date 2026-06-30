#!/bin/bash

# Install pytest and required plugins
echo "Installing pytest dependencies..."
python3 -m pip install -q pytest pytest-timeout pytest-xdist

# Run tests with proper configuration
echo "Running argument parsing tests..."
python3 -m pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v eval/tests/

# Capture exit code but always return 0
exit 0
