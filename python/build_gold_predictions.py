#!/usr/bin/env python3
"""Emit a predictions JSONL where each line is a problem's gold rtl_diff.

Phase-1 sanity check for the benchmarking harness — feeding this JSONL to
`evaluate.py` should resolve every problem. If it doesn't, the harness has
a bug, not the model.

The stored `rtl_diff` may contain hunks for files outside `rtl_files_changed`
(the mining flow records the full commit diff even when only a subset is
under bug-fix-surface tracking). The evaluation harness rejects patches that
touch non-allowlisted files, so we filter the saved diff down to just the
declared files before emitting it as the gold prediction. The harness only
reverts those files to the buggy commit anyway, so a filtered gold patch
still resolves the test."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from dvbench.problem_database import ProblemDatabase


GOLD_MODEL_NAME = "gold-rtl_diff"

DIFF_FILE_HEADER_PATTERN = re.compile(r'^diff --git a/(\S+) b/(\S+)$', re.MULTILINE)


def filter_diff_to_allowlist(unified_diff: str, allowlist: set[str]) -> str:
    """Return a unified diff containing only the `diff --git` blocks whose
    post-image path is in `allowlist`. Blocks are split at each `diff --git`
    header (the canonical per-file boundary in git-formatted diffs)."""
    file_header_matches = list(DIFF_FILE_HEADER_PATTERN.finditer(unified_diff))
    if not file_header_matches:
        return unified_diff  # No git-format headers; can't filter — pass through.
    file_header_matches.append(None)  # type: ignore[arg-type]  # sentinel for end-of-string
    kept_blocks: list[str] = []
    for index, header_match in enumerate(file_header_matches[:-1]):
        next_header_match = file_header_matches[index + 1]
        block_end = next_header_match.start() if next_header_match else len(unified_diff)
        post_image_path = header_match.group(2)
        if post_image_path in allowlist:
            kept_blocks.append(unified_diff[header_match.start():block_end])
    return "".join(kept_blocks)


def main() -> int:
    output_jsonl_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "benchmarks/predictions/gold.jsonl"
    )
    output_jsonl_path.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    with output_jsonl_path.open("w") as output_jsonl_file:
        for problem_json_path in ProblemDatabase().list_all_paths():
            problem_json_data = json.loads(problem_json_path.read_text())
            declared_files = set(problem_json_data["rtl_files_changed"])
            filtered_diff = filter_diff_to_allowlist(
                problem_json_data["rtl_diff"], declared_files
            )
            prediction_record = {
                "problem_id": problem_json_data["problem_id"],
                "model_name": GOLD_MODEL_NAME,
                "model_patch": filtered_diff,
            }
            output_jsonl_file.write(json.dumps(prediction_record) + "\n")
            written += 1
    print(f"Wrote {written} predictions → {output_jsonl_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
