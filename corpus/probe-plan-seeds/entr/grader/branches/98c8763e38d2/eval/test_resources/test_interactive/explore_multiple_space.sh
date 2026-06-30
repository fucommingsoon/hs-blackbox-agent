#!/bin/bash
# Test multiple space key presses

SESSION="test_multi_$$"
WATCH_FILE="/tmp/watch_multi_$$.txt"
COUNTER_FILE="/tmp/counter_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE $COUNTER_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE
echo "0" > $COUNTER_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Run entr that increments a counter
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable sh -c 'N=\$(cat $COUNTER_FILE); N=\$((N+1)); echo \$N > $COUNTER_FILE; echo \"Execution \$N\"'" Enter

# Wait for initial execution
sleep 1

echo "=== After initial execution ==="
cat $COUNTER_FILE

# Press space 3 times
for i in 1 2 3; do
    tmux send-keys -t $SESSION Space
    sleep 0.5
done

echo "=== After 3 space presses ==="
cat $COUNTER_FILE

# Quit
tmux send-keys -t $SESSION q
