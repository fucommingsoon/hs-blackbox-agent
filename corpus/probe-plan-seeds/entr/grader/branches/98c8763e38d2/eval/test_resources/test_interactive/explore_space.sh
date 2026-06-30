#!/bin/bash
# Test space key triggering command execution

SESSION="test_space_$$"
TEST_FILE="/tmp/test_space_$$.txt"
WATCH_FILE="/tmp/watch_space_$$.txt"
OUTPUT_FILE="/tmp/output_space_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $TEST_FILE $WATCH_FILE $OUTPUT_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Run entr without -n flag (interactive mode)
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable echo 'Command executed' > $OUTPUT_FILE" Enter

# Wait for entr to start
sleep 1

# Capture initial state
echo "=== Initial state ===" 
tmux capture-pane -t $SESSION -p
echo ""

# Send space key to trigger execution
tmux send-keys -t $SESSION Space

# Wait for command to complete
sleep 1

# Check output file
echo "=== After space key ===" 
if [ -f "$OUTPUT_FILE" ]; then
    cat "$OUTPUT_FILE"
else
    echo "No output file created"
fi
echo ""

# Capture pane again
tmux capture-pane -t $SESSION -p

# Quit entr
tmux send-keys -t $SESSION q

sleep 0.5
