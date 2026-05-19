from __future__ import annotations

import time

from dvbench.constants import (
    MODE_BUGGY,
    MODE_SOLUTION,
    MODE_VERIFY,
    PROJECT_ROOT,
    RESULT_BUGGY_DID_NOT_FAIL,
    RESULT_BUGGY_FAILED,
    RESULT_ERROR,
    RESULT_SOLUTION_DID_NOT_PASS,
    RESULT_SOLUTION_PASSED,
    RESULT_VERIFIED,
)
from dvbench.git_repo import GitRepo
from dvbench.records import Problem, VerificationResult
from dvbench.shell import run_cmd


class Verifier:
    """Verifies one Problem in one mode (verify | solution | buggy):
        - acquire per-repo exclusive lock so parallel workers don't fight
        - clone the repo if missing
        - checkout the fix commit, optionally revert RTL files to buggy state,
          execute test commands
        - capture stdout/stderr to logs/{problem_id}/{solution,buggy}.log
        - write logs/{problem_id}/result.json
        - return a typed VerificationResult"""

    def __init__(self, problem: Problem, mode: str) -> None:
        self.problem = problem
        self.mode = mode
        self.git_repo = GitRepo(problem.repo_clone_directory, tee_git_commands=True)

    def run(self) -> VerificationResult:
        started_at_monotonic = time.monotonic()
        solution_exit_code: int | None = None
        buggy_exit_code: int | None = None
        result_label: str | None = None
        error_message: str | None = None

        try:
            with self.problem.repo_exclusive_lock():
                self.git_repo.clone_if_missing(self.problem.repo_url)

                if self.mode in (MODE_SOLUTION, MODE_VERIFY):
                    self._reset_clone_to_fix_commit()
                    solution_exit_code = self._execute_test_commands_to_log("solution.log")
                    if self.mode == MODE_SOLUTION:
                        result_label = (
                            RESULT_SOLUTION_PASSED if solution_exit_code == 0
                            else RESULT_SOLUTION_DID_NOT_PASS
                        )

                if self.mode in (MODE_BUGGY, MODE_VERIFY):
                    self._reset_clone_to_fix_commit()
                    self.git_repo.revert_files(
                        self.problem.buggy_rtl_commit, self.problem.rtl_files_changed
                    )
                    buggy_exit_code = self._execute_test_commands_to_log("buggy.log")
                    if self.mode == MODE_BUGGY:
                        result_label = (
                            RESULT_BUGGY_FAILED if buggy_exit_code != 0
                            else RESULT_BUGGY_DID_NOT_FAIL
                        )

                if self.mode == MODE_VERIFY:
                    result_label = self._classify_verify_result(
                        solution_exit_code, buggy_exit_code
                    )
        except Exception as caught_exception:
            result_label = RESULT_ERROR
            error_message = repr(caught_exception)

        verification_duration_seconds = round(time.monotonic() - started_at_monotonic, 2)

        result = VerificationResult(
            problem_id=self.problem.problem_id,
            mode=self.mode,
            result=result_label or RESULT_ERROR,
            duration_s=verification_duration_seconds,
            solution_exit_code=solution_exit_code,
            buggy_exit_code=buggy_exit_code,
            error=error_message,
        )
        result.write_to(self.problem.problem_log_directory / "result.json")
        return result

    def _reset_clone_to_fix_commit(self) -> None:
        self.git_repo.fetch(self.problem.fix_commit, raise_on_failure=False)
        self.git_repo.hard_checkout(self.problem.fix_commit)

    def _execute_test_commands_to_log(self, log_file_name: str) -> int:
        self.problem.problem_log_directory.mkdir(parents=True, exist_ok=True)
        log_file_path = self.problem.problem_log_directory / log_file_name
        with log_file_path.open("w") as log_file:
            for test_command in self.problem.test_commands:
                exit_code, _ = run_cmd(
                    test_command,
                    cwd=PROJECT_ROOT,
                    tee_to_console=True,
                    log_file=log_file,
                    raise_on_failure=False,
                )
                if exit_code != 0:
                    return exit_code
        return 0

    @staticmethod
    def _classify_verify_result(
        solution_exit_code: int | None, buggy_exit_code: int | None
    ) -> str:
        solution_passed = solution_exit_code == 0
        buggy_failed_as_expected = buggy_exit_code != 0
        if solution_passed and buggy_failed_as_expected:
            return RESULT_VERIFIED
        if not solution_passed:
            return RESULT_SOLUTION_DID_NOT_PASS
        return RESULT_BUGGY_DID_NOT_FAIL
