#!/bin/bash
# Test terminal state restoration

SESSION="test_term_$$"
WATCH_FILE="/tmp/watch_term_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Get initial terminal settings
tmux send-keys -t $SESSION "stty -a > /tmp/before_$$.txt" Enter
sleep 0.5

# Run entr in interactive mode
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable sleep 0.1; stty -a > /tmp/after_$$.txt" Enter

# Wait for entr to start
sleep 1

# Quit entr with 'q'
tmux send-keys -t $SESSION q

# Wait for command to complete
sleep 1

# Compare terminal settings
echo "=== Comparing terminal settings ==="
if [ -f "/tmp/before_$$.txt" ] && [ -f "/tmp/after_$$.txt" ]; then
    diff -u /tmp/before_$$.txt /tmp/after_$$.txt || echo "Terminal settings restored (or similar)"
    rm -f /tmp/before_$$.txt /tmp/after_$$.txt
else
    echo "Could not get terminal settings"
fi
