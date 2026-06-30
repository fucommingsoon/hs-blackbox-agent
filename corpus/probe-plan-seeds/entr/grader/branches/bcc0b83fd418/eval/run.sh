#!/bin/bash

# Install pytest dependencies
echo "Installing pytest dependencies..."
python3 -m pip install -q pytest pytest-timeout pytest-xdist

# Navigate to eval directory
cd eval

# Run tests with JUnit XML output
# NOTE: Running sequentially (no -n auto) because entr tests conflict when parallel
echo "Running tests..."
python3 -m pytest tests/ \
    --junitxml=results.xml \
    --timeout=5 \
    --timeout-method=thread \
    -v || true

echo "Tests completed. Results saved to eval/results.xml"
exit 0
