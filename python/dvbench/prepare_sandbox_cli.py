"""
prepare_sandbox.py — proof-of-concept sandbox builder.

TEMPORARY: This is a quick demonstration of how a saved Problem can be
materialized into a self-contained working directory that an LLM (or a human)
could open and try to debug. It is *not* the final evaluation harness. The
long-term plan is a SWE-bench-style Docker pipeline (base → env → instance
images, isolated containers per attempt, FAIL_TO_PASS / PASS_TO_PASS grading,
patch-application contract). This script will be retired once that lands —
keep it small and obvious; do not grow features here.

What this does
--------------
Given a saved problem JSON, materialize a sandbox directory containing:
  - an isolated copy of the repo clone, hard-checked-out to the fix commit
  - RTL files reverted to the buggy commit (so the test command fails)
  - a DEBUG_ME.md brief telling the reader what to do
  - no ground-truth diff (rtl_diff is deliberately withheld)
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

import typer

from dvbench.constants import SANDBOXES_DIRECTORY
from dvbench.git_repo import GitRepo
from dvbench.problem_database import ProblemDatabase
from dvbench.records import Problem


def prepare_sandbox(
    problem_id: str = typer.Option(..., "--problem-id", help="Full or sha-only problem id"),
    output_dir: Path | None = typer.Option(
        None, "--output-dir",
        help="Where to materialize the sandbox. Default: sandboxes/{problem_id}/"
    ),
    overwrite: bool = typer.Option(
        False, "--overwrite", help="Delete the sandbox directory if it already exists"
    ),
) -> None:
    problem = Problem.load_from_json(ProblemDatabase().resolve_by_id(problem_id))
    sandbox_dir = output_dir or SANDBOXES_DIRECTORY / problem.problem_id

    if sandbox_dir.exists():
        if not overwrite:
            print(
                f"Sandbox already exists at {sandbox_dir}. Pass --overwrite to replace.",
                file=sys.stderr,
            )
            raise typer.Exit(code=1)
        shutil.rmtree(sandbox_dir)

    print(f"Copying clone → {sandbox_dir}", file=sys.stderr)
    shutil.copytree(problem.repo_clone_directory, sandbox_dir, symlinks=True)

    git_repo = GitRepo(sandbox_dir, tee_git_commands=True)
    git_repo.hard_checkout(problem.fix_commit)
    git_repo.clean_working_tree()
    git_repo.revert_files(problem.buggy_rtl_commit, problem.rtl_files_changed)

    (sandbox_dir / "DEBUG_ME.md").write_text(_debug_me_brief(problem))

    print(f"\nSandbox ready: {sandbox_dir}", file=sys.stderr)
    print(f"Open {sandbox_dir / 'DEBUG_ME.md'} to see the task.", file=sys.stderr)


def _debug_me_brief(problem: Problem) -> str:
    rtl_file_lines = "\n".join(f"- `{path}`" for path in problem.rtl_files_changed)
    test_command_blocks = "\n\n".join(
        f"```bash\n{command}\n```" for command in problem.test_commands
    )
    return (
        f"# Debug me — `{problem.problem_id}`\n"
        f"\n"
        f"This is a buggy snapshot of [{problem.repo_url}]({problem.repo_url}).\n"
        f"The repo is checked out at the **fix** commit `{problem.fix_commit}`, but the\n"
        f"following RTL files have been reverted to the **buggy** commit\n"
        f"`{problem.buggy_rtl_commit}`:\n"
        f"\n"
        f"{rtl_file_lines}\n"
        f"\n"
        f"## Run the test (it currently fails)\n"
        f"\n"
        f"Test commands are project-rooted — they read RTL from `clones/{problem.owner}__{problem.repo_name}/`,\n"
        f"not from this sandbox copy. To actually run them, put that in-place clone\n"
        f"into the same buggy state via `python python/verify_problem.py --mode buggy`,\n"
        f"or edit there directly. The forthcoming Docker eval flow will remove this\n"
        f"asymmetry.\n"
        f"\n"
        f"Commands (run from the project root):\n"
        f"\n"
        f"{test_command_blocks}\n"
        f"\n"
        f"## Your task\n"
        f"\n"
        f"Read the failing test output, find the bug in the listed RTL files, and\n"
        f"edit them so the test passes. Do **not** look at the fix commit — that's\n"
        f"the ground truth and using it defeats the purpose of the benchmark.\n"
    )


def main() -> None:
    typer.run(prepare_sandbox)
