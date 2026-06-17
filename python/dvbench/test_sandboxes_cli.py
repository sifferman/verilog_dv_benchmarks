"""Smoke-test sandbox creation and execution across every benchmark problem.

For each problem JSON, materialize a sandbox into a tmpdir, run the bundled
`verify` wrapper, and check the exit code:

  - non-zero → sandbox correctly reflects the buggy state (the test catches it).
  - exit 0  → either the buggy RTL didn't trigger the test (bad benchmark) or
              prepare_sandbox accidentally restored the fix (bad harness).

Also flags problems where the sandbox build itself failed (missing sibling
clone, scrub crash, etc.). Mirrors the shape of `verify_problem_cli.py`.
"""
from __future__ import annotations

import concurrent.futures
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Iterable

import typer

from dvbench.problem_database import ProblemDatabase
from dvbench.prepare_sandbox_cli import prepare_sandbox
from dvbench.records import Problem


SUMMARY_TABLE_PROBLEM_COLUMN_WIDTH = 70
SUMMARY_TABLE_DURATION_COLUMN_WIDTH = 10
SUMMARY_TABLE_SEPARATOR_WIDTH = 110

RESULT_SANDBOX_VERIFIED = "sandbox_verified"
RESULT_SANDBOX_VERIFY_DID_NOT_FAIL = "sandbox_verify_did_not_fail"
RESULT_SANDBOX_BUILD_FAILED = "sandbox_build_failed"
RESULT_SANDBOX_ERROR = "sandbox_error"

SUCCESSFUL_SANDBOX_RESULT_LABELS = {RESULT_SANDBOX_VERIFIED}

VERIFY_WRAPPER_TIMEOUT_SECONDS = 600


@dataclass(frozen=True)
class SandboxTestResult:
    problem_id: str
    result: str
    duration_s: float
    verify_exit_code: int | None = None
    error_message: str | None = None

    @property
    def is_successful(self) -> bool:
        return self.result in SUCCESSFUL_SANDBOX_RESULT_LABELS


def _test_one_sandbox(problem_json_path: Path) -> SandboxTestResult:
    started_at_monotonic = time.monotonic()
    problem = Problem.load_from_json(problem_json_path)

    sandbox_root = Path(tempfile.mkdtemp(prefix="dvbench_sandbox_test_"))
    sandbox_dir = sandbox_root / "sandbox"
    try:
        try:
            prepare_sandbox(
                problem_id=problem.problem_id,
                output_dir=sandbox_dir,
                overwrite=False,
                no_scrub=False,
            )
        except (typer.Exit, SystemExit) as caught_exit:
            return SandboxTestResult(
                problem_id=problem.problem_id,
                result=RESULT_SANDBOX_BUILD_FAILED,
                duration_s=round(time.monotonic() - started_at_monotonic, 2),
                error_message=f"prepare_sandbox raised Exit({caught_exit})",
            )
        except Exception as caught_exception:
            return SandboxTestResult(
                problem_id=problem.problem_id,
                result=RESULT_SANDBOX_ERROR,
                duration_s=round(time.monotonic() - started_at_monotonic, 2),
                error_message=repr(caught_exception),
            )

        completed_process = subprocess.run(
            ["bash", str(sandbox_dir / "verify")],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=VERIFY_WRAPPER_TIMEOUT_SECONDS,
        )

        if completed_process.returncode == 0:
            return SandboxTestResult(
                problem_id=problem.problem_id,
                result=RESULT_SANDBOX_VERIFY_DID_NOT_FAIL,
                duration_s=round(time.monotonic() - started_at_monotonic, 2),
                verify_exit_code=0,
            )
        return SandboxTestResult(
            problem_id=problem.problem_id,
            result=RESULT_SANDBOX_VERIFIED,
            duration_s=round(time.monotonic() - started_at_monotonic, 2),
            verify_exit_code=completed_process.returncode,
        )
    finally:
        shutil.rmtree(sandbox_root, ignore_errors=True)


def test_sandboxes_possibly_in_parallel(
    problem_json_paths: Iterable[Path], worker_count: int
) -> list[SandboxTestResult]:
    problem_json_paths = list(problem_json_paths)
    if worker_count <= 1:
        return [_test_one_sandbox(path) for path in problem_json_paths]
    with concurrent.futures.ProcessPoolExecutor(max_workers=worker_count) as worker_pool:
        submitted_futures = [
            worker_pool.submit(_test_one_sandbox, path) for path in problem_json_paths
        ]
        return [future.result() for future in concurrent.futures.as_completed(submitted_futures)]


def render_results_summary_table(results: list[SandboxTestResult]) -> str:
    sorted_results = sorted(results, key=lambda r: r.problem_id)
    header_line = (
        f"{'PROBLEM':<{SUMMARY_TABLE_PROBLEM_COLUMN_WIDTH}s} "
        f"{'DURATION':>{SUMMARY_TABLE_DURATION_COLUMN_WIDTH}s}  RESULT"
    )
    separator = "-" * SUMMARY_TABLE_SEPARATOR_WIDTH
    body_lines = [
        f"{r.problem_id:<{SUMMARY_TABLE_PROBLEM_COLUMN_WIDTH}s} "
        f"{r.duration_s:>{SUMMARY_TABLE_DURATION_COLUMN_WIDTH-1}.1f}s  {r.result}"
        for r in sorted_results
    ]

    counts_by_result_label: dict[str, int] = {}
    for r in sorted_results:
        counts_by_result_label[r.result] = counts_by_result_label.get(r.result, 0) + 1
    counts_summary = ", ".join(
        f"{count} {label}" for label, count in sorted(counts_by_result_label.items())
    )
    summary_line = f"Summary ({len(sorted_results)} problems): {counts_summary}"

    return "\n".join(["", header_line, separator, *body_lines, separator, summary_line])


def exit_code_from_results(results: list[SandboxTestResult]) -> int:
    return 1 if any(not r.is_successful for r in results) else 0


def test_sandboxes(
    problem_id: str | None = typer.Option(
        None, "--problem-id", help="Problem ID like {owner}/{repo}/{sha}, or just {sha}"
    ),
    run_all: bool = typer.Option(False, "--all", help="Test every JSON in problems/"),
    workers: int = typer.Option(1, "--workers"),
) -> None:
    """Build a sandbox for each problem, run its verify wrapper, and check
    that the buggy RTL state is correctly detected (exit non-zero)."""
    if (problem_id is None) == (not run_all):
        raise typer.BadParameter("Specify exactly one of --problem-id or --all.")

    problem_database = ProblemDatabase()
    if run_all:
        problem_json_paths = problem_database.list_all_paths()
    else:
        assert problem_id is not None
        problem_json_paths = [problem_database.resolve_by_id(problem_id)]

    results = test_sandboxes_possibly_in_parallel(problem_json_paths, workers)
    print(render_results_summary_table(results))
    raise typer.Exit(code=exit_code_from_results(results))


def main() -> int:
    typer.run(test_sandboxes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
