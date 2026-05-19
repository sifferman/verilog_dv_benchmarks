"""Generic harness for verifying benchmark problems.

Reads a problem JSON from problems/{owner}/{repo}/{sha}.json, ensures the repo
clone is at the right state, executes the test command, and reports pass/fail.

Usage:
    python3 scripts/verify_problem.py --problem-id <id> [--mode {verify,solution,buggy}]
    python3 scripts/verify_problem.py --all [--workers N] [--mode ...]
"""
from __future__ import annotations

import concurrent.futures
import sys
from enum import Enum
from pathlib import Path
from typing import Iterable

import typer

from dvbench.problem_database import ProblemDatabase
from dvbench.records import Problem, VerificationResult
from dvbench.verifier import Verifier


class VerifierMode(str, Enum):
    VERIFY = "verify"
    SOLUTION = "solution"
    BUGGY = "buggy"


SUMMARY_TABLE_PROBLEM_COLUMN_WIDTH = 70
SUMMARY_TABLE_MODE_COLUMN_WIDTH = 10
SUMMARY_TABLE_DURATION_COLUMN_WIDTH = 10
SUMMARY_TABLE_SEPARATOR_WIDTH = 115


def _verify_one_problem(problem: Problem, mode: str) -> VerificationResult:
    return Verifier(problem, mode).run()


def verify_problems_possibly_in_parallel(
    problem_json_paths: Iterable[Path], mode: str, worker_count: int
) -> list[VerificationResult]:
    problems = [Problem.load_from_json(p) for p in problem_json_paths]
    if worker_count <= 1:
        return [_verify_one_problem(problem, mode) for problem in problems]
    with concurrent.futures.ProcessPoolExecutor(max_workers=worker_count) as worker_pool:
        submitted_futures = {
            worker_pool.submit(_verify_one_problem, problem, mode): problem
            for problem in problems
        }
        return [
            completed_future.result()
            for completed_future in concurrent.futures.as_completed(submitted_futures)
        ]


def render_results_summary_table(results: list[VerificationResult]) -> str:
    sorted_results = sorted(results, key=lambda r: r.problem_id)
    header_line = (
        f"{'PROBLEM':<{SUMMARY_TABLE_PROBLEM_COLUMN_WIDTH}s} "
        f"{'MODE':<{SUMMARY_TABLE_MODE_COLUMN_WIDTH}s} "
        f"{'DURATION':>{SUMMARY_TABLE_DURATION_COLUMN_WIDTH}s}  RESULT"
    )
    separator = "-" * SUMMARY_TABLE_SEPARATOR_WIDTH
    body_lines = [_format_summary_row(r) for r in sorted_results]

    counts_by_result_label: dict[str, int] = {}
    for r in sorted_results:
        counts_by_result_label[r.result] = counts_by_result_label.get(r.result, 0) + 1
    counts_summary = ", ".join(
        f"{count} {label}" for label, count in sorted(counts_by_result_label.items())
    )
    summary_line = f"Summary ({len(sorted_results)} problems): {counts_summary}"

    return "\n".join(["", header_line, separator, *body_lines, separator, summary_line])


def _format_summary_row(result: VerificationResult) -> str:
    duration_display = f"{result.duration_s:.1f}s"
    return (
        f"{result.problem_id:<{SUMMARY_TABLE_PROBLEM_COLUMN_WIDTH}s} "
        f"{result.mode:<{SUMMARY_TABLE_MODE_COLUMN_WIDTH}s} "
        f"{duration_display:>{SUMMARY_TABLE_DURATION_COLUMN_WIDTH}s}  {result.result}"
    )


def exit_code_from_results(results: list[VerificationResult]) -> int:
    return 1 if any(not r.is_successful for r in results) else 0


def verify_problem(
    problem_id: str | None = typer.Option(
        None, "--problem-id", help="Problem ID like {owner}/{repo}/{sha}, or just {sha}"
    ),
    run_all: bool = typer.Option(False, "--all", help="Verify every JSON in problems/"),
    mode: VerifierMode = typer.Option(VerifierMode.VERIFY, "--mode"),
    workers: int = typer.Option(1, "--workers"),
) -> None:
    """Generic harness for verifying benchmark problems."""
    if (problem_id is None) == (not run_all):
        raise typer.BadParameter("Specify exactly one of --problem-id or --all.")

    problem_database = ProblemDatabase()
    if run_all:
        problem_json_paths = problem_database.list_all_paths()
    else:
        assert problem_id is not None
        problem_json_paths = [problem_database.resolve_by_id(problem_id)]

    results = verify_problems_possibly_in_parallel(
        problem_json_paths, mode.value, workers
    )
    print(render_results_summary_table(results))
    raise typer.Exit(code=exit_code_from_results(results))


def main() -> int:
    typer.run(verify_problem)
    return 0


if __name__ == "__main__":
    sys.exit(main())
