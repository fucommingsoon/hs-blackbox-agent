#!/bin/bash
# Script that runs for a while and can be interrupted
echo "START"
for i in {1..100}; do
    echo "iteration $i"
    sleep 0.1
done
echo "DONE"
