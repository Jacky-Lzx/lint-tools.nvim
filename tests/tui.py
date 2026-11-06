#!/usr/bin/env python3
"""Exercise saves through typed terminal input and inspect rendered Neovim cells."""
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="lint-tui-") as directory:
    env = dict(os.environ, TERM="xterm-256color", LINT_TUI_DIR=directory,
               XDG_STATE_HOME=directory + "/state", XDG_CACHE_HOME=directory + "/cache",
               NVIM_LOG_FILE=directory + "/nvim.log")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 110, 0, 0))
    process = subprocess.Popen(
        [os.environ.get("NVIM", "nvim"), "-u", "tests/minimal_init.lua", "-i", "NONE", "-n",
         "-c", "lua dofile('tests/tui.lua')"], cwd=root, env=env,
        stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    actions = {"save": b":write\r", "edit": b"gg0Cecho clean\x1b", "burst": b":write\r:write\r:write\r"}
    handled, output = set(), bytearray()
    deadline = time.monotonic() + 40
    try:
        while process.poll() is None and time.monotonic() < deadline:
            readable, _, _ = select.select([master], [], [], 0.05)
            if readable:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
            path = Path(directory, "stage")
            stage = path.read_text().strip() if path.exists() else ""
            if stage in actions and stage not in handled:
                os.write(master, actions[stage])
                handled.add(stage)
        process.wait(timeout=max(0.1, deadline - time.monotonic()))
        result = Path(directory, "result")
        if process.returncode or not result.exists():
            failure = Path(directory, "failure")
            raise AssertionError(failure.read_text() if failure.exists() else output.decode(errors="replace"))
        assert handled == set(actions), handled
        print(result.read_text().strip())
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        os.close(master)
