#!/usr/bin/env python3
"""Entry point for the verify_problem harness. See dvbench/verify_problem_cli.py
for the actual implementation; this file exists so users can invoke
`python3 python/verify_problem.py …` directly."""
from __future__ import annotations

import sys

from dvbench.verify_problem_cli import main

if __name__ == "__main__":
    sys.exit(main())
