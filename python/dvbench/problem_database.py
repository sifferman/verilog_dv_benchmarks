"""On-disk database of benchmark problems under `problems/`.

A `Problem` lives at `problems/{owner}/{repo}/{sha}.json`. `ProblemDatabase`
is the lookup layer over that directory — by full ID, or by trailing SHA
alone, or "all problems in the dataset"."""
from __future__ import annotations

from pathlib import Path

from dvbench.constants import PROBLEMS_DIRECTORY


class ProblemDatabase:
    """Filesystem-backed problem catalog rooted at `problems/`."""

    def __init__(self, problems_directory: Path = PROBLEMS_DIRECTORY) -> None:
        self.problems_directory = problems_directory

    def resolve_by_id(self, problem_id: str) -> Path:
        """Accepts either a full `{owner}/{repo}/{sha}` ID (direct path lookup)
        or just `{sha}` (globs across `problems/` for the unique match)."""
        direct_path = self.problems_directory / f"{problem_id}.json"
        if direct_path.exists():
            return direct_path
        matching_json_paths = sorted(
            self.problems_directory.glob(f"**/{problem_id}.json")
        )
        if not matching_json_paths:
            raise SystemExit(f"No problem JSON found for {problem_id}")
        if len(matching_json_paths) > 1:
            raise SystemExit(
                f"Ambiguous problem ID {problem_id}: {matching_json_paths}"
            )
        return matching_json_paths[0]

    def list_all_paths(self) -> list[Path]:
        return sorted(self.problems_directory.glob("**/*.json"))
