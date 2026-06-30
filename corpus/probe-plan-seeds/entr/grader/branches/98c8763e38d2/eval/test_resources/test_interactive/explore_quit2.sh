#!/bin/bash
# Test q key quitting entr with better detection

SESSION="test_quit_$$"
WATCH_FILE="/tmp/watch_quit_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Run entr in interactive mode
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable echo test; echo 'ENTR_EXITED'" Enter

# Wait for entr to start
sleep 1

echo "=== Before 'q' key ==="
OUTPUT=$(tmux capture-pane -t $SESSION -p)
echo "$OUTPUT"
echo ""

# Send 'q' key
tmux send-keys -t $SESSION q

# Wait
sleep 0.5

echo "=== After 'q' key ==="
OUTPUT=$(tmux capture-pane -t $SESSION -p)
echo "$OUTPUT"
echo ""

# Check if ENTR_EXITED appears
if echo "$OUTPUT" | grep -q "ENTR_EXITED"; then
    echo "SUCCESS: entr exited cleanly"
else
    echo "FAILED: entr did not exit"
fi
