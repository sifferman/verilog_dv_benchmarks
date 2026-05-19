"""Unified subprocess wrapper used across the dvbench package.

`run_cmd` spawns a subprocess, always returns `(exit_code, full_output)`, and
takes optional flags to:
  - `tee_to_console=True`      — tee each line to `sys.stdout` as it arrives
  - `log_file=<IO>`            — also tee each line to a file
  - `timeout=<seconds>`        — kill the subprocess if it exceeds the deadline
                                  (raises `subprocess.TimeoutExpired`)
  - `raise_on_failure=True`    — raise `subprocess.CalledProcessError` on non-zero exit

The full output is always collected, so callers can both tee progress live AND
inspect what was printed at the end.
"""
from __future__ import annotations

import subprocess
import sys
import threading
from pathlib import Path
from typing import IO


def run_cmd(
    command: list[str] | str,
    cwd: Path,
    *,
    tee_to_console: bool = False,
    log_file: IO[str] | None = None,
    timeout: float | None = None,
    raise_on_failure: bool = False,
) -> tuple[int, str]:
    if tee_to_console or log_file is not None:
        invocation_line = (
            f"$ {command if isinstance(command, str) else ' '.join(command)}\n"
        )
        if tee_to_console:
            sys.stdout.write(invocation_line)
            sys.stdout.flush()
        if log_file is not None:
            log_file.write(invocation_line)
            log_file.flush()

    subprocess_handle = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        text=True,
        shell=isinstance(command, str),
    )

    deadline_exceeded = [False]
    def _kill_on_timeout() -> None:
        deadline_exceeded[0] = True
        subprocess_handle.kill()

    timeout_watchdog: threading.Timer | None = None
    if timeout is not None:
        timeout_watchdog = threading.Timer(timeout, _kill_on_timeout)
        timeout_watchdog.start()

    collected_output_lines: list[str] = []
    assert subprocess_handle.stdout is not None
    for output_line in subprocess_handle.stdout:
        collected_output_lines.append(output_line)
        if tee_to_console:
            sys.stdout.write(output_line)
            sys.stdout.flush()
        if log_file is not None:
            log_file.write(output_line)

    exit_code = subprocess_handle.wait()

    if timeout_watchdog is not None:
        timeout_watchdog.cancel()

    captured_output = "".join(collected_output_lines)

    if deadline_exceeded[0]:
        raise subprocess.TimeoutExpired(command, timeout, captured_output)
    if raise_on_failure and exit_code != 0:
        raise subprocess.CalledProcessError(exit_code, command, captured_output)

    return exit_code, captured_output
