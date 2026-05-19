#!/usr/bin/env python3
"""Entry point for prepare_sandbox. See dvbench/prepare_sandbox_cli.py for the
actual implementation; this file exists so users can invoke
`python3 python/prepare_sandbox.py …` directly.

TEMPORARY proof-of-concept — see dvbench/prepare_sandbox_cli.py header."""
from __future__ import annotations

import sys

from dvbench.prepare_sandbox_cli import main

if __name__ == "__main__":
    sys.exit(main())
