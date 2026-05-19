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
           --rtl-dir DIR --dv-dir DIR --test-cmd CMD [--test-cwd DIR]
           <rtl_files>...
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

import json
import sys
from pathlib import Path

import typer

from dvbench.constants import (
    GITHUB_URL_KIND_ORG,
    GITHUB_URL_KIND_REPO,
    GITHUB_URL_KIND_USER,
)
from dvbench.candidates_walker import CandidatesWalker
from dvbench.git_repo import GitRepo
from dvbench.github_api import GitHubApi
from dvbench.log_csv import LogCsv
from dvbench.try_commit import TryCommit


app = typer.Typer(
    help=__doc__,
    no_args_is_help=True,
    add_completion=False,
    rich_markup_mode=None,
    context_settings={"help_option_names": ["-h", "--help"]},
)


@app.command("check-url", help="Check viability of repos from a GitHub URL.")
def check_url(
    url: str = typer.Argument(..., help="GitHub org/user/repo URL"),
) -> None:
    github_api = GitHubApi()
    log_csv = LogCsv()
    url_kind, url_value = GitHubApi.classify_url(url)

    if url_kind == GITHUB_URL_KIND_ORG:
        owner_slash_repo_list = [
            api_repo["full_name"]
            for api_repo in github_api.iter_responses(f"/orgs/{url_value}/repos", type="public")
        ]
    elif url_kind == GITHUB_URL_KIND_USER:
        owner_slash_repo_list = [
            api_repo["full_name"]
            for api_repo in github_api.iter_responses(f"/users/{url_value}/repos", type="public")
        ]
    elif url_kind == GITHUB_URL_KIND_REPO:
        owner_slash_repo_list = [url_value]
    else:
        print(json.dumps({"error": f"Cannot parse GitHub URL: {url}"}), file=sys.stderr)
        raise typer.Exit(code=1)

    for owner_slash_repo in owner_slash_repo_list:
        viability = github_api.repo_viability(owner_slash_repo)
        print(viability.to_json_line(), flush=True)
        log_csv.set(
            repo_url=viability.repo_url,
            repo_name=viability.repo_name,
            reason_skipped=viability.reason or "",
            commits_total=str(viability.commit_count or ""),
        )


@app.command("list-candidates", help="Find candidate commits in a clone.")
def list_candidates(
    clone_dir: Path = typer.Argument(...),
    repo_url: str = typer.Option(..., "--repo-url"),
    rtl_dir: str = typer.Option(..., "--rtl-dir"),
    dv_dir: str = typer.Option(..., "--dv-dir"),
    max_commits: int = typer.Option(1000, "--max-commits"),
    max_rtl_lines: int = typer.Option(50, "--max-rtl-lines"),
) -> None:
    walker = CandidatesWalker(
        GitRepo(clone_dir), LogCsv(),
        repo_url=repo_url,
        rtl_dir=rtl_dir,
        dv_dir=dv_dir,
        max_commits_to_walk=max_commits,
        max_rtl_diff_lines=max_rtl_lines,
    )
    for candidate_record in walker.iter_candidate_records():
        print(candidate_record.to_json_line(), flush=True)


@app.command("try-commit", help="Test a candidate commit pair.")
def try_commit(
    clone_dir: Path = typer.Argument(...),
    repo_url: str = typer.Option(..., "--repo-url"),
    fix_commit: str = typer.Option(..., "--fix-commit"),
    prev_commit: str = typer.Option(..., "--prev-commit"),
    rtl_dir: str = typer.Option(..., "--rtl-dir"),
    dv_dir: str = typer.Option(..., "--dv-dir"),
    test_cmd: str = typer.Option(..., "--test-cmd"),
    test_cwd: Path | None = typer.Option(None, "--test-cwd"),
    rtl_files: list[str] = typer.Argument(..., help="RTL files reverted to produce the buggy state"),
) -> None:
    workflow = TryCommit(
        GitRepo(clone_dir), LogCsv(),
        repo_url=repo_url,
        fix_commit=fix_commit,
        prev_commit=prev_commit,
        rtl_dir=rtl_dir,
        dv_dir=dv_dir,
        rtl_files=rtl_files,
        test_cmd=test_cmd,
        test_cwd=test_cwd or Path.cwd(),
    )
    print(workflow.run().to_json_line())


@app.command("update-log", help="Upsert a row in data/log.csv.")
def update_log(
    repo_url: str = typer.Option(..., "--repo-url"),
    repo_name: str | None = typer.Option(None, "--repo-name"),
    reason: str | None = typer.Option(None, "--reason"),
    current_hash: str | None = typer.Option(None, "--current-hash"),
    commits_total: int | None = typer.Option(None, "--commits-total"),
    add_commits_used: int | None = typer.Option(None, "--add-commits-used"),
    add_commits_walked: int | None = typer.Option(None, "--add-commits-walked"),
    rtl_dir: str | None = typer.Option(None, "--rtl-dir"),
    dv_dir: str | None = typer.Option(None, "--dv-dir"),
    test_cmd: str | None = typer.Option(None, "--test-cmd"),
) -> None:
    log_csv = LogCsv()
    row_fields: dict = {}
    if repo_name is not None:     row_fields["repo_name"]      = repo_name
    if reason is not None:        row_fields["reason_skipped"] = reason
    if current_hash is not None:  row_fields["current_hash"]   = current_hash
    if commits_total is not None: row_fields["commits_total"]  = str(commits_total)
    if rtl_dir is not None:       row_fields["rtl_dir"]        = rtl_dir
    if dv_dir is not None:        row_fields["dv_dir"]         = dv_dir
    if test_cmd is not None:      row_fields["test_cmd"]       = test_cmd

    log_csv.set(repo_url, **row_fields)

    if add_commits_used:
        log_csv.increment_counter(repo_url, "commits_used", add_commits_used)
    if add_commits_walked:
        log_csv.increment_counter(repo_url, "commits_walked", add_commits_walked)


def main() -> None:
    app()
