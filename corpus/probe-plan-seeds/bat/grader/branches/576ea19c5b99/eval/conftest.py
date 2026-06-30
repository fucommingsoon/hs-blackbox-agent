import subprocess
import os
import tempfile
import shutil
from pathlib import Path
import pytest

# Executable is in the parent directory
EXECUTABLE = str(Path(__file__).parent.parent / "executable")

def run(*args, stdin=None, env=None, cwd=None, timeout=5.0):
    """Run the executable with given arguments and optional stdin."""
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    return subprocess.run(
        [EXECUTABLE, *args],
        input=stdin.encode() if isinstance(stdin, str) else stdin,
        capture_output=True, 
        timeout=timeout, 
        env=full_env, 
        cwd=cwd,
    )

class TempFiles:
    """Context manager for creating temporary test files."""
    def __init__(self): 
        self.tempdir = None
    
    def __enter__(self):
        self.tempdir = tempfile.mkdtemp()
        return self
    
    def __exit__(self, *args):
        shutil.rmtree(self.tempdir, ignore_errors=True)
    
    def create(self, name, content):
        path = Path(self.tempdir) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode() if isinstance(content, str) else content)
        return path

@pytest.fixture
def temp_files():
    """Fixture for creating temporary test files."""
    with TempFiles() as tf:
        yield tf
