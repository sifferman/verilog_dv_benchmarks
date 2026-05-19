"""Typed record dataclasses: the loaded Problem and every output record
emitted by the CLI (JSONL to stdout, JSON files on disk)."""
from __future__ import annotations

import contextlib
import fcntl
import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Literal

from dvbench.constants import (
    CLONES_DIRECTORY,
    LOGS_DIRECTORY,
    REPO_LOCKS_DIRECTORY,
    SUCCESSFUL_RESULT_LABELS,
)


@dataclass
class Problem:
    """A benchmark problem loaded from problems/{owner}/{repo}/{sha}.json.

    A Problem is one entry in the dataset: a known bug + the repo + the
    test command that distinguishes the buggy state from the solution state."""

    problem_id: str
    repo_url: str
    owner: str
    repo_name: str
    fix_commit: str
    buggy_rtl_commit: str
    rtl_files_changed: list[str]
    test_commands: list[str]
    problem_json_path: Path

    @staticmethod
    def load_from_json(problem_json_path: Path) -> "Problem":
        problem_json_data = json.loads(problem_json_path.read_text())
        return Problem(
            problem_id=problem_json_data["problem_id"],
            repo_url=problem_json_data["repo_url"],
            owner=problem_json_data["owner"],
            repo_name=problem_json_data["repo_name"],
            fix_commit=problem_json_data["fix_commit"],
            buggy_rtl_commit=problem_json_data["buggy_rtl_commit"],
            rtl_files_changed=problem_json_data["rtl_files_changed"],
            test_commands=problem_json_data["test_commands"],
            problem_json_path=problem_json_path,
        )

    @property
    def repo_clone_directory(self) -> Path:
        return CLONES_DIRECTORY / f"{self.owner}__{self.repo_name}"

    @property
    def problem_log_directory(self) -> Path:
        return LOGS_DIRECTORY / self.problem_id

    @property
    def repo_lock_file_path(self) -> Path:
        return REPO_LOCKS_DIRECTORY / f"{self.owner}__{self.repo_name}.lock"

    @contextlib.contextmanager
    def repo_exclusive_lock(self):
        """Per-repo `fcntl.flock` — serializes parallel workers that share the
        same clone directory (e.g. multiple Problems verifying the same repo)."""
        REPO_LOCKS_DIRECTORY.mkdir(parents=True, exist_ok=True)
        lock_file_descriptor = os.open(
            str(self.repo_lock_file_path), os.O_WRONLY | os.O_CREAT, 0o644
        )
        try:
            fcntl.flock(lock_file_descriptor, fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(lock_file_descriptor, fcntl.LOCK_UN)
            os.close(lock_file_descriptor)


@dataclass(frozen=True)
class RepoViabilityReport:
    """Output record emitted by `check-url` for each discovered repo."""

    repo_url: str
    owner: str
    repo_name: str
    viable: bool
    reason: str | None
    license: str
    language: str
    hdl_pct: float
    commit_count: int
    stars: int

    def to_json_line(self) -> str:
        return json.dumps(asdict(self))


@dataclass(frozen=True)
class CandidateCommitRecord:
    """Output record emitted by `list-candidates` for each candidate commit pair."""

    fix_commit: str
    prev_commit: str
    commit_msg: str
    rtl_files: list[str]
    dv_files: list[str]
    diff_lines: int
    rtl_diff: str

    def to_json_line(self) -> str:
        return json.dumps(asdict(self))


TryCommitOutcomeKind = Literal["success", "skip", "error"]


@dataclass(frozen=True)
class TryCommitOutcome:
    """The terminal outcome of `try-commit`. `outcome` discriminates which fields
    are meaningful: success → `saved_problem_json_path`; skip → `reason` (and
    optionally `truncated_test_output`); error → `reason`."""

    repo_url: str
    fix_commit: str
    outcome: TryCommitOutcomeKind
    reason: str | None = None
    saved_problem_json_path: str | None = None
    truncated_test_output: str | None = None

    @classmethod
    def success(cls, *, repo_url: str, fix_commit: str, saved_problem_json_path: str) -> "TryCommitOutcome":
        return cls(
            repo_url=repo_url,
            fix_commit=fix_commit,
            outcome="success",
            saved_problem_json_path=saved_problem_json_path,
        )

    @classmethod
    def skip(
        cls, *, repo_url: str, fix_commit: str, reason: str,
        truncated_test_output: str | None = None,
    ) -> "TryCommitOutcome":
        return cls(
            repo_url=repo_url,
            fix_commit=fix_commit,
            outcome="skip",
            reason=reason,
            truncated_test_output=truncated_test_output,
        )

    @classmethod
    def error(cls, *, repo_url: str, fix_commit: str, reason: str) -> "TryCommitOutcome":
        return cls(
            repo_url=repo_url,
            fix_commit=fix_commit,
            outcome="error",
            reason=reason,
        )

    def to_json_line(self) -> str:
        record: dict = {
            "repo_url":   self.repo_url,
            "fix_commit": self.fix_commit,
            "outcome":    self.outcome,
        }
        if self.outcome == "success":
            record["saved"] = self.saved_problem_json_path
        else:
            record["reason"] = self.reason
            if self.truncated_test_output is not None:
                record["test_output"] = self.truncated_test_output
        return json.dumps(record)


@dataclass(frozen=True)
class SavedProblem:
    """The on-disk problem JSON written by try-commit to
    problems/{owner}/{repo}/{fix_commit}.json."""

    problem_id: str
    repo_url: str
    owner: str
    repo_name: str
    fix_commit: str
    buggy_rtl_commit: str
    fix_commit_msg: str
    description: str
    date_created: str
    rtl_dir: str
    dv_dir: str
    rtl_files_changed: list[str]
    test_commands: list[str]
    rtl_diff: str
    rtl_diff_lines: int
    source: str = "historical"

    def write_to(self, problem_json_output_path: Path) -> None:
        problem_json_output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(problem_json_output_path, "w") as problem_json_file:
            json.dump(asdict(self), problem_json_file, indent=2)


@dataclass(frozen=True)
class VerificationResult:
    """Outcome of verifying one Problem in one mode (verify | solution | buggy).
    Written to logs/{problem_id}/result.json and aggregated in the summary table."""

    problem_id: str
    mode: str
    result: str
    duration_s: float
    solution_exit_code: int | None = None
    buggy_exit_code: int | None = None
    error: str | None = None

    @property
    def is_successful(self) -> bool:
        return self.result in SUCCESSFUL_RESULT_LABELS

    def to_json_dict(self) -> dict:
        record: dict = {
            "problem_id": self.problem_id,
            "mode": self.mode,
        }
        if self.solution_exit_code is not None:
            record["solution_exit_code"] = self.solution_exit_code
        if self.buggy_exit_code is not None:
            record["buggy_exit_code"] = self.buggy_exit_code
        record["result"] = self.result
        if self.error is not None:
            record["error"] = self.error
        record["duration_s"] = self.duration_s
        return record

    def write_to(self, result_json_output_path: Path) -> None:
        result_json_output_path.parent.mkdir(parents=True, exist_ok=True)
        result_json_output_path.write_text(json.dumps(self.to_json_dict(), indent=2))
