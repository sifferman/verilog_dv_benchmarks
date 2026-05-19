from __future__ import annotations

import csv
from pathlib import Path

from dvbench.constants import DEFAULT_LOG_CSV_PATH, LOG_CSV_COLUMNS


class LogCsv:
    """Wraps problems/log.csv as a dict keyed by repo_url. `set` creates the
    row if missing; `increment_counter` reads-modifies-writes one column."""

    def __init__(self, csv_path: Path = DEFAULT_LOG_CSV_PATH) -> None:
        self.csv_path = csv_path

    def _url2row_dict(self) -> dict[str, dict]:
        if not self.csv_path.exists():
            return {}
        with open(self.csv_path, newline="") as log_csv_file:
            return {row["repo_url"]: row for row in csv.DictReader(log_csv_file)}

    def _write(self, url2row_dict: dict[str, dict]) -> None:
        self.csv_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.csv_path, "w", newline="") as log_csv_file:
            csv_writer = csv.DictWriter(
                log_csv_file, fieldnames=LOG_CSV_COLUMNS, extrasaction="ignore"
            )
            csv_writer.writeheader()
            for row in url2row_dict.values():
                csv_writer.writerow(
                    {column: row.get(column, "") for column in LOG_CSV_COLUMNS}
                )

    def set(self, repo_url: str, **fields_to_update) -> None:
        url2row_dict = self._url2row_dict()
        if repo_url not in url2row_dict:
            url2row_dict[repo_url] = {"repo_url": repo_url}
        url2row_dict[repo_url].update(
            {field: value for field, value in fields_to_update.items() if value is not None}
        )
        self._write(url2row_dict)

    def increment_counter(self, repo_url: str, counter_column: str, delta: int) -> None:
        url2row_dict = self._url2row_dict()
        if repo_url not in url2row_dict:
            url2row_dict[repo_url] = {"repo_url": repo_url}
        current_count = int(url2row_dict[repo_url].get(counter_column) or 0)
        url2row_dict[repo_url][counter_column] = str(current_count + delta)
        self._write(url2row_dict)
