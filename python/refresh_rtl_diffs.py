#!/usr/bin/env python3
"""Refresh the `rtl_diff` field in every problem JSON.

The mining flow saved diffs whose final hunks were occasionally truncated
(missing trailing context lines, off-by-one in some pulp-platform sources).
This script recomputes the diff canonically as:

    git diff <buggy_rtl_commit> <fix_commit> -- <rtl_files_changed...>

and writes the result back into the problem JSON, updating `rtl_diff` and
`rtl_diff_lines` together. Skips problems whose canonical diff already
matches what's stored.

Run once before the first benchmarking sweep; rerun if `try_commit.py` ever
regresses.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from dvbench.git_repo import GitRepo
from dvbench.problem_database import ProblemDatabase


def main() -> int:
    refreshed = 0
    skipped = 0
    failed: list[tuple[str, str]] = []
    for problem_json_path in ProblemDatabase().list_all_paths():
        problem_json_data = json.loads(problem_json_path.read_text())
        clone_dir = Path("clones") / problem_json_data["owner"] / problem_json_data["repo_name"]
        if not (clone_dir / ".git").exists():
            failed.append((problem_json_data["problem_id"], "clone missing"))
            continue

        git_repo = GitRepo(clone_dir, tee_git_commands=False)
        git_repo.fetch(problem_json_data["fix_commit"], raise_on_failure=False)
        git_repo.fetch(problem_json_data["buggy_rtl_commit"], raise_on_failure=False)

        diff_result = subprocess.run(
            ["git", "-C", str(clone_dir), "diff",
             problem_json_data["buggy_rtl_commit"],
             problem_json_data["fix_commit"],
             "--"] + problem_json_data["rtl_files_changed"],
            capture_output=True, text=True,
        )
        if diff_result.returncode != 0:
            failed.append((problem_json_data["problem_id"], diff_result.stderr.strip()[:120]))
            continue
        canonical_diff = diff_result.stdout

        if canonical_diff.rstrip("\n") == problem_json_data["rtl_diff"].rstrip("\n"):
            skipped += 1
            continue

        added = sum(
            1 for line in canonical_diff.splitlines()
            if line.startswith("+") and not line.startswith("+++")
        )
        removed = sum(
            1 for line in canonical_diff.splitlines()
            if line.startswith("-") and not line.startswith("---")
        )
        problem_json_data["rtl_diff"] = canonical_diff
        problem_json_data["rtl_diff_lines"] = added + removed
        problem_json_path.write_text(json.dumps(problem_json_data, indent=2) + "\n")
        print(f"  refreshed: {problem_json_data['problem_id']}", file=sys.stderr)
        refreshed += 1

    print(f"\nRefreshed {refreshed}, unchanged {skipped}, failed {len(failed)}", file=sys.stderr)
    for pid, reason in failed:
        print(f"  FAILED {pid}: {reason}", file=sys.stderr)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
