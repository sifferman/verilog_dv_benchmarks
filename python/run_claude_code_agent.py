#!/usr/bin/env python3
"""Entry point for the Claude Code agent runner. See
dvbench/claude_code_agent_cli.py for the actual implementation."""
from __future__ import annotations

import sys

from dvbench.claude_code_agent_cli import main

if __name__ == "__main__":
    sys.exit(main())
