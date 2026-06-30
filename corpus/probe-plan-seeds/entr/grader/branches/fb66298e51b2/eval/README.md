# entr Interactive Behavior Tests

This directory contains tests for the interactive keyboard behavior of `entr`, a file watcher utility.

## Application Type

While `entr` is not a traditional TUI application (it doesn't use curses/ncurses or take over the terminal screen), it does have interactive keyboard commands that respond to user input:

- **Space**: Trigger immediate execution of the utility
- **q**: Quit the program (equivalent to Ctrl-C)

These tests validate that the interactive keyboard behavior works correctly.

## Test Coverage

The test suite covers:
- Basic startup and execution behavior
- Interactive keyboard commands (space and q)
- Various command-line flags (-p, -r, -c, -s, -z, -d, -n, -a, -x)
- Multiple file watching
- Error handling and edge cases
- Rapid input handling
- Process restart behavior
- Output capture
- Exit behavior

## Running Tests

To run all tests:

```bash
./eval/run.sh
```

Tests run in tmux sessions to provide a pseudo-TTY environment required by entr.

## Requirements

- Python 3.6+
- pytest
- pytest-timeout
- pytest-dependency
- libtmux
- tmux (system package)

All Python dependencies are installed automatically by the run script.
