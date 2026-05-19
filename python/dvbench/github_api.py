from __future__ import annotations

import os
import re
from typing import Iterable

from dvbench.constants import (
    BARE_OWNER_SLASH_REPO_PATTERN,
    COPYLEFT_LICENSE_SPDX_IDS,
    GITHUB_PAGINATION_LAST_PAGE_PATTERN,
    GITHUB_URL_DIRECT_REPO_PATTERN,
    GITHUB_URL_KIND_ORG,
    GITHUB_URL_KIND_REPO,
    GITHUB_URL_KIND_UNKNOWN,
    GITHUB_URL_KIND_USER,
    GITHUB_URL_ORG_PATTERN,
    GITHUB_URL_USER_PREFIX_PATTERN,
)
from dvbench.records import RepoViabilityReport

try:
    import requests
    _REQUESTS_LIBRARY_AVAILABLE = True
except ImportError:
    _REQUESTS_LIBRARY_AVAILABLE = False


class GitHubApi:
    """Wraps the GitHub REST API for the few endpoints mining needs, plus
    pure-URL parsing utilities (as static methods)."""

    def __init__(self, api_token: str | None = None) -> None:
        self.api_token = api_token or os.environ.get("GITHUB_TOKEN")

    # ---- HTTP methods (require an instance) ----------------------------------

    def _request_headers(self) -> dict[str, str]:
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if self.api_token:
            headers["Authorization"] = f"Bearer {self.api_token}"
        return headers

    def get(self, api_path: str, query_params: dict | None = None):
        if not _REQUESTS_LIBRARY_AVAILABLE:
            raise RuntimeError("Install requests: pip install requests")
        response = requests.get(
            f"https://api.github.com{api_path}",
            headers=self._request_headers(),
            params=query_params,
            timeout=30,
        )
        response.raise_for_status()
        return response

    def iter_responses(self, api_path: str, **query_params) -> Iterable[dict]:
        """Generator that walks every page of a GitHub list endpoint, yielding
        one resource dict at a time. Page boundaries are hidden — the caller
        sees a flat stream. Pages are fetched lazily, so breaking the loop
        early avoids unneeded HTTP calls."""
        current_page_number = 1
        while True:
            response = self.get(
                api_path,
                query_params={"per_page": 100, "page": current_page_number, **query_params},
            )
            page_items = response.json()
            if not page_items:
                break
            yield from page_items
            current_page_number += 1

    def _fetch_commit_count(self, owner: str, repo_name: str) -> int:
        try:
            response = self.get(
                f"/repos/{owner}/{repo_name}/commits", query_params={"per_page": 1}
            )
            last_page_match = GITHUB_PAGINATION_LAST_PAGE_PATTERN.search(
                response.headers.get("Link", "")
            )
            return int(last_page_match.group(1)) if last_page_match else 1
        except Exception:
            return 0

    def repo_viability(self, owner_slash_repo: str) -> RepoViabilityReport:
        owner, repo_name = owner_slash_repo.split("/", 1)
        repo_url = f"https://github.com/{owner}/{repo_name}"

        try:
            repo_info = self.get(f"/repos/{owner}/{repo_name}").json()
            byte_counts_by_language = self.get(
                f"/repos/{owner}/{repo_name}/languages"
            ).json()
        except Exception as caught_exception:
            return RepoViabilityReport(
                repo_url=repo_url, owner=owner, repo_name=repo_name,
                viable=False, reason=f"API error: {caught_exception}",
                license="none", language="Verilog", hdl_pct=0.0,
                commit_count=0, stars=0,
            )

        skip_reason = self._classify_repo_skip_reason(
            owner, repo_name, repo_info, byte_counts_by_language
        )

        return RepoViabilityReport(
            repo_url=repo_url,
            owner=owner,
            repo_name=repo_name,
            viable=skip_reason is None,
            reason=skip_reason,
            license=_spdx_license_id(repo_info) or "none",
            language=_dominant_hdl(byte_counts_by_language),
            hdl_pct=round(_hdl_percentage(byte_counts_by_language), 1),
            commit_count=self._fetch_commit_count(owner, repo_name),
            stars=repo_info.get("stargazers_count", 0),
        )

    def _classify_repo_skip_reason(
        self,
        owner: str,
        repo_name: str,
        repo_info: dict,
        byte_counts_by_language: dict,
    ) -> str | None:
        """Apply cheap dict-based screening rules first; only hit the commits
        endpoint if everything else looks good."""
        if repo_info.get("archived"):
            return "archived"
        if repo_info.get("fork"):
            return "fork"
        spdx = _spdx_license_id(repo_info)
        if spdx in COPYLEFT_LICENSE_SPDX_IDS:
            return f"bad license: {spdx}"
        hdl_pct = _hdl_percentage(byte_counts_by_language)
        if hdl_pct < 5:
            return "not enough Verilog/SV (<5%)"
        primary_language = repo_info.get("language", "") or ""
        if primary_language not in ("SystemVerilog", "Verilog", "") and hdl_pct < 15:
            return f"wrong HDL: primary language is {primary_language}"
        commit_count = self._fetch_commit_count(owner, repo_name)
        if commit_count < 10:
            return f"not enough commits ({commit_count})"
        return None

    # ---- pure URL parsing (no HTTP, no state) --------------------------------

    @staticmethod
    def classify_url(raw_url: str) -> tuple[str, str]:
        """Return `(kind, slug)` where `kind in {org, user, repo, unknown}`."""
        stripped_url = raw_url.strip()
        base_url = re.sub(r"[?#].*", "", stripped_url).rstrip("/")

        org_url_match = GITHUB_URL_ORG_PATTERN.match(base_url)
        if org_url_match:
            return GITHUB_URL_KIND_ORG, org_url_match.group(1)

        if "tab=repositories" in stripped_url:
            user_url_match = GITHUB_URL_USER_PREFIX_PATTERN.match(base_url)
            if user_url_match:
                return GITHUB_URL_KIND_USER, user_url_match.group(1)

        direct_repo_url_match = GITHUB_URL_DIRECT_REPO_PATTERN.match(base_url)
        if direct_repo_url_match:
            return (
                GITHUB_URL_KIND_REPO,
                f"{direct_repo_url_match.group(1)}/{direct_repo_url_match.group(2)}",
            )

        bare_owner_repo_match = BARE_OWNER_SLASH_REPO_PATTERN.match(stripped_url)
        if bare_owner_repo_match:
            return (
                GITHUB_URL_KIND_REPO,
                f"{bare_owner_repo_match.group(1)}/{bare_owner_repo_match.group(2)}",
            )

        return GITHUB_URL_KIND_UNKNOWN, raw_url

    @staticmethod
    def extract_repo_owner(repo_url: str) -> tuple[str, str]:
        """Pull `(owner, repo_name)` out of a GitHub repo URL."""
        repo_url_match = re.match(r"https?://github\.com/([^/]+)/([^/]+)", repo_url)
        if repo_url_match:
            return repo_url_match.group(1), repo_url_match.group(2)
        return "unknown", "unknown"


# ---- helpers that derive fields from GitHub API responses --------------------

def _hdl_percentage(byte_counts_by_language: dict) -> float:
    """Verilog + SystemVerilog as a percentage of total source bytes (0-100)."""
    total_bytes = sum(byte_counts_by_language.values()) or 1
    sv_bytes = byte_counts_by_language.get("SystemVerilog", 0)
    v_bytes = byte_counts_by_language.get("Verilog", 0)
    return (sv_bytes + v_bytes) / total_bytes * 100


def _spdx_license_id(repo_info: dict) -> str:
    """The SPDX id from a `/repos/...` response, or `""` if missing."""
    return (repo_info.get("license") or {}).get("spdx_id", "")


def _dominant_hdl(byte_counts_by_language: dict) -> str:
    """Whichever of Verilog or SystemVerilog has more bytes in the repo."""
    sv_bytes = byte_counts_by_language.get("SystemVerilog", 0)
    v_bytes = byte_counts_by_language.get("Verilog", 0)
    return "SystemVerilog" if sv_bytes >= v_bytes else "Verilog"
