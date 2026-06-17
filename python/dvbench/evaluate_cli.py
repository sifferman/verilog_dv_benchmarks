"""Apply a model's predicted patches against fresh sandboxes and score the results.

Input is a JSONL file — one prediction per line:

    {"problem_id": "...", "model_name": "...", "model_patch": "diff ...",
     "usage": {...optional token / wall-clock metrics from the agent...}}

For each prediction:
  1. Build a fresh sandbox via `dvbench.prepare_sandbox_cli.prepare_sandbox`.
  2. Apply `model_patch` to the sandbox's `clones/<owner>/<repo>/` with
     `git apply` (works without a .git tree).
  3. Reject any patch that touches files outside `rtl_files_changed`.
  4. Run the sandbox's `verify` wrapper.
  5. Mark as `resolved` iff verify exits 0, `unresolved` if non-zero, or
     `error:<reason>` if the patch failed to apply / touched forbidden files.

Output is one aggregated scores JSON at `--out`.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

import typer

from dvbench.prepare_sandbox_cli import prepare_sandbox
from dvbench.problem_database import ProblemDatabase
from dvbench.records import Problem


RESULT_RESOLVED = "resolved"
RESULT_UNRESOLVED = "unresolved"
RESULT_ERROR_PATCH_DID_NOT_APPLY = "error_patch_did_not_apply"
RESULT_ERROR_PATCH_TOUCHED_FORBIDDEN_FILES = "error_patch_touched_forbidden_files"
RESULT_ERROR_SANDBOX_BUILD_FAILED = "error_sandbox_build_failed"
RESULT_ERROR_UNCAUGHT = "error_uncaught"

# Files touched by a unified diff. Catches `diff --git a/<path> b/<path>` and
# the plain `--- a/<path>` / `+++ b/<path>` headers used when there's no diff
# --git line.
DIFF_GIT_HEADER_PATTERN = re.compile(r'^diff --git a/(\S+) b/(\S+)$', re.MULTILINE)
DIFF_FILE_PREFIX_PATTERN = re.compile(r'^\+\+\+ b/(\S+)$', re.MULTILINE)

VERIFY_WRAPPER_TIMEOUT_SECONDS = 600


@dataclass(frozen=True)
class Prediction:
    """One line of a predictions JSONL."""
    problem_id: str
    model_name: str
    model_patch: str
    usage: dict | None = None

    @classmethod
    def from_jsonl_line(cls, raw_line: str) -> "Prediction":
        data = json.loads(raw_line)
        return cls(
            problem_id=data["problem_id"],
            model_name=data["model_name"],
            model_patch=data["model_patch"],
            usage=data.get("usage"),
        )


@dataclass(frozen=True)
class EvaluationOutcome:
    """One scored prediction."""
    problem_id: str
    result: str
    duration_s: float
    verify_exit_code: int | None = None
    error_detail: str | None = None
    usage: dict | None = None

    @property
    def is_resolved(self) -> bool:
        return self.result == RESULT_RESOLVED

    def to_json_dict(self) -> dict:
        record: dict = {
            "problem_id": self.problem_id,
            "result": self.result,
            "duration_s": self.duration_s,
        }
        if self.verify_exit_code is not None:
            record["verify_exit_code"] = self.verify_exit_code
        if self.error_detail is not None:
            record["error_detail"] = self.error_detail
        if self.usage is not None:
            record["usage"] = self.usage
        return record


def _clean_stale_global_build_dirs() -> None:
    """Wipe `/tmp/vbuild_*` directories left by previous runner invocations.
    The bundled per-problem runners hardcode that prefix and don't `rm -rf`
    first, so a stale obj_dir from a now-gone sandbox can cause verilator
    incremental builds to fail with `No rule to make target ...`."""
    for stale_build_directory in Path("/tmp").glob("vbuild_*"):
        if stale_build_directory.is_dir():
            shutil.rmtree(stale_build_directory, ignore_errors=True)


def _files_touched_by_patch(unified_diff: str) -> list[str]:
    touched: list[str] = []
    for diff_git_match in DIFF_GIT_HEADER_PATTERN.finditer(unified_diff):
        # `diff --git a/<a> b/<b>` — record the b-side path (the post-image).
        touched.append(diff_git_match.group(2))
    if not touched:
        # Diff lacks `diff --git` headers (e.g. produced by plain `diff -u`).
        for plus_plus_match in DIFF_FILE_PREFIX_PATTERN.finditer(unified_diff):
            touched.append(plus_plus_match.group(1))
    return touched


def _evaluate_one_prediction(
    prediction: Prediction, problem: Problem
) -> EvaluationOutcome:
    started_at_monotonic = time.monotonic()

    touched_files = _files_touched_by_patch(prediction.model_patch)
    forbidden_touched = [
        path for path in touched_files
        if path not in problem.rtl_files_changed
    ]
    if forbidden_touched:
        return EvaluationOutcome(
            problem_id=prediction.problem_id,
            result=RESULT_ERROR_PATCH_TOUCHED_FORBIDDEN_FILES,
            duration_s=round(time.monotonic() - started_at_monotonic, 2),
            error_detail=f"patch touches non-allowlisted files: {forbidden_touched}",
            usage=prediction.usage,
        )

    sandbox_root = Path(tempfile.mkdtemp(prefix="dvbench_evaluate_"))
    sandbox_dir = sandbox_root / "sandbox"
    try:
        # Most of our runners stash verilator build artifacts at a globally-
        # shared `/tmp/vbuild_<problem_short>/` directory. If a prior
        # invocation (in some other now-deleted sandbox) populated that
        # directory, verilator's incremental build sees stale path
        # references and fails. Clear them out before each evaluation.
        _clean_stale_global_build_dirs()

        try:
            prepare_sandbox(
                problem_id=problem.problem_id,
                output_dir=sandbox_dir,
                overwrite=False,
                no_scrub=False,
            )
        except Exception as caught_exception:
            return EvaluationOutcome(
                problem_id=prediction.problem_id,
                result=RESULT_ERROR_SANDBOX_BUILD_FAILED,
                duration_s=round(time.monotonic() - started_at_monotonic, 2),
                error_detail=repr(caught_exception),
                usage=prediction.usage,
            )

        # `git apply` requires the diff to end with a newline. Many of our
        # stored `rtl_diff` values (from `git diff` of a single-hunk fix) don't,
        # so normalize before piping in.
        normalized_patch = prediction.model_patch.rstrip("\n") + "\n"

        repo_in_sandbox = sandbox_dir / "clones" / problem.owner / problem.repo_name
        # `--ignore-whitespace` makes the apply CRLF/LF-tolerant; some
        # upstream files (e.g. pulp-platform/hwpe-ctrl) keep CRLF endings
        # but `git diff` always emits LF in the patch context.
        patch_application = subprocess.run(
            ["git", "apply", "-p1", "--ignore-whitespace", "-"],
            input=normalized_patch,
            cwd=repo_in_sandbox,
            text=True,
            capture_output=True,
        )
        if patch_application.returncode != 0:
            return EvaluationOutcome(
                problem_id=prediction.problem_id,
                result=RESULT_ERROR_PATCH_DID_NOT_APPLY,
                duration_s=round(time.monotonic() - started_at_monotonic, 2),
                error_detail=patch_application.stderr.strip()[:500],
                usage=prediction.usage,
            )

        verify_run = subprocess.run(
            ["bash", str(sandbox_dir / "verify")],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=VERIFY_WRAPPER_TIMEOUT_SECONDS,
        )
        return EvaluationOutcome(
            problem_id=prediction.problem_id,
            result=RESULT_RESOLVED if verify_run.returncode == 0 else RESULT_UNRESOLVED,
            duration_s=round(time.monotonic() - started_at_monotonic, 2),
            verify_exit_code=verify_run.returncode,
            usage=prediction.usage,
        )
    except Exception as caught_exception:
        return EvaluationOutcome(
            problem_id=prediction.problem_id,
            result=RESULT_ERROR_UNCAUGHT,
            duration_s=round(time.monotonic() - started_at_monotonic, 2),
            error_detail=repr(caught_exception),
            usage=prediction.usage,
        )
    finally:
        shutil.rmtree(sandbox_root, ignore_errors=True)


def evaluate_predictions(predictions: Iterable[Prediction]) -> list[EvaluationOutcome]:
    problem_database = ProblemDatabase()
    outcomes: list[EvaluationOutcome] = []
    for prediction in predictions:
        problem = Problem.load_from_json(
            problem_database.resolve_by_id(prediction.problem_id)
        )
        outcome = _evaluate_one_prediction(prediction, problem)
        print(
            f"  {prediction.problem_id}: {outcome.result} ({outcome.duration_s:.1f}s)",
            file=sys.stderr,
        )
        outcomes.append(outcome)
    return outcomes


def render_summary_table(outcomes: list[EvaluationOutcome], model_name: str) -> str:
    sorted_outcomes = sorted(outcomes, key=lambda o: o.problem_id)
    counts_by_result_label: dict[str, int] = {}
    for outcome in sorted_outcomes:
        counts_by_result_label[outcome.result] = (
            counts_by_result_label.get(outcome.result, 0) + 1
        )
    counts_summary = ", ".join(
        f"{count} {label}" for label, count in sorted(counts_by_result_label.items())
    )
    body_lines = [
        f"  {o.problem_id:<70s}  {o.duration_s:>6.1f}s  {o.result}"
        for o in sorted_outcomes
    ]
    return "\n".join([
        f"Model: {model_name}",
        f"Summary ({len(sorted_outcomes)} predictions): {counts_summary}",
        "",
        *body_lines,
    ])


def write_scores_json(
    outcomes: list[EvaluationOutcome], model_name: str, run_id: str,
    scores_json_output_path: Path,
) -> None:
    aggregated_usage = _aggregate_usage_metrics([o.usage for o in outcomes if o.usage])
    scores_json_output_path.parent.mkdir(parents=True, exist_ok=True)
    scores_json_output_path.write_text(json.dumps({
        "model_name": model_name,
        "run_id": run_id,
        "total": len(outcomes),
        "resolved": sum(1 for o in outcomes if o.is_resolved),
        "result_counts": _result_counts(outcomes),
        "aggregated_usage": aggregated_usage,
        "by_problem": [o.to_json_dict() for o in outcomes],
    }, indent=2))


def _result_counts(outcomes: list[EvaluationOutcome]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for outcome in outcomes:
        counts[outcome.result] = counts.get(outcome.result, 0) + 1
    return dict(sorted(counts.items()))


def _aggregate_usage_metrics(per_problem_usage: list[dict]) -> dict:
    """Sum integer-valued metrics across problems; pass non-int values through
    only if they're equal across all problems (e.g. a model_id string)."""
    if not per_problem_usage:
        return {}
    summed: dict = {}
    for one_problem_usage in per_problem_usage:
        for metric_name, metric_value in one_problem_usage.items():
            if isinstance(metric_value, (int, float)):
                summed[metric_name] = summed.get(metric_name, 0) + metric_value
    return summed


def evaluate(
    predictions: Path = typer.Option(
        ..., "--predictions",
        help="Path to a JSONL file: one {problem_id, model_name, model_patch, ...} per line.",
    ),
    out: Path = typer.Option(
        ..., "--out",
        help="Where to write the scores JSON.",
    ),
) -> None:
    """Score a predictions JSONL by applying each patch in a fresh sandbox
    and running its `verify` wrapper. Reports resolved/unresolved/error per
    problem and aggregates usage metrics across the run."""
    raw_lines = [
        line for line in predictions.read_text().splitlines() if line.strip()
    ]
    parsed_predictions = [Prediction.from_jsonl_line(line) for line in raw_lines]
    if not parsed_predictions:
        raise typer.BadParameter(f"No predictions found in {predictions}")

    # Allow heterogeneous model names in one file but warn if mixed — the
    # scores JSON labels the run with the most common one.
    model_names_seen = {p.model_name for p in parsed_predictions}
    primary_model_name = max(
        model_names_seen,
        key=lambda name: sum(1 for p in parsed_predictions if p.model_name == name),
    )
    if len(model_names_seen) > 1:
        print(
            f"WARNING: predictions file mixes {len(model_names_seen)} model names;"
            f" scores will be labeled '{primary_model_name}'.",
            file=sys.stderr,
        )

    run_id = time.strftime("%Y-%m-%dT%H-%M-%S")
    print(
        f"Evaluating {len(parsed_predictions)} predictions ({primary_model_name})…",
        file=sys.stderr,
    )
    outcomes = evaluate_predictions(parsed_predictions)
    print(render_summary_table(outcomes, primary_model_name))
    write_scores_json(outcomes, primary_model_name, run_id, out)
    print(f"Scores written to {out}", file=sys.stderr)
    if any(not o.is_resolved for o in outcomes):
        raise typer.Exit(code=1)


def main() -> int:
    typer.run(evaluate)
    return 0


if __name__ == "__main__":
    sys.exit(main())
