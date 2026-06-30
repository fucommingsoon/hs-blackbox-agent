#!/bin/bash
# Test -p (postpone) option with space key

SESSION="test_postpone_$$"
WATCH_FILE="/tmp/watch_postpone_$$.txt"
OUTPUT_FILE="/tmp/output_postpone_$$.txt"

# Clean up
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE $OUTPUT_FILE" EXIT

# Create watch file
echo "content" > $WATCH_FILE
> $OUTPUT_FILE

# Start tmux session
tmux new-session -d -s $SESSION

# Run entr with -p flag (postpone initial execution)
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable -p sh -c 'echo \"Executed\" >> $OUTPUT_FILE'" Enter

# Wait a bit
sleep 1

echo "=== After entr starts (with -p, no initial execution) ==="
if [ -s "$OUTPUT_FILE" ]; then
    cat $OUTPUT_FILE
else
    echo "No output yet (correct with -p)"
fi

# Press space to trigger execution
tmux send-keys -t $SESSION Space
sleep 0.5

echo "=== After space key press ==="
cat $OUTPUT_FILE

# Quit
tmux send-keys -t $SESSION q
