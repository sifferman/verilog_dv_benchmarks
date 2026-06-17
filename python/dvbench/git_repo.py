from __future__ import annotations

import subprocess
from pathlib import Path

from dvbench.shell import run_cmd


class GitRepo:
    """Local git repo wrapper. Owns a clone directory and exposes the git
    operations the mining + verification flows need.

    `tee_git_commands=True` mirrors every git subprocess's invocation line and
    output to the console as it arrives — used by the `verify_problem` harness
    so the user sees progress on long operations. With `tee_git_commands=False`
    (used by `TryCommit`), the output is only captured and returned."""

    def __init__(self, clone_directory: Path, *, tee_git_commands: bool = False) -> None:
        self.clone_directory = clone_directory
        self.tee_git_commands = tee_git_commands

    def _git(
        self,
        git_arguments: list[str],
        *,
        raise_on_failure: bool = True,
        cwd: Path | None = None,
    ) -> str:
        """Run `git <args>` and return its captured stdout (trimmed). When
        `tee_git_commands=True` is set on this instance, the invocation and its
        output are also tee'd to the console as they arrive. Raises
        `subprocess.CalledProcessError` on non-zero exit unless
        `raise_on_failure=False`."""
        _, captured_output = run_cmd(
            ["git"] + git_arguments,
            cwd=cwd or self.clone_directory,
            tee_to_console=self.tee_git_commands,
            raise_on_failure=raise_on_failure,
        )
        return captured_output.strip()

    # ---- mutating operations -------------------------------------------------

    def clone_if_missing(self, repo_url: str) -> None:
        if self.clone_directory.exists():
            return
        self.clone_directory.parent.mkdir(parents=True, exist_ok=True)
        self._git(
            ["clone", "--filter=blob:none", repo_url, str(self.clone_directory)],
            cwd=self.clone_directory.parent,
        )

    def fetch(self, ref: str, *, raise_on_failure: bool = True) -> None:
        self._git(
            ["fetch", "--filter=blob:none", "origin", ref],
            raise_on_failure=raise_on_failure,
        )

    def hard_checkout(self, ref: str) -> None:
        self._git(["checkout", "-f", ref])

    def clean_working_tree(self) -> None:
        self._git(["clean", "-fd"])

    def revert_files(self, ref: str, file_paths: list[str]) -> None:
        self._git(["checkout", ref, "--"] + file_paths)

    def init_submodule(self, submodule_path: str) -> None:
        """Populate one submodule's working tree (e.g. `corev_apu/riscv-dbg`).
        Used by `prepare_sandbox` to materialize submodule files before
        stripping `.git` from the sandbox copy."""
        self._git(["submodule", "update", "--init", "--recursive", submodule_path])

    def init_all_submodules_recursively(self) -> None:
        """Populate every submodule (including nested) of the working tree.
        Used by `prepare_sandbox` when the runner references submodule paths
        without explicitly listing them — cheap insurance against a missing
        submodule. The runner's own `dvbench_init_submodule` helper
        short-circuits when files are already present."""
        self._git(["submodule", "update", "--init", "--recursive"])

    # ---- read-only queries ---------------------------------------------------

    def default_branch_name(self) -> str:
        try:
            current_branch = self._git(["symbolic-ref", "--short", "HEAD"])
            if current_branch:
                return current_branch
        except subprocess.CalledProcessError:
            pass
        remote_branches_listing = self._git(["branch", "-r"], raise_on_failure=False)
        for branch_line in remote_branches_listing.splitlines():
            branch_name = branch_line.strip().removeprefix("origin/")
            if branch_name in ("main", "master"):
                return branch_name
        return "main"

    def list_changed_files(self, prev_ref: str, curr_ref: str) -> list[str]:
        return self._git(["diff", "--name-only", prev_ref, curr_ref]).splitlines()

    def unified_diff(self, prev_ref: str, curr_ref: str, path_filter: str) -> str:
        return self._git(["diff", prev_ref, curr_ref, "--", path_filter])

    def commit_message(self, sha: str) -> str:
        return self._git(["log", "-1", "--format=%B", sha])

    def recent_commit_shas_and_subjects(
        self, branch: str, limit: int
    ) -> list[tuple[str, str]]:
        log_output_lines = self._git(
            ["log", "--format=%H\t%s", f"-{limit}", branch]
        ).splitlines()
        return [
            (line.split("\t", 1)[0], line.split("\t", 1)[1] if "\t" in line else "")
            for line in log_output_lines
            if line.strip()
        ]

    # ---- static utilities on git output --------------------------------------

    @staticmethod
    def count_diff_lines(diff_text: str) -> int:
        """Count added + removed lines in a unified diff (excluding file headers)."""
        added = sum(
            1 for line in diff_text.splitlines()
            if line.startswith("+") and not line.startswith("+++")
        )
        removed = sum(
            1 for line in diff_text.splitlines()
            if line.startswith("-") and not line.startswith("---")
        )
        return added + removed

    @staticmethod
    def paths_under_directory(paths: list[str], directory: str) -> list[str]:
        """Filter `paths` to those equal to or descended from `directory`."""
        return [p for p in paths if p == directory or p.startswith(directory + "/")]
