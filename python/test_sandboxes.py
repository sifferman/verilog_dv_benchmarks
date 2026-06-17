#!/usr/bin/env python3
"""Entry point for the test_sandboxes harness. See dvbench/test_sandboxes_cli.py
for the actual implementation; this file exists so users can invoke
`python3 python/test_sandboxes.py …` directly."""
from __future__ import annotations

import sys

from dvbench.test_sandboxes_cli import main

if __name__ == "__main__":
    sys.exit(main())
