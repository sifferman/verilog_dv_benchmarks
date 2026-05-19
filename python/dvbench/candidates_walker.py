from __future__ import annotations

from typing import Iterable

from dvbench.constants import COVERAGE_ONLY_COMMIT_PATTERN
from dvbench.git_repo import GitRepo
from dvbench.log_csv import LogCsv
from dvbench.records import CandidateCommitRecord


class CandidatesWalker:
    """Walks recent commits in a clone, yielding a CandidateCommitRecord for
    every (prev_commit -> fix_commit) pair whose RTL+DV changes match the
    candidate criteria. Updates `problems/log.csv` in real time as the walk
    progresses, so a `tail -f` observer can watch `commits_walked` count up."""

    def __init__(
        self,
        git_repo: GitRepo,
        log_csv: LogCsv,
        *,
        repo_url: str,
        rtl_dir: str,
        dv_dir: str,
        max_commits_to_walk: int,
        max_rtl_diff_lines: int,
    ) -> None:
        self.git_repo = git_repo
        self.log_csv = log_csv
        self.repo_url = repo_url
        self.rtl_dir = rtl_dir.rstrip("/")
        self.dv_dir = dv_dir.rstrip("/")
        self.max_commits_to_walk = max_commits_to_walk
        self.max_rtl_diff_lines = max_rtl_diff_lines

    def iter_candidate_records(self) -> Iterable[CandidateCommitRecord]:
        default_branch = self.git_repo.default_branch_name()
        commits = self.git_repo.recent_commit_shas_and_subjects(
            default_branch, self.max_commits_to_walk
        )
        self.log_csv.set(
            repo_url=self.repo_url,
            commits_total=str(len(commits)),
            commits_walked="0",
        )

        candidate_commits_walked = 0
        for commit_pair_index in range(len(commits) - 1):
            fix_commit_sha, fix_commit_subject = commits[commit_pair_index]
            prev_commit_sha, _ = commits[commit_pair_index + 1]

            if COVERAGE_ONLY_COMMIT_PATTERN.search(fix_commit_subject):
                continue

            files_changed_in_pair = self.git_repo.list_changed_files(
                prev_commit_sha, fix_commit_sha
            )
            rtl_files_changed = GitRepo.paths_under_directory(files_changed_in_pair, self.rtl_dir)
            dv_files_changed = GitRepo.paths_under_directory(files_changed_in_pair, self.dv_dir)

            candidate_commits_walked += 1
            self.log_csv.set(
                repo_url=self.repo_url,
                commits_walked=str(candidate_commits_walked),
            )

            if not rtl_files_changed or not dv_files_changed:
                continue

            rtl_diff_text = self.git_repo.unified_diff(
                prev_commit_sha, fix_commit_sha, self.rtl_dir
            )
            total_rtl_diff_lines = GitRepo.count_diff_lines(rtl_diff_text)
            if total_rtl_diff_lines > self.max_rtl_diff_lines:
                continue

            yield CandidateCommitRecord(
                fix_commit=fix_commit_sha,
                prev_commit=prev_commit_sha,
                commit_msg=self.git_repo.commit_message(fix_commit_sha),
                rtl_files=rtl_files_changed,
                dv_files=dv_files_changed,
                diff_lines=total_rtl_diff_lines,
                rtl_diff=rtl_diff_text,
            )
