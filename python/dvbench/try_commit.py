from __future__ import annotations

import subprocess
from datetime import date
from pathlib import Path

from dvbench.constants import (
    PROBLEMS_DIRECTORY,
    TEST_COMMAND_TIMEOUT_SECONDS,
    TRUNCATED_TEST_OUTPUT_TAIL_BYTES,
)
from dvbench.git_repo import GitRepo
from dvbench.github_api import GitHubApi
from dvbench.log_csv import LogCsv
from dvbench.records import SavedProblem, TryCommitOutcome
from dvbench.shell import run_cmd


class TryCommit:
    """Executes the try-commit state machine:
        1. checkout fix commit cleanly
        2. verify test passes at fix commit
        3. revert RTL files to buggy state
        4. verify test fails with buggy RTL
        5. save the instance JSON and update log.csv

    Each phase either returns None (proceed) or a terminal TryCommitOutcome."""

    def __init__(
        self,
        git_repo: GitRepo,
        log_csv: LogCsv,
        *,
        repo_url: str,
        fix_commit: str,
        prev_commit: str,
        rtl_dir: str,
        dv_dir: str,
        rtl_files: list[str],
        test_cmd: str,
        test_cwd: Path,
    ) -> None:
        self.git_repo = git_repo
        self.log_csv = log_csv
        self.repo_url = repo_url
        self.fix_commit = fix_commit
        self.prev_commit = prev_commit
        self.rtl_dir = rtl_dir
        self.dv_dir = dv_dir
        self.rtl_files = rtl_files
        self.test_cmd = test_cmd
        self.test_cwd = test_cwd

    def run(self) -> TryCommitOutcome:
        if (early_exit := self._checkout_fix_commit_cleanly()) is not None:
            return early_exit
        if (early_exit := self._verify_test_passes_at_fix_commit()) is not None:
            return early_exit
        if (early_exit := self._revert_rtl_files_to_buggy_state()) is not None:
            return early_exit
        if (early_exit := self._verify_test_fails_with_buggy_rtl()) is not None:
            return early_exit
        return self._save_problem_and_update_log()

    def _error(self, reason: str) -> TryCommitOutcome:
        return TryCommitOutcome.error(
            repo_url=self.repo_url,
            fix_commit=self.fix_commit,
            reason=reason,
        )

    def _skip(self, reason: str, truncated_test_output: str | None = None) -> TryCommitOutcome:
        return TryCommitOutcome.skip(
            repo_url=self.repo_url,
            fix_commit=self.fix_commit,
            reason=reason,
            truncated_test_output=truncated_test_output,
        )

    def _checkout_fix_commit_cleanly(self) -> TryCommitOutcome | None:
        try:
            self.git_repo.hard_checkout(self.fix_commit)
            self.git_repo.clean_working_tree()
        except subprocess.CalledProcessError as checkout_error:
            return self._error(checkout_error.output or str(checkout_error))
        return None

    def _verify_test_passes_at_fix_commit(self) -> TryCommitOutcome | None:
        try:
            exit_code, test_output = run_cmd(
                self.test_cmd, cwd=self.test_cwd,
                timeout=TEST_COMMAND_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            return self._skip("timeout at fix commit")
        if exit_code != 0:
            return self._skip(
                "test fails at fix commit",
                truncated_test_output=test_output[-TRUNCATED_TEST_OUTPUT_TAIL_BYTES:],
            )
        return None

    def _revert_rtl_files_to_buggy_state(self) -> TryCommitOutcome | None:
        try:
            self.git_repo.revert_files(self.prev_commit, self.rtl_files)
        except subprocess.CalledProcessError as revert_error:
            return self._error(f"revert failed: {revert_error.output or revert_error}")
        return None

    def _verify_test_fails_with_buggy_rtl(self) -> TryCommitOutcome | None:
        try:
            exit_code, _ = run_cmd(
                self.test_cmd, cwd=self.test_cwd,
                timeout=TEST_COMMAND_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            return self._skip("timeout with buggy RTL")
        if exit_code == 0:
            return self._skip("test passes with buggy RTL")
        return None

    def _save_problem_and_update_log(self) -> TryCommitOutcome:
        owner, repo_name = GitHubApi.extract_repo_owner(self.repo_url)
        rtl_diff_text = self.git_repo.unified_diff(
            self.prev_commit, self.fix_commit, self.rtl_dir
        )
        fix_commit_message = self.git_repo.commit_message(self.fix_commit)

        saved_problem = SavedProblem(
            problem_id=f"{owner}/{repo_name}/{self.fix_commit}",
            repo_url=self.repo_url,
            owner=owner,
            repo_name=repo_name,
            fix_commit=self.fix_commit,
            buggy_rtl_commit=self.prev_commit,
            fix_commit_msg=fix_commit_message,
            description=fix_commit_message,
            date_created=date.today().isoformat(),
            rtl_dir=self.rtl_dir,
            dv_dir=self.dv_dir,
            rtl_files_changed=self.rtl_files,
            test_commands=[self.test_cmd],
            rtl_diff=rtl_diff_text,
            rtl_diff_lines=GitRepo.count_diff_lines(rtl_diff_text),
        )
        problem_json_output_path = (
            PROBLEMS_DIRECTORY / owner / repo_name / f"{self.fix_commit}.json"
        )
        saved_problem.write_to(problem_json_output_path)

        self.log_csv.set(repo_url=self.repo_url, current_hash=self.fix_commit)
        self.log_csv.increment_counter(self.repo_url, "commits_used", 1)

        return TryCommitOutcome.success(
            repo_url=self.repo_url,
            fix_commit=self.fix_commit,
            saved_problem_json_path=str(problem_json_output_path),
        )
