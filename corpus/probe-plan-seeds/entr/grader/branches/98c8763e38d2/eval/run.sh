#!/bin/bash
set -e
cd "$(dirname "$0")"

# Install system dependencies for harvest tests
apt-get update -qq 2>/dev/null || true
apt-get install -y file 2>/dev/null || true

# Install pytest and dependencies
pip install pytest pytest-timeout pytest-xdist psutil 2>/dev/null || pip3 install pytest pytest-timeout pytest-xdist psutil 2>/dev/null

# Run tests
python3 -m pytest tests/ -n auto -v --timeout=30 --tb=short --junitxml=results.xml || true
