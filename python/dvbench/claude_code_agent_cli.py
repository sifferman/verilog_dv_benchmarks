"""Run Claude Code (subscription-auth, headless `claude -p`) against every
problem and emit per-run CSV + JSONL.

Why `claude -p` and not the Anthropic Agent SDK or the raw API?
  - The Agent SDK requires `ANTHROPIC_API_KEY` from the Console (pay-per-token).
  - The raw API requires the same key.
  - The `claude` CLI is auth'd via your claude.ai login (OAuth) so it works
    against a Claude Code subscription with no separate billing setup.

For each problem we:
  1. Build a fresh sandbox via `prepare_sandbox` (optionally with VCD-dump
     injection so an MCP-VCD server has waveforms to read).
  2. Snapshot the buggy contents of every file in `rtl_files_changed`.
  3. Spawn `claude -p` (optionally with --mcp-config), letting it explore
     and edit until it stops, hits the cost budget, or the wall clock fires.
  4. Run `bash ./verify` in the same sandbox to score resolved/unresolved.
  5. Diff the (now-edited) RTL files against the snapshots to capture the
     model's patch.
  6. Write one CSV row + one JSONL prediction per problem.
"""
from __future__ import annotations

import concurrent.futures
import csv
import difflib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable

import typer

from dvbench.prepare_sandbox_cli import prepare_sandbox
from dvbench.problem_database import ProblemDatabase
from dvbench.records import Problem


PROMPT_TEMPLATE = """\
You are a hardware verification engineer. There's a bug in the RTL design
in this sandbox — your job is to find and fix it.

## The sandbox
- `clones/{owner}/{repo}/` — the upstream RTL. Edit only the file(s) listed below.
- `problems/{owner}/{repo}/` — the testbench (read-only; don't edit).
- `PROBLEM.md` — the problem description.

## Files you may edit (and only these)
{rtl_file_list}

## Verifying your work
Run `bash ./verify` from the sandbox root. It exits 0 iff the bug is fixed
and non-zero while the bug is still present. The testbench will print a
PASS/FAIL line.
{mcp_vcd_section}
## Approach
1. Read `PROBLEM.md` for the bug description.
2. Read the testbench under `problems/{owner}/{repo}/` to understand what's
   being checked.
3. Read the file(s) you may edit and identify the bug.
4. Make a minimal fix — change only what's needed, don't refactor.
5. Run `./verify` to confirm it passes.

Stop as soon as `./verify` exits 0.
"""

MCP_VCD_PROMPT_SECTION = """
## Waveform inspection (recommended for tricky bugs)
When `./verify` runs the simulator, it writes a `dump.vcd` waveform file
to the sandbox root. **You have access to the `mcp-vcd` MCP server** —
use it to peek at signal values over time when reasoning about
timing-sensitive bugs. Feel free to consult the waveform whenever it'd
save you reasoning steps.

The tool's signature:
    get-signal(file_name="<absolute path to dump.vcd>",
               signal_name="<leaf signal name, e.g. 'clk'>",
               start_time=<optional ns>, end_time=<optional ns>)

It's especially useful when:
  - the test reports "expected X at time T but got Y"
  - you need to confirm when a control signal asserts/deasserts
  - you suspect a stuck-at, gating, or off-by-one timing issue
  - a value flows through several pipeline stages and you need to see
    which stage corrupted it
"""

ALLOWED_TOOLS = "Bash Read Edit Write Glob Grep mcp__mcp-vcd__get-signal"

# A cost-limit hit is inferred when total_cost_usd is at least this fraction
# of the configured --max-budget-usd cap (Claude Code stops a tick before
# strictly exceeding the cap, so exact equality is rare).
COST_LIMIT_HIT_FRACTION = 0.95

# Resume mode: when a CSV already exists, skip rows that represent a "real"
# attempt (resolved, real patch attempt, real timeout, real cost-cap). The
# remaining rows are rate-limit stubs (num_turns=1, cost=0, stop_sequence)
# and should be retried.
RATE_LIMIT_STUB_STOP_REASON = "stop_sequence"

# Wall-clock cap for the verify wrapper after the agent finishes. The agent
# itself may already have spent budget running it; this is just to confirm
# pass/fail.
POST_RUN_VERIFY_TIMEOUT_SECONDS = 600


@dataclass
class AgentRunResult:
    """One agent attempt at one problem. The CSV writer pulls every public
    field from here."""
    problem_id: str
    model_name: str
    resolved: bool
    duration_s: float
    num_turns: int
    input_tokens: int
    output_tokens: int
    cache_read_input_tokens: int
    cache_creation_input_tokens: int
    total_cost_usd: float
    patch_bytes: int
    total_tool_calls: int
    mcp_tool_calls: int
    mcp_tool_errors: int
    timeout_hit: bool
    cost_limit_hit: bool
    cli_exit_code: int
    stop_reason: str
    verify_exit_code: int | None
    error: str = ""
    # Not serialized into the CSV, but kept for the JSONL prediction file.
    model_patch: str = field(default="", repr=False)


CSV_COLUMNS = (
    "problem_id",
    "model_name",
    "resolved",
    "duration_s",
    "num_turns",
    "input_tokens",
    "output_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
    "total_cost_usd",
    "patch_bytes",
    "total_tool_calls",
    "mcp_tool_calls",
    "mcp_tool_errors",
    "timeout_hit",
    "cost_limit_hit",
    "cli_exit_code",
    "stop_reason",
    "verify_exit_code",
    "error",
)


def _build_prompt(problem: Problem, *, mcp_vcd_enabled: bool) -> str:
    rtl_file_list = "\n".join(
        f"- `clones/{problem.owner}/{problem.repo_name}/{rtl_file_path}`"
        for rtl_file_path in problem.rtl_files_changed
    )
    return PROMPT_TEMPLATE.format(
        owner=problem.owner,
        repo=problem.repo_name,
        rtl_file_list=rtl_file_list,
        mcp_vcd_section=MCP_VCD_PROMPT_SECTION if mcp_vcd_enabled else "",
    )


def _snapshot_buggy_files(problem: Problem, sandbox_dir: Path) -> dict[str, str]:
    snapshots: dict[str, str] = {}
    for rtl_file_path in problem.rtl_files_changed:
        absolute_path = (
            sandbox_dir / "clones" / problem.owner / problem.repo_name / rtl_file_path
        )
        snapshots[rtl_file_path] = absolute_path.read_text()
    return snapshots


def _build_diff_from_snapshots(
    problem: Problem, sandbox_dir: Path, snapshots: dict[str, str]
) -> str:
    diff_parts: list[str] = []
    for rtl_file_path, original_content in snapshots.items():
        current_path = (
            sandbox_dir / "clones" / problem.owner / problem.repo_name / rtl_file_path
        )
        current_content = current_path.read_text()
        if current_content == original_content:
            continue
        unified_diff_body = "".join(difflib.unified_diff(
            original_content.splitlines(keepends=True),
            current_content.splitlines(keepends=True),
            fromfile=f"a/{rtl_file_path}",
            tofile=f"b/{rtl_file_path}",
        ))
        diff_parts.append(
            f"diff --git a/{rtl_file_path} b/{rtl_file_path}\n" + unified_diff_body
        )
    return "".join(diff_parts)


@dataclass
class StreamedClaudeRun:
    """What we got from a `claude -p --output-format stream-json` run."""
    exit_code: int
    final_result_json: dict          # the trailing {"type":"result", ...} doc
    total_tool_calls: int
    mcp_tool_calls: int
    mcp_tool_errors: int
    stderr_tail: str
    wall_clock_timeout_hit: bool


def _run_claude_code_in_sandbox(
    prompt: str, sandbox_dir: Path, model_alias: str,
    mcp_config_path: Path | None, max_budget_usd: float,
    timeout_seconds: int,
) -> StreamedClaudeRun:
    """Spawn `claude -p --output-format stream-json` rooted in the sandbox
    and parse each line as it arrives. We use stream-json (not the simpler
    `json` mode) specifically so we can see every individual `tool_use`
    event and tally how many of them target an MCP server (mcp-vcd in
    particular). The final `{"type":"result",...}` line carries the same
    aggregate usage/cost data the old `json` mode emitted."""
    cli_argv = [
        "claude", "-p", prompt,
        "--model", model_alias,
        "--output-format", "stream-json",
        "--verbose",                 # stream-json requires --verbose
        "--add-dir", str(sandbox_dir),
        "--allowedTools", ALLOWED_TOOLS,
        "--permission-mode", "acceptEdits",
        "--max-budget-usd", str(max_budget_usd),
    ]
    if mcp_config_path is not None:
        # Resolve to absolute — `claude -p` looks for the MCP config relative
        # to its own cwd, which here is the sandbox (not the project root
        # where the path was specified).
        cli_argv += ["--mcp-config", str(mcp_config_path.resolve())]

    final_result_json: dict = {}
    total_tool_calls = 0
    mcp_tool_calls = 0
    mcp_tool_errors = 0
    seen_mcp_tool_use_ids: set[str] = set()
    timed_out = False  # set by the watchdog closure below when timeout fires

    # `start_new_session=True` so `claude` and every child it spawns
    # (vvp, verilator, iverilog, npm helpers …) share a fresh process
    # group whose pgid == claude's pid. The watchdog then kills the whole
    # group, not just the main pid — otherwise grandchildren keep stdout
    # held open and the read loop never sees EOF.
    process_handle = subprocess.Popen(
        cli_argv, cwd=sandbox_dir, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, bufsize=1,
        start_new_session=True,
    )
    process_group_id = process_handle.pid

    def _kill_on_deadline() -> None:
        nonlocal timed_out
        timed_out = True
        try:
            os.killpg(process_group_id, signal.SIGKILL)
        except (ProcessLookupError, OSError):
            pass
    watchdog_timer = threading.Timer(timeout_seconds, _kill_on_deadline)
    watchdog_timer.start()
    try:
        # Tail-cap stderr (we keep only the last few hundred chars for the
        # error column). stdout we have to read incrementally to keep the
        # pipe drained.
        assert process_handle.stdout is not None
        for raw_line in process_handle.stdout:
            stripped_line = raw_line.strip()
            if not stripped_line:
                continue
            try:
                event = json.loads(stripped_line)
            except (json.JSONDecodeError, ValueError):
                continue

            event_type = event.get("type")
            if event_type == "assistant":
                # Walk the message content; each content item with
                # type==tool_use is one call. MCP tools have names of the
                # form `mcp__<server>__<tool>` per Claude Code convention.
                content_items = (
                    event.get("message", {}).get("content") or []
                )
                for content_item in content_items:
                    if content_item.get("type") != "tool_use":
                        continue
                    total_tool_calls += 1
                    tool_name = content_item.get("name", "")
                    if tool_name.startswith("mcp__"):
                        mcp_tool_calls += 1
                        tool_use_id = content_item.get("id")
                        if tool_use_id:
                            seen_mcp_tool_use_ids.add(tool_use_id)
            elif event_type == "user":
                # Tool result event — count errors that came back from
                # MCP-flagged calls.
                content_items = (
                    event.get("message", {}).get("content") or []
                )
                for content_item in content_items:
                    if content_item.get("type") != "tool_result":
                        continue
                    if not content_item.get("is_error"):
                        continue
                    if content_item.get("tool_use_id") in seen_mcp_tool_use_ids:
                        mcp_tool_errors += 1
            elif event_type == "result":
                final_result_json = event

        # The stdout loop terminated (either the process exited cleanly or
        # the watchdog killed it). Reap so .returncode is populated.
        process_handle.wait()
    finally:
        watchdog_timer.cancel()
        stderr_text = ""
        if process_handle.stderr is not None:
            try:
                stderr_text = process_handle.stderr.read() or ""
            except Exception:
                pass

    return StreamedClaudeRun(
        exit_code=process_handle.returncode if process_handle.returncode is not None else -1,
        final_result_json=final_result_json,
        total_tool_calls=total_tool_calls,
        mcp_tool_calls=mcp_tool_calls,
        mcp_tool_errors=mcp_tool_errors,
        stderr_tail=stderr_text[-500:].strip(),
        wall_clock_timeout_hit=timed_out,
    )


def _run_post_run_verify(sandbox_dir: Path) -> int | None:
    """Run `bash ./verify` after the agent stops; non-zero means the bug is
    still present. Returns None if verify itself errored out or timed out."""
    try:
        completed_process = subprocess.run(
            ["bash", str(sandbox_dir / "verify")],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=POST_RUN_VERIFY_TIMEOUT_SECONDS,
        )
        return completed_process.returncode
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def _run_agent_on_one_problem(
    problem: Problem, model_alias: str,
    mcp_config_path: Path | None, max_budget_usd: float,
    timeout_seconds: int, enable_vcd_dump: bool,
) -> AgentRunResult:
    started_at_monotonic = time.monotonic()
    sandbox_root = Path(tempfile.mkdtemp(prefix="dvbench_agent_"))
    sandbox_dir = sandbox_root / "sandbox"
    try:
        prepare_sandbox(
            problem_id=problem.problem_id,
            output_dir=sandbox_dir,
            overwrite=False,
            no_scrub=False,
            enable_vcd_dump=enable_vcd_dump,
        )
        snapshots = _snapshot_buggy_files(problem, sandbox_dir)
        prompt = _build_prompt(problem, mcp_vcd_enabled=mcp_config_path is not None)

        streamed_run = _run_claude_code_in_sandbox(
            prompt, sandbox_dir, model_alias, mcp_config_path,
            max_budget_usd, timeout_seconds,
        )
        cli_result = streamed_run.final_result_json
        model_patch = _build_diff_from_snapshots(problem, sandbox_dir, snapshots)
        verify_exit_code = _run_post_run_verify(sandbox_dir)

        total_cost_usd = cli_result.get("total_cost_usd", 0.0) or 0.0
        cost_limit_hit = total_cost_usd >= max_budget_usd * COST_LIMIT_HIT_FRACTION

        return AgentRunResult(
            problem_id=problem.problem_id,
            model_name=model_alias,
            resolved=verify_exit_code == 0,
            duration_s=round(time.monotonic() - started_at_monotonic, 2),
            num_turns=cli_result.get("num_turns", 0) or 0,
            input_tokens=cli_result.get("usage", {}).get("input_tokens", 0) or 0,
            output_tokens=cli_result.get("usage", {}).get("output_tokens", 0) or 0,
            cache_read_input_tokens=cli_result.get("usage", {}).get(
                "cache_read_input_tokens", 0
            ) or 0,
            cache_creation_input_tokens=cli_result.get("usage", {}).get(
                "cache_creation_input_tokens", 0
            ) or 0,
            total_cost_usd=total_cost_usd,
            patch_bytes=len(model_patch),
            total_tool_calls=streamed_run.total_tool_calls,
            mcp_tool_calls=streamed_run.mcp_tool_calls,
            mcp_tool_errors=streamed_run.mcp_tool_errors,
            timeout_hit=streamed_run.wall_clock_timeout_hit,
            cost_limit_hit=cost_limit_hit,
            cli_exit_code=streamed_run.exit_code,
            stop_reason=cli_result.get("stop_reason") or "",
            verify_exit_code=verify_exit_code,
            error=(streamed_run.stderr_tail
                   if streamed_run.exit_code != 0 and not streamed_run.wall_clock_timeout_hit
                   else ""),
            model_patch=model_patch,
        )
    finally:
        shutil.rmtree(sandbox_root, ignore_errors=True)


def _run_one_for_pool(args: tuple) -> AgentRunResult | tuple[str, str]:
    problem_json_path, model_alias, mcp_config_path, max_budget_usd, \
        timeout_seconds, enable_vcd_dump = args
    problem = Problem.load_from_json(problem_json_path)
    try:
        return _run_agent_on_one_problem(
            problem, model_alias, mcp_config_path, max_budget_usd,
            timeout_seconds, enable_vcd_dump,
        )
    except Exception as caught_exception:
        return (problem.problem_id, repr(caught_exception))


def _log_agent_result(result: AgentRunResult) -> None:
    tags: list[str] = []
    if result.resolved:
        tags.append("✓RESOLVED")
    if result.timeout_hit:
        tags.append("TIMEOUT")
    if result.cost_limit_hit:
        tags.append("COST_CAP")
    if not result.resolved and not result.timeout_hit and not result.cost_limit_hit:
        tags.append("unresolved")
    if result.mcp_tool_calls > 0:
        tags.append(f"mcp×{result.mcp_tool_calls}")
    tag_string = " " + " ".join(tags) if tags else ""
    print(
        f"[done] {result.problem_id} —"
        f" {result.duration_s:.1f}s,"
        f" {result.num_turns} turns,"
        f" tools={result.total_tool_calls},"
        f" out={result.output_tokens:,}"
        f" cache_r={result.cache_read_input_tokens:,}"
        f" ${result.total_cost_usd:.4f}"
        f"{tag_string}",
        file=sys.stderr, flush=True,
    )


def _write_csv_row(
    csv_writer: csv.DictWriter, csv_file_handle, result: AgentRunResult,
) -> None:
    row = {column_name: getattr(result, column_name) for column_name in CSV_COLUMNS}
    csv_writer.writerow(row)
    csv_file_handle.flush()


def _write_jsonl_line(predictions_file_handle, result: AgentRunResult) -> None:
    predictions_file_handle.write(json.dumps({
        "problem_id": result.problem_id,
        "model_name": result.model_name,
        "model_patch": result.model_patch,
        "usage": {
            "input_tokens": result.input_tokens,
            "output_tokens": result.output_tokens,
            "cache_read_input_tokens": result.cache_read_input_tokens,
            "cache_creation_input_tokens": result.cache_creation_input_tokens,
            "num_turns": result.num_turns,
            "total_cost_usd": result.total_cost_usd,
            "timeout_hit": result.timeout_hit,
            "cost_limit_hit": result.cost_limit_hit,
        },
    }) + "\n")
    predictions_file_handle.flush()


def _read_existing_csv_outcomes(csv_path: Path) -> dict[str, dict]:
    """Read an existing CSV (from a prior partial sweep) and index by
    problem_id. Caller decides which rows to keep vs retry."""
    if not csv_path.is_file():
        return {}
    indexed: dict[str, dict] = {}
    with csv_path.open() as csv_file_handle:
        for row in csv.DictReader(csv_file_handle):
            indexed[row["problem_id"]] = row
    return indexed


def _row_represents_real_attempt(csv_row: dict) -> bool:
    """A "real attempt" is one where the model genuinely engaged — either it
    resolved the problem, made any edit, or hit a real time/cost cap. Rows
    where stop_reason='stop_sequence' with num_turns=1 and cost=0 are
    rate-limit stubs that should be re-run."""
    if csv_row.get("resolved", "").lower() == "true":
        return True
    if int(csv_row.get("patch_bytes", "0") or 0) > 0:
        return True
    if csv_row.get("timeout_hit", "").lower() == "true":
        return True
    if csv_row.get("cost_limit_hit", "").lower() == "true":
        return True
    if int(csv_row.get("num_turns", "0") or 0) > 1:
        return True
    return False


def run_agent_against_dataset(
    problem_json_paths: Iterable[Path],
    *,
    model_alias: str,
    csv_path: Path,
    predictions_jsonl_path: Path | None,
    worker_count: int,
    max_budget_usd: float,
    timeout_seconds: int,
    mcp_config_path: Path | None,
    enable_vcd_dump: bool,
    resume: bool,
) -> list[AgentRunResult]:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    if predictions_jsonl_path is not None:
        predictions_jsonl_path.parent.mkdir(parents=True, exist_ok=True)
    problem_json_paths = list(problem_json_paths)

    existing_rows_by_problem_id: dict[str, dict] = {}
    real_attempts_to_keep: list[dict] = []
    if resume:
        existing_rows_by_problem_id = _read_existing_csv_outcomes(csv_path)
        real_attempts_to_keep = [
            row for row in existing_rows_by_problem_id.values()
            if _row_represents_real_attempt(row)
        ]
        problem_ids_to_skip = {row["problem_id"] for row in real_attempts_to_keep}
        problem_json_paths = [
            path for path in problem_json_paths
            if Problem.load_from_json(path).problem_id not in problem_ids_to_skip
        ]
        print(
            f"[agent] resume: existing CSV has {len(existing_rows_by_problem_id)}"
            f" rows; keeping {len(real_attempts_to_keep)} real attempts;"
            f" retrying {len(problem_json_paths)} problems",
            file=sys.stderr, flush=True,
        )

    print(
        f"[agent] {len(problem_json_paths)} problems"
        f" model={model_alias}"
        f" workers={worker_count}"
        f" budget=${max_budget_usd}/problem"
        f" timeout={timeout_seconds}s"
        f" mcp={'yes' if mcp_config_path else 'no'}"
        f" vcd_dump={'yes' if enable_vcd_dump else 'no'}",
        file=sys.stderr, flush=True,
    )

    worker_args_list = [
        (
            problem_json_path, model_alias, mcp_config_path,
            max_budget_usd, timeout_seconds, enable_vcd_dump,
        )
        for problem_json_path in problem_json_paths
    ]

    results: list[AgentRunResult] = []
    csv_file_handle = csv_path.open("w", newline="")
    csv_writer = csv.DictWriter(csv_file_handle, fieldnames=CSV_COLUMNS)
    csv_writer.writeheader()
    # Re-emit the kept real attempts at the top of the new CSV.
    for kept_row in real_attempts_to_keep:
        csv_writer.writerow({column: kept_row.get(column, "") for column in CSV_COLUMNS})
    csv_file_handle.flush()
    predictions_file_handle = (
        predictions_jsonl_path.open("w") if predictions_jsonl_path else None
    )
    try:
        if worker_count <= 1:
            for worker_args in worker_args_list:
                worker_result = _run_one_for_pool(worker_args)
                _handle_worker_outcome(
                    worker_result, csv_writer, csv_file_handle,
                    predictions_file_handle, results,
                )
        else:
            with concurrent.futures.ProcessPoolExecutor(max_workers=worker_count) as worker_pool:
                submitted_futures = [
                    worker_pool.submit(_run_one_for_pool, worker_args)
                    for worker_args in worker_args_list
                ]
                for completed_future in concurrent.futures.as_completed(submitted_futures):
                    worker_result = completed_future.result()
                    _handle_worker_outcome(
                        worker_result, csv_writer, csv_file_handle,
                        predictions_file_handle, results,
                    )
    finally:
        csv_file_handle.close()
        if predictions_file_handle is not None:
            predictions_file_handle.close()

    return results


def _handle_worker_outcome(
    worker_result, csv_writer, csv_file_handle,
    predictions_file_handle, results,
) -> None:
    if isinstance(worker_result, AgentRunResult):
        _log_agent_result(worker_result)
        _write_csv_row(csv_writer, csv_file_handle, worker_result)
        if predictions_file_handle is not None:
            _write_jsonl_line(predictions_file_handle, worker_result)
        results.append(worker_result)
    else:
        problem_id, error_repr = worker_result
        print(f"[error] {problem_id}: {error_repr}", file=sys.stderr, flush=True)


def run_claude_code_agent(
    problem_id: str | None = typer.Option(None, "--problem-id"),
    problem_ids_file: Path | None = typer.Option(None, "--problem-ids-file"),
    run_all: bool = typer.Option(False, "--all"),
    model_alias: str = typer.Option("sonnet", "--model"),
    csv_out: Path = typer.Option(
        Path("benchmarks/runs/claude-code.csv"), "--csv-out",
        help="Where to write the per-problem CSV.",
    ),
    predictions: Path | None = typer.Option(
        None, "--predictions",
        help="Optional: also write a predictions JSONL (one row per problem"
             " with model_patch) suitable for python/evaluate.py.",
    ),
    workers: int = typer.Option(4, "--workers"),
    max_budget_usd: float = typer.Option(2.00, "--max-budget-usd"),
    timeout_seconds: int = typer.Option(
        600, "--timeout-seconds",
        help="Wall-clock cap per `claude -p` invocation. The agent's own"
             " cost cap usually fires first; this is a safety net.",
    ),
    mcp_config: Path | None = typer.Option(
        None, "--mcp-config",
        help="Path to an MCP config JSON file (passed through to `claude -p"
             " --mcp-config`). e.g. benchmarks/mcp-vcd.json",
    ),
    enable_vcd_dump: bool = typer.Option(
        False, "--enable-vcd-dump",
        help="Inject `$dumpfile + $dumpvars(0, ...)` into testbench SV files"
             " so simulators emit dump.vcd. Useful for MCP-VCD experiments.",
    ),
    resume: bool = typer.Option(
        False, "--resume",
        help="If --csv-out already exists, skip problems whose row represents"
             " a real attempt (resolved, real patch, real timeout, real"
             " cost-cap, or num_turns>1) and only re-run rate-limit stubs"
             " (num_turns=1, cost=0, stop_sequence). Lets you recover from"
             " mid-sweep subscription quota exhaustion by re-running once"
             " the 5-hour window refreshes.",
    ),
) -> None:
    """Drive `claude -p` (Claude Code, subscription auth) against the
    benchmark dataset. Writes a CSV with per-problem metrics + an optional
    predictions JSONL."""
    selection_modes_specified = sum(
        1 for selected in (problem_id, problem_ids_file, run_all or None) if selected
    )
    if selection_modes_specified != 1:
        raise typer.BadParameter(
            "Specify exactly one of --problem-id, --problem-ids-file, or --all."
        )

    problem_database = ProblemDatabase()
    if run_all:
        problem_json_paths = problem_database.list_all_paths()
    elif problem_ids_file is not None:
        ids_to_run = [
            line.strip() for line in problem_ids_file.read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        problem_json_paths = [problem_database.resolve_by_id(pid) for pid in ids_to_run]
    else:
        assert problem_id is not None
        problem_json_paths = [problem_database.resolve_by_id(problem_id)]

    results = run_agent_against_dataset(
        problem_json_paths,
        model_alias=model_alias,
        csv_path=csv_out,
        predictions_jsonl_path=predictions,
        worker_count=workers,
        max_budget_usd=max_budget_usd,
        timeout_seconds=timeout_seconds,
        mcp_config_path=mcp_config,
        enable_vcd_dump=enable_vcd_dump,
        resume=resume,
    )

    resolved_count = sum(1 for r in results if r.resolved)
    timeout_count = sum(1 for r in results if r.timeout_hit)
    cost_cap_count = sum(1 for r in results if r.cost_limit_hit)
    aggregate_cost_usd = sum(r.total_cost_usd for r in results)
    print(
        f"\n=== Sweep done: {len(results)} problems ===\n"
        f"  resolved       : {resolved_count}/{len(results)}\n"
        f"  timeout hits   : {timeout_count}\n"
        f"  cost-cap hits  : {cost_cap_count}\n"
        f"  est. total cost: ${aggregate_cost_usd:.2f}\n"
        f"  CSV            : {csv_out}\n"
        + (f"  JSONL          : {predictions}\n" if predictions else ""),
        file=sys.stderr,
    )


def main() -> int:
    typer.run(run_claude_code_agent)
    return 0


if __name__ == "__main__":
    sys.exit(main())
