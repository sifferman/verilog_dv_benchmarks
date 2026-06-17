#!/usr/bin/env python3
"""Entry point for the evaluate harness. See dvbench/evaluate_cli.py for the
actual implementation."""
from __future__ import annotations

import sys

from dvbench.evaluate_cli import main

if __name__ == "__main__":
    sys.exit(main())
