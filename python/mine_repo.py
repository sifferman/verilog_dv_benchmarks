#!/usr/bin/env python3
"""Entry point for the mine_repo CLI. See dvbench/mine_repo_cli.py for the
actual implementation; this file exists so users can run
`python3 python/mine_repo.py …` directly."""
from __future__ import annotations

import sys

from dvbench.mine_repo_cli import main

if __name__ == "__main__":
    sys.exit(main())
