#!/bin/bash
# Test space key during command execution

SESSION="test_during_$$"
WATCH_FILE="/tmp/watch_during_$$.txt"
OUTPUT_FILE="/tmp/output_during_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE $OUTPUT_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE
echo "0" > $OUTPUT_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Run entr with a slow command
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable sh -c 'N=\$(cat $OUTPUT_FILE); N=\$((N+1)); echo \$N > $OUTPUT_FILE; sleep 2; echo \"Done \$N\"'" Enter

# Wait for initial execution to start
sleep 0.5

# Press space while command is running
tmux send-keys -t $SESSION Space

# Wait for both executions to complete
sleep 3

echo "=== Counter after space during execution ==="
cat $OUTPUT_FILE

# Quit
tmux send-keys -t $SESSION q
