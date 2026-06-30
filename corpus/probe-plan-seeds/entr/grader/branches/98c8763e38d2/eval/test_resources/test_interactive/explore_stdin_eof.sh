#!/bin/bash
# Test EOF on stdin

SESSION="test_eof_$$"
WATCH_FILE="/tmp/watch_eof_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Run entr
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable echo test; echo 'EXITED'" Enter

# Wait for entr to start
sleep 1

# Send Ctrl-D (EOF) to stdin - this should be handled gracefully
tmux send-keys -t $SESSION C-d

sleep 1

echo "=== After Ctrl-D (EOF) ==="
tmux capture-pane -t $SESSION -p

# Check if still running or exited
if tmux capture-pane -t $SESSION -p | grep -q "EXITED"; then
    echo "Entr did not exit on EOF (still running)"
else
    echo "Entr still running"
fi

# Quit
tmux send-keys -t $SESSION q
