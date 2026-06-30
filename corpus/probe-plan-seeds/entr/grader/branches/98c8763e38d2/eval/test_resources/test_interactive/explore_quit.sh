#!/bin/bash
# Test q key quitting entr

SESSION="test_quit_$$"
WATCH_FILE="/tmp/watch_quit_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Run entr in interactive mode
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable echo test" Enter

# Wait for entr to start
sleep 1

# Send 'q' key
tmux send-keys -t $SESSION q

# Wait a bit
sleep 0.5

# Check if session still exists (it should be gone)
if tmux has-session -t $SESSION 2>/dev/null; then
    echo "Session still exists - entr did not quit"
    tmux capture-pane -t $SESSION -p
else
    echo "Session ended - entr quit successfully"
fi
