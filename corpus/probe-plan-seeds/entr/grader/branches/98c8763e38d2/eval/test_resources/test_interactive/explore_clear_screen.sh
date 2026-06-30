#!/bin/bash
# Test -c (clear screen) option with space key

SESSION="test_clear_$$"
WATCH_FILE="/tmp/watch_clear_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE

# Start tmux session with larger screen
tmux new-session -d -s $SESSION -x 80 -y 24

# Run entr with -c flag
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable -c echo 'Test output line 1'; echo 'Test output line 2'" Enter

# Wait for initial execution
sleep 1

echo "=== After initial execution ==="
tmux capture-pane -t $SESSION -p | head -20

# Press space to trigger again
tmux send-keys -t $SESSION Space
sleep 0.5

echo ""
echo "=== After space (should have cleared screen) ==="
tmux capture-pane -t $SESSION -p | head -20

# Quit
tmux send-keys -t $SESSION q
