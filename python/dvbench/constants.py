from __future__ import annotations

import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
PROBLEMS_DIRECTORY = PROJECT_ROOT / "problems"
CLONES_DIRECTORY = PROJECT_ROOT / "clones"
LOGS_DIRECTORY = PROJECT_ROOT / "logs"
SANDBOXES_DIRECTORY = PROJECT_ROOT / "sandboxes"
REPO_LOCKS_DIRECTORY = LOGS_DIRECTORY / ".locks"
DEFAULT_LOG_CSV_PATH = PROBLEMS_DIRECTORY / "log.csv"

LOG_CSV_COLUMNS = [
    "repo_url", "repo_name", "reason_skipped",
    "current_hash", "commits_used", "commits_walked", "commits_total",
    "rtl_dir", "dv_dir", "test_cmd",
]

COPYLEFT_LICENSE_SPDX_IDS = {
    "GPL-2.0", "GPL-2.0-only", "GPL-2.0-or-later",
    "GPL-3.0", "GPL-3.0-only", "GPL-3.0-or-later",
    "LGPL-2.0", "LGPL-2.1", "LGPL-2.1-only", "LGPL-2.1-or-later",
    "LGPL-3.0", "LGPL-3.0-only", "LGPL-3.0-or-later",
    "AGPL-3.0", "AGPL-3.0-only", "AGPL-3.0-or-later",
    "MPL-2.0", "EUPL-1.0", "EUPL-1.1", "EUPL-1.2",
    "CDDL-1.0", "OSL-3.0", "SSPL-1.0",
}

COVERAGE_ONLY_COMMIT_PATTERN = re.compile(
    r"\[(?:fcov|cov|dv[, ]*fcov|dv[, ]*cov)\]"
    r"|coverage[\s_]+(add|only|fix|update)"
    r"|\bfcov\b",
    re.IGNORECASE,
)

GITHUB_URL_ORG_PATTERN = re.compile(r"https?://github\.com/orgs/([^/]+)")
GITHUB_URL_DIRECT_REPO_PATTERN = re.compile(r"https?://github\.com/([^/]+)/([^/]+)$")
GITHUB_URL_USER_PREFIX_PATTERN = re.compile(r"https?://github\.com/([^/?#]+)")
BARE_OWNER_SLASH_REPO_PATTERN = re.compile(r"^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$")
GITHUB_PAGINATION_LAST_PAGE_PATTERN = re.compile(r'page=(\d+)>; rel="last"')

GITHUB_URL_KIND_ORG = "org"
GITHUB_URL_KIND_USER = "user"
GITHUB_URL_KIND_REPO = "repo"
GITHUB_URL_KIND_UNKNOWN = "unknown"

MODE_VERIFY = "verify"
MODE_SOLUTION = "solution"
MODE_BUGGY = "buggy"
ALL_VERIFY_MODES = (MODE_VERIFY, MODE_SOLUTION, MODE_BUGGY)

RESULT_VERIFIED = "verified"
RESULT_SOLUTION_PASSED = "solution_passed"
RESULT_SOLUTION_DID_NOT_PASS = "solution_did_not_pass"
RESULT_BUGGY_FAILED = "buggy_failed"
RESULT_BUGGY_DID_NOT_FAIL = "buggy_did_not_fail"
RESULT_ERROR = "error"
SUCCESSFUL_RESULT_LABELS = {RESULT_VERIFIED, RESULT_SOLUTION_PASSED, RESULT_BUGGY_FAILED}

TEST_COMMAND_TIMEOUT_SECONDS = 600
TRUNCATED_TEST_OUTPUT_TAIL_BYTES = 3000
