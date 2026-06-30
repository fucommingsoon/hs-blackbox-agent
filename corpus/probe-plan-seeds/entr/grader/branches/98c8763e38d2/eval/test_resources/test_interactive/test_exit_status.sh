#!/bin/bash
SESSION="test_exit_$$"
WATCH_FILE="/tmp/watch_exit_$$.txt"
trap "tmux kill-session -t $SESSION 2>/dev/null; rm -f $WATCH_FILE" EXIT

echo "content" > $WATCH_FILE
tmux new-session -d -s $SESSION
tmux send-keys -t $SESSION "echo $WATCH_FILE | /workspace/./executable -x sh -c 'exit 42'" Enter
sleep 2

echo "=== Screen after initial execution ==="
tmux capture-pane -t $SESSION -p

tmux send-keys -t $SESSION Space
sleep 1

echo ""
echo "=== Screen after space ==="
tmux capture-pane -t $SESSION -p

tmux send-keys -t $SESSION q
