#!/usr/bin/env python3
"""
mine_repo.py — Mine GitHub Verilog/SV repositories for LLM debugging benchmarks.

Subcommands
-----------
check-url <github_url>
    Resolve a GitHub org/user/repo URL to a list of repos, check each for
    viability (license, language, commit count), and update data/log.csv.
    Emits JSONL to stdout: one record per discovered repo.

list-candidates <clone_dir> --repo-url URL --rtl-dir DIR --dv-dir DIR
                [--max-commits N] [--max-rtl-lines N]
    Walk commits on the default branch. For consecutive pairs where both
    <rtl_dir> and <dv_dir> changed and the RTL diff is ≤ max-rtl-lines,
    emit a JSONL record to stdout. Updates data/log.csv walk counts.

try-commit <clone_dir> --repo-url URL --fix-commit SHA --prev-commit SHA
           --rtl-dir DIR --dv-dir DIR --rtl-files F [F ...] --test-cmd CMD
           [--test-cwd DIR]
    1. git checkout <fix_commit> (clean).
    2. Run <test-cmd> — must exit 0 (passes at fix commit).
    3. git checkout <prev_commit> -- <rtl_files>.
    4. Run <test-cmd> — must exit non-0 (fails with buggy RTL).
    5. Save data/{owner}/{repo}/{fix_commit}.json.
    Emits a JSON result record to stdout.

update-log --repo-url URL [--repo-name NAME] [--reason STR]
           [--current-hash SHA] [--commits-total N]
           [--add-commits-used N] [--add-commits-walked N]
           [--rtl-dir DIR] [--dv-dir DIR] [--test-cmd CMD]
    Upsert one row in data/log.csv.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

try:
    import requests as _req
    HAS_REQ = True
except ImportError:
    HAS_REQ = False

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR  = REPO_ROOT / "data"
LOG_CSV   = DATA_DIR / "log.csv"

LOG_FIELDS = [
    "repo_url", "repo_name", "reason_skipped",
    "current_hash", "commits_used", "commits_walked", "commits_total",
    "rtl_dir", "dv_dir", "test_cmd",
]

# ---------------------------------------------------------------------------
# License classification
# ---------------------------------------------------------------------------
PERMISSIVE = {
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC",
    "Unlicense", "CC0-1.0", "0BSD", "WTFPL", "Artistic-2.0",
    "ECL-2.0", "AFL-3.0", "MS-PL", "MS-RL",
}
COPYLEFT = {
    "GPL-2.0", "GPL-2.0-only", "GPL-2.0-or-later",
    "GPL-3.0", "GPL-3.0-only", "GPL-3.0-or-later",
    "LGPL-2.0", "LGPL-2.1", "LGPL-2.1-only", "LGPL-2.1-or-later",
    "LGPL-3.0", "LGPL-3.0-only", "LGPL-3.0-or-later",
    "AGPL-3.0", "AGPL-3.0-only", "AGPL-3.0-or-later",
    "MPL-2.0", "EUPL-1.0", "EUPL-1.1", "EUPL-1.2",
    "CDDL-1.0", "OSL-3.0", "SSPL-1.0",
}

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def git(args: list[str], cwd=None, check: bool = True) -> str:
    r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed:\n{r.stderr.strip()}")
    return r.stdout.strip()


def default_branch(clone_dir: Path) -> str:
    try:
        b = git(["symbolic-ref", "--short", "HEAD"], cwd=clone_dir)
        if b:
            return b
    except RuntimeError:
        pass
    refs = git(["branch", "-r"], cwd=clone_dir, check=False)
    for line in refs.splitlines():
        name = line.strip().removeprefix("origin/")
        if name in ("main", "master"):
            return name
    return "main"


# ---------------------------------------------------------------------------
# CSV helpers
# ---------------------------------------------------------------------------

def read_log() -> dict[str, dict]:
    if not LOG_CSV.exists():
        return {}
    with open(LOG_CSV, newline="") as f:
        return {r["repo_url"]: r for r in csv.DictReader(f)}


def write_log(rows: dict[str, dict]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with open(LOG_CSV, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=LOG_FIELDS, extrasaction="ignore")
        w.writeheader()
        for row in rows.values():
            w.writerow({k: row.get(k, "") for k in LOG_FIELDS})


def upsert_log(repo_url: str, **kw) -> None:
    rows = read_log()
    if repo_url not in rows:
        rows[repo_url] = {"repo_url": repo_url}
    rows[repo_url].update({k: v for k, v in kw.items() if v is not None})
    write_log(rows)


def increment_log(repo_url: str, field: str, delta: int) -> None:
    rows = read_log()
    if repo_url not in rows:
        rows[repo_url] = {"repo_url": repo_url}
    cur = int(rows[repo_url].get(field) or 0)
    rows[repo_url][field] = str(cur + delta)
    write_log(rows)


# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------

def _gh_headers(token: str | None = None) -> dict:
    token = token or os.environ.get("GITHUB_TOKEN")
    h = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        h["Authorization"] = f"Bearer {token}"
    return h


def gh_get(path: str, token=None, params=None):
    if not HAS_REQ:
        raise RuntimeError("Install requests: pip install requests")
    r = _req.get(
        f"https://api.github.com{path}",
        headers=_gh_headers(token),
        params=params,
        timeout=30,
    )
    r.raise_for_status()
    return r


def gh_all(path: str, token=None, **params):
    """Yield all items across paginated GitHub API responses."""
    page = 1
    while True:
        r = gh_get(path, token=token, params={"per_page": 100, "page": page, **params})
        items = r.json()
        if not items:
            break
        yield from items
        page += 1


def gh_commit_count(owner: str, repo: str, token=None) -> int:
    try:
        r = gh_get(f"/repos/{owner}/{repo}/commits", token=token, params={"per_page": 1})
        m = re.search(r'page=(\d+)>; rel="last"', r.headers.get("Link", ""))
        return int(m.group(1)) if m else 1
    except Exception:
        return 0


# ---------------------------------------------------------------------------
# URL parsing
# ---------------------------------------------------------------------------

def parse_github_url(url: str) -> tuple[str, str]:
    """Return (kind, value) where kind ∈ {org, user, repo, unknown}."""
    url = url.strip()
    base = re.sub(r"[?#].*", "", url).rstrip("/")

    # org repos: https://github.com/orgs/ORGNAME[/repositories]
    m = re.match(r"https?://github\.com/orgs/([^/]+)", base)
    if m:
        return "org", m.group(1)

    # user repos: ?tab=repositories in query
    if "tab=repositories" in url:
        m = re.match(r"https?://github\.com/([^/?#]+)", base)
        if m:
            return "user", m.group(1)

    # direct repo: https://github.com/OWNER/REPO
    m = re.match(r"https?://github\.com/([^/]+)/([^/]+)$", base)
    if m:
        return "repo", f"{m.group(1)}/{m.group(2)}"

    # bare OWNER/REPO
    m = re.match(r"^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$", url.strip())
    if m:
        return "repo", f"{m.group(1)}/{m.group(2)}"

    return "unknown", url


# ---------------------------------------------------------------------------
# Repo viability
# ---------------------------------------------------------------------------

def _check_one_repo(owner_repo: str, token=None) -> dict:
    owner, rname = owner_repo.split("/", 1)
    repo_url = f"https://github.com/{owner}/{rname}"

    try:
        info  = gh_get(f"/repos/{owner}/{rname}", token=token).json()
        langs = gh_get(f"/repos/{owner}/{rname}/languages", token=token).json()
    except Exception as e:
        return {"repo_url": repo_url, "owner": owner, "repo_name": rname,
                "viable": False, "reason": f"API error: {e}"}

    spdx = (info.get("license") or {}).get("spdx_id", "")

    reason = None
    if info.get("archived"):
        reason = "archived"
    elif info.get("fork"):
        reason = "fork"
    elif spdx in COPYLEFT:
        reason = f"bad license: {spdx}"
    else:
        total    = sum(langs.values()) or 1
        sv_bytes = langs.get("SystemVerilog", 0)
        v_bytes  = langs.get("Verilog", 0)
        hdl_pct  = (sv_bytes + v_bytes) / total * 100

        primary = info.get("language", "") or ""
        if hdl_pct < 5:
            reason = "not enough Verilog/SV (<5%)"
        elif primary not in ("SystemVerilog", "Verilog", "") and hdl_pct < 15:
            reason = f"wrong HDL: primary language is {primary}"

    commit_count = 0
    if not reason:
        commit_count = gh_commit_count(owner, rname, token)
        if commit_count < 10:
            reason = f"not enough commits ({commit_count})"

    total    = sum(langs.values()) or 1
    sv_bytes = langs.get("SystemVerilog", 0)
    v_bytes  = langs.get("Verilog", 0)
    hdl_pct  = (sv_bytes + v_bytes) / total * 100

    return {
        "repo_url":     repo_url,
        "owner":        owner,
        "repo_name":    rname,
        "viable":       reason is None,
        "reason":       reason,
        "license":      spdx or "none",
        "language":     "SystemVerilog" if sv_bytes >= v_bytes else "Verilog",
        "hdl_pct":      round(hdl_pct, 1),
        "commit_count": commit_count,
        "stars":        info.get("stargazers_count", 0),
    }


# ---------------------------------------------------------------------------
# Subcommand: check-url
# ---------------------------------------------------------------------------

def cmd_check_url(args):
    token = os.environ.get("GITHUB_TOKEN")
    kind, value = parse_github_url(args.url)

    if kind == "org":
        owner_repos = [r["full_name"] for r in
                       gh_all(f"/orgs/{value}/repos", token=token, type="public")]
    elif kind == "user":
        owner_repos = [r["full_name"] for r in
                       gh_all(f"/users/{value}/repos", token=token, type="public")]
    elif kind == "repo":
        owner_repos = [value]
    else:
        print(json.dumps({"error": f"Cannot parse GitHub URL: {args.url}"}),
              file=sys.stderr)
        sys.exit(1)

    for owner_repo in owner_repos:
        info = _check_one_repo(owner_repo, token=token)
        print(json.dumps(info), flush=True)
        owner, rname = owner_repo.split("/", 1)
        upsert_log(
            repo_url=info["repo_url"],
            repo_name=rname,
            reason_skipped=info.get("reason") or "",
            commits_total=str(info.get("commit_count") or ""),
        )


# ---------------------------------------------------------------------------
# Subcommand: list-candidates
# ---------------------------------------------------------------------------

def cmd_list_candidates(args):
    cdir    = Path(args.clone_dir)
    rtl_dir = args.rtl_dir.rstrip("/")
    dv_dir  = args.dv_dir.rstrip("/")

    branch  = default_branch(cdir)
    # Fetch hash + subject together so we can filter by commit message cheaply.
    log_lines = git(
        ["log", "--format=%H\t%s", f"-{args.max_commits}", branch], cwd=cdir
    ).splitlines()
    commit_pairs = [(l.split("\t", 1)[0], l.split("\t", 1)[1] if "\t" in l else "")
                    for l in log_lines if l.strip()]

    total  = len(commit_pairs)
    walked = 0

    _COVERAGE_RE = re.compile(
        r"\[(?:fcov|cov|dv[, ]*fcov|dv[, ]*cov)\]"
        r"|coverage[\s_]+(add|only|fix|update)"
        r"|\bfcov\b",
        re.IGNORECASE,
    )

    for i in range(len(commit_pairs) - 1):
        fix_c,  fix_subj  = commit_pairs[i]
        prev_c, _         = commit_pairs[i + 1]

        # Skip coverage-only commits early (cheap, before any diff fetch).
        if _COVERAGE_RE.search(fix_subj):
            continue

        changed = git(["diff", "--name-only", prev_c, fix_c], cwd=cdir).splitlines()
        rtl_chg = [f for f in changed
                   if f == rtl_dir or f.startswith(rtl_dir + "/")]
        dv_chg  = [f for f in changed
                   if f == dv_dir or f.startswith(dv_dir + "/")]

        walked += 1

        if not rtl_chg or not dv_chg:
            continue

        rtl_diff = git(["diff", prev_c, fix_c, "--", rtl_dir], cwd=cdir)
        added   = sum(1 for l in rtl_diff.splitlines()
                      if l.startswith("+") and not l.startswith("+++"))
        removed = sum(1 for l in rtl_diff.splitlines()
                      if l.startswith("-") and not l.startswith("---"))
        diff_lines = added + removed

        if diff_lines > args.max_rtl_lines:
            continue

        commit_msg = git(["log", "-1", "--format=%B", fix_c], cwd=cdir).strip()

        print(json.dumps({
            "fix_commit":  fix_c,
            "prev_commit": prev_c,
            "commit_msg":  commit_msg,
            "rtl_files":   rtl_chg,
            "dv_files":    dv_chg,
            "diff_lines":  diff_lines,
            "rtl_diff":    rtl_diff,
        }), flush=True)

    upsert_log(
        repo_url=args.repo_url,
        commits_total=str(total),
        commits_walked=str(walked),
    )


# ---------------------------------------------------------------------------
# Subcommand: try-commit
# ---------------------------------------------------------------------------

def _run_test(cmd: str, cwd: Path) -> tuple[bool, str]:
    r = subprocess.run(
        cmd, shell=True, cwd=cwd,
        capture_output=True, text=True, timeout=600,
    )
    return r.returncode == 0, (r.stdout + r.stderr)


def cmd_try_commit(args):
    cdir     = Path(args.clone_dir)
    test_cwd = Path(args.test_cwd) if args.test_cwd else Path.cwd()

    result = {
        "repo_url":   args.repo_url,
        "fix_commit": args.fix_commit,
    }

    # 1. Checkout fix commit cleanly
    try:
        git(["checkout", "-f", args.fix_commit], cwd=cdir)
        git(["clean", "-fd"], cwd=cdir)
    except RuntimeError as e:
        result.update({"outcome": "error", "reason": str(e)})
        print(json.dumps(result))
        return

    # 2. Run test at fix commit — must pass
    try:
        passed, out = _run_test(args.test_cmd, test_cwd)
    except subprocess.TimeoutExpired:
        result.update({"outcome": "skip", "reason": "timeout at fix commit"})
        print(json.dumps(result))
        return

    if not passed:
        result.update({
            "outcome": "skip",
            "reason":  "test fails at fix commit",
            "test_output": out[-3000:],
        })
        print(json.dumps(result))
        return

    # 3. Revert RTL files to prev commit
    try:
        git(["checkout", args.prev_commit, "--"] + args.rtl_files, cwd=cdir)
    except RuntimeError as e:
        result.update({"outcome": "error", "reason": f"revert failed: {e}"})
        print(json.dumps(result))
        return

    # 4. Run test with buggy RTL — must fail
    try:
        passed2, out2 = _run_test(args.test_cmd, test_cwd)
    except subprocess.TimeoutExpired:
        result.update({"outcome": "skip", "reason": "timeout with buggy RTL"})
        print(json.dumps(result))
        return

    if passed2:
        result.update({"outcome": "skip", "reason": "test passes with buggy RTL"})
        print(json.dumps(result))
        return

    # 5. Save instance
    m = re.match(r"https?://github\.com/([^/]+)/([^/]+)", args.repo_url)
    owner, rname = (m.group(1), m.group(2)) if m else ("unknown", "unknown")

    rtl_diff = git(["diff", args.prev_commit, args.fix_commit, "--", args.rtl_dir],
                   cwd=cdir)
    diff_lines = sum(
        1 for l in rtl_diff.splitlines()
        if (l.startswith("+") and not l.startswith("+++"))
        or (l.startswith("-") and not l.startswith("---"))
    )

    fix_commit_msg = git(["log", "-1", "--format=%B", args.fix_commit], cwd=cdir).strip()

    instance = {
        "instance_id":       f"{owner}__{rname}__{args.fix_commit}",
        "repo_url":          args.repo_url,
        "owner":             owner,
        "repo_name":         rname,
        "fix_commit":        args.fix_commit,
        "buggy_rtl_commit":  args.prev_commit,
        "fix_commit_msg":    fix_commit_msg,
        "problem_statement": fix_commit_msg,
        "date_created":      date.today().isoformat(),
        "rtl_dir":           args.rtl_dir,
        "dv_dir":            args.dv_dir,
        "rtl_files_changed": args.rtl_files,
        "test_commands":     [args.test_cmd],
        "setup_commands": (
            [
                f"git clone {args.repo_url} repo",
                "cd repo",
                f"git checkout {args.fix_commit}",
            ]
            + [f"git checkout {args.prev_commit} -- {f}" for f in args.rtl_files]
        ),
        "rtl_diff":          rtl_diff,
        "rtl_diff_lines":    diff_lines,
        "source":            "historical",
    }

    out_dir  = DATA_DIR / owner / rname
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{args.fix_commit}.json"
    with open(out_path, "w") as f:
        json.dump(instance, f, indent=2)

    result.update({"outcome": "success", "saved": str(out_path)})
    print(json.dumps(result))

    upsert_log(repo_url=args.repo_url, current_hash=args.fix_commit)
    increment_log(args.repo_url, "commits_used", 1)


# ---------------------------------------------------------------------------
# Subcommand: update-log
# ---------------------------------------------------------------------------

def cmd_update_log(args):
    kw: dict = {}
    if args.repo_name:                kw["repo_name"]      = args.repo_name
    if args.reason:                   kw["reason_skipped"] = args.reason
    if args.current_hash:             kw["current_hash"]   = args.current_hash
    if args.commits_total is not None: kw["commits_total"] = str(args.commits_total)
    if args.rtl_dir:                  kw["rtl_dir"]        = args.rtl_dir
    if args.dv_dir:                   kw["dv_dir"]         = args.dv_dir
    if args.test_cmd:                 kw["test_cmd"]       = args.test_cmd

    upsert_log(args.repo_url, **kw)

    if args.add_commits_used:
        increment_log(args.repo_url, "commits_used",   args.add_commits_used)
    if args.add_commits_walked:
        increment_log(args.repo_url, "commits_walked", args.add_commits_walked)


# ---------------------------------------------------------------------------
# Argument parsing + dispatch
# ---------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    # check-url
    p1 = sub.add_parser("check-url", help="Check viability of repos from a GitHub URL")
    p1.add_argument("url", help="GitHub org/user/repo URL")

    # list-candidates
    p2 = sub.add_parser("list-candidates", help="Find candidate commits in a clone")
    p2.add_argument("clone_dir")
    p2.add_argument("--repo-url",      required=True)
    p2.add_argument("--rtl-dir",       required=True)
    p2.add_argument("--dv-dir",        required=True)
    p2.add_argument("--max-commits",   type=int, default=1000)
    p2.add_argument("--max-rtl-lines", type=int, default=50)

    # try-commit
    p3 = sub.add_parser("try-commit", help="Test a candidate commit pair")
    p3.add_argument("clone_dir")
    p3.add_argument("--repo-url",    required=True)
    p3.add_argument("--fix-commit",  required=True)
    p3.add_argument("--prev-commit", required=True)
    p3.add_argument("--rtl-dir",     required=True)
    p3.add_argument("--dv-dir",      required=True)
    p3.add_argument("--rtl-files",   nargs="+", required=True)
    p3.add_argument("--test-cmd",    required=True)
    p3.add_argument("--test-cwd",    default=None)

    # update-log
    p4 = sub.add_parser("update-log", help="Upsert a row in data/log.csv")
    p4.add_argument("--repo-url",           required=True)
    p4.add_argument("--repo-name",          default=None)
    p4.add_argument("--reason",             default=None)
    p4.add_argument("--current-hash",       default=None)
    p4.add_argument("--commits-total",      type=int, default=None)
    p4.add_argument("--add-commits-used",   type=int, default=None)
    p4.add_argument("--add-commits-walked", type=int, default=None)
    p4.add_argument("--rtl-dir",            default=None)
    p4.add_argument("--dv-dir",             default=None)
    p4.add_argument("--test-cmd",           default=None)

    args = p.parse_args()
    dispatch = {
        "check-url":       cmd_check_url,
        "list-candidates": cmd_list_candidates,
        "try-commit":      cmd_try_commit,
        "update-log":      cmd_update_log,
    }
    dispatch[args.cmd](args)


if __name__ == "__main__":
    main()
