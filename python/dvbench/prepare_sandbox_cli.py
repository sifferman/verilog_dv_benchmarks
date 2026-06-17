"""
prepare_sandbox.py — sandbox builder for benchmark evaluations.

Materializes a self-contained working directory for one Problem so that an
LLM (or a human) can attempt the bug fix in isolation. The layout mirrors the
project root so the bundled test runners — which use project-relative paths
like `$SCRIPT_DIR/../../env.sh` and `$SCRIPT_DIR/../../../clones/<owner>/<repo>` —
"just work" when invoked from inside the sandbox.

Threat model
------------
Assume the LLM can read every file in the sandbox. The sandbox is hardened by:
  - Excluding every `.git` directory (the upstream repo, the submodules,
    every sibling clone). `git log` cannot name the fix commit.
  - Scrubbing comments and fix-revealing diagnostic strings in the testbench
    files (see `dvbench.scrub`). The scrub is per-problem-configurable via the
    optional `scrub` key in the problem JSON.
  - Omitting the per-problem `<sha>.json` files (they carry `rtl_diff` and
    the fix commit SHA).

Layout (under `<sandbox>/`)
---------------------------
  clones/<owner>/<repo>/       upstream repo, buggy-state RTL, no .git
  clones/<other>/<sibling>/    sibling clones the runner references, no .git
  problems/env.sh              shared toolchain discovery (verbatim copy)
  problems/<owner>/<repo>/     scrubbed per-problem testbench files
  PROBLEM.md                   task brief (no rtl_diff, no fix commit SHA)
  verify                       cd-in wrapper that runs the bundled test_commands
"""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

import typer

from dvbench.constants import CLONES_DIRECTORY, PROBLEMS_DIRECTORY, SANDBOXES_DIRECTORY
from dvbench.git_repo import GitRepo
from dvbench.problem_database import ProblemDatabase
from dvbench.records import Problem
from dvbench.scrub import ScrubConfig, Scrubber

# Extensions copied (and scrubbed) into sandbox/problems/<owner>/<repo>/.
# JSONs are deliberately omitted since they carry rtl_diff and the fix SHA.
TESTBENCH_FILE_EXTENSIONS = (
    ".sv", ".v", ".svh", ".vh", ".vlt",
    ".cpp", ".c", ".h", ".hpp",
    ".S", ".sh",
)

# Patterns we grep out of each testbench runner to discover which submodules
# need pre-init and which sibling clones need pre-copy. The runner can't run
# either operation itself once .git is gone, so prepare_sandbox does it.
SUBMODULE_INIT_CALL_PATTERN = re.compile(
    r'\bdvbench_init_submodule\s+"\$REPO_DIR"\s+(\S+)'
)
SIBLING_CLONE_CALL_PATTERN = re.compile(
    r'\bdvbench_ensure_sibling_clone\s+"\$CLONES_ROOT"\s+(\S+)\s+(\S+)'
)
# Also detect *direct* path references like
# `cd "$SCRIPT_DIR/../../../clones/secworks/aes"` — some hand-written runners
# pull in a sibling clone this way without using the helper.
SIBLING_CLONE_PATH_PATTERN = re.compile(
    r'clones/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)'
)


def prepare_sandbox(
    problem_id: str = typer.Option(..., "--problem-id", help="Full or sha-only problem id"),
    output_dir: Path | None = typer.Option(
        None, "--output-dir",
        help="Where to materialize the sandbox. Default: sandboxes/{problem_id}/"
    ),
    overwrite: bool = typer.Option(
        False, "--overwrite", help="Delete the sandbox directory if it already exists"
    ),
    no_scrub: bool = typer.Option(
        False, "--no-scrub",
        help="Skip the scrub pass on copied testbench files. Useful for"
             " debugging the harness; do not use when handing the sandbox to"
             " a model.",
    ),
    enable_vcd_dump: bool = typer.Option(
        False, "--enable-vcd-dump",
        help="Inject `$dumpfile + $dumpvars(0)` blocks into each tb_*.sv so"
             " simulators emit a VCD at sandbox-relative `dump.vcd`. Used"
             " when running with an MCP-VCD server.",
    ),
) -> None:
    problem = Problem.load_from_json(ProblemDatabase().resolve_by_id(problem_id))
    sandbox_dir = output_dir or SANDBOXES_DIRECTORY / problem.problem_id

    if sandbox_dir.exists():
        if not overwrite:
            print(
                f"Sandbox already exists at {sandbox_dir}. Pass --overwrite to replace.",
                file=sys.stderr,
            )
            raise typer.Exit(code=1)
        shutil.rmtree(sandbox_dir)

    sandbox_dir.mkdir(parents=True)
    sandbox_clones_root = sandbox_dir / "clones"
    sandbox_problems_root = sandbox_dir / "problems"

    required_submodule_paths, required_sibling_clones = _scan_runner_dependencies(problem)

    # Acquire the per-repo lock so we don't race a parallel verify worker
    # mutating the same clone via `hard_checkout`/`revert_files` below.
    with problem.repo_exclusive_lock():
        workspace_git_repo = GitRepo(problem.repo_clone_directory, tee_git_commands=True)
        workspace_git_repo.hard_checkout(problem.fix_commit)
        workspace_git_repo.clean_working_tree()
        workspace_git_repo.revert_files(problem.buggy_rtl_commit, problem.rtl_files_changed)

        for submodule_path in required_submodule_paths:
            print(f"Pre-initializing submodule {submodule_path}", file=sys.stderr)
            workspace_git_repo.init_submodule(submodule_path)

        print(
            f"Copying clone → {sandbox_clones_root / problem.owner / problem.repo_name}"
            f" (no .git)",
            file=sys.stderr,
        )
        shutil.copytree(
            problem.repo_clone_directory,
            sandbox_clones_root / problem.owner / problem.repo_name,
            symlinks=True,
            ignore=shutil.ignore_patterns(".git"),
        )

    for sibling_owner, sibling_repo in required_sibling_clones:
        source_sibling_clone = CLONES_DIRECTORY / sibling_owner / sibling_repo
        if not source_sibling_clone.is_dir():
            print(
                f"WARNING: sibling clone {sibling_owner}/{sibling_repo} not present at"
                f" {source_sibling_clone}; runner will fail. Run it once via verify_problem"
                f" to populate, then retry prepare_sandbox.",
                file=sys.stderr,
            )
            continue
        print(
            f"Copying sibling clone → {sandbox_clones_root / sibling_owner / sibling_repo}"
            f" (no .git)",
            file=sys.stderr,
        )
        shutil.copytree(
            source_sibling_clone,
            sandbox_clones_root / sibling_owner / sibling_repo,
            symlinks=True,
            ignore=shutil.ignore_patterns(".git"),
        )

    _materialize_problems_directory(problem, sandbox_problems_root, skip_scrub=no_scrub)
    if enable_vcd_dump:
        _inject_vcd_dump_into_testbenches(problem, sandbox_problems_root)
    (sandbox_dir / "PROBLEM.md").write_text(_problem_brief(problem))
    _write_verify_wrapper(problem, sandbox_dir)

    print(f"\nSandbox ready: {sandbox_dir}", file=sys.stderr)
    print(f"Run with: bash {sandbox_dir / 'verify'}", file=sys.stderr)


def _scan_runner_dependencies(problem: Problem) -> tuple[list[str], list[tuple[str, str]]]:
    """Grep every per-problem runner for explicit `dvbench_init_submodule` /
    `dvbench_ensure_sibling_clone` calls plus direct `clones/<owner>/<repo>`
    path references, so we can pre-populate everything they need (the runner
    can't do any of it once .git is stripped). The main repo's own owner/repo
    is filtered out — that's the clone we already copied."""
    problem_source_directory = problem.problem_json_path.parent
    submodule_paths: list[str] = []
    sibling_clones: list[tuple[str, str]] = []
    for runner_path in problem_source_directory.rglob("run_*.sh"):
        runner_text = runner_path.read_text()
        for submodule_match in SUBMODULE_INIT_CALL_PATTERN.finditer(runner_text):
            submodule_path = submodule_match.group(1)
            if submodule_path not in submodule_paths:
                submodule_paths.append(submodule_path)
        for sibling_clone_match in SIBLING_CLONE_CALL_PATTERN.finditer(runner_text):
            sibling_clone = (sibling_clone_match.group(1), sibling_clone_match.group(2))
            if sibling_clone not in sibling_clones:
                sibling_clones.append(sibling_clone)
        for path_match in SIBLING_CLONE_PATH_PATTERN.finditer(runner_text):
            referenced_clone = (path_match.group(1), path_match.group(2))
            if referenced_clone == (problem.owner, problem.repo_name):
                continue  # the main clone — already handled
            if referenced_clone not in sibling_clones:
                sibling_clones.append(referenced_clone)
    return submodule_paths, sibling_clones


# Pattern for the first `module <name>(...)` declaration in an SV file. Used
# to look up the top-module name for the $dumpvars hierarchical target.
SV_MODULE_DECLARATION_PATTERN = re.compile(
    r'^\s*module\s+(\w+)\s*[(;]', re.MULTILINE
)


def _inject_vcd_dump_into_testbenches(
    problem: Problem, sandbox_problems_root: Path
) -> None:
    """Make the sandboxed testbenches emit a `dump.vcd`. Two steps:
      1. Insert `$dumpfile + $dumpvars(0, <top_module>);` right before the
         last `endmodule` in each tb_*.sv / tb_top_*.v.
      2. For Verilator-based runners, add `--trace` to the verilator command
         (without it $dumpvars is a no-op under Verilator). Iverilog-based
         runners honor $dumpvars natively; cocotb-driven tests aren't
         touched (they'd need a sim-specific WAVES env var).
    The dump.vcd lands in whatever the runner's cwd is at simulation time."""
    testbench_directory = sandbox_problems_root / problem.owner / problem.repo_name
    for testbench_file_path in testbench_directory.rglob("tb_*.sv"):
        _inject_dump_block_into_sv_file(testbench_file_path)
    for testbench_file_path in testbench_directory.rglob("tb_top_*.v"):
        _inject_dump_block_into_sv_file(testbench_file_path)
    for runner_file_path in testbench_directory.rglob("run_*.sh"):
        _add_trace_flag_to_verilator_runner(runner_file_path)


def _add_trace_flag_to_verilator_runner(runner_file_path: Path) -> None:
    """If the runner invokes `verilator --binary`, ensure `--trace` is also
    present so the simulator honors `$dumpvars`. Idempotent."""
    file_contents = runner_file_path.read_text()
    if "verilator" not in file_contents or "--binary" not in file_contents:
        return
    if "--trace" in file_contents:
        return
    rewritten = file_contents.replace("--binary", "--binary --trace", 1)
    runner_file_path.write_text(rewritten)


def _inject_dump_block_into_sv_file(sv_file_path: Path) -> None:
    """Find the first `module <NAME>` and inject a `$dumpfile + $dumpvars`
    initial block right before this module's `endmodule`. Idempotent — skips
    files that already mention `$dumpvars`."""
    file_contents = sv_file_path.read_text()
    if "$dumpvars" in file_contents:
        return
    module_declaration_match = SV_MODULE_DECLARATION_PATTERN.search(file_contents)
    if module_declaration_match is None:
        return
    top_module_name = module_declaration_match.group(1)
    # Inject before the *last* endmodule so we don't accidentally land inside
    # a nested module declaration. The last endmodule belongs to the outermost
    # module in the file (which is the top in our hand-written testbenches).
    last_endmodule_index = file_contents.rfind("endmodule")
    if last_endmodule_index == -1:
        return
    dump_block = (
        f"\n  initial begin\n"
        f"    $dumpfile(\"dump.vcd\");\n"
        f"    $dumpvars(0, {top_module_name});\n"
        f"  end\n"
    )
    rewritten_contents = (
        file_contents[:last_endmodule_index]
        + dump_block
        + file_contents[last_endmodule_index:]
    )
    sv_file_path.write_text(rewritten_contents)


def _materialize_problems_directory(
    problem: Problem, sandbox_problems_root: Path, *, skip_scrub: bool
) -> None:
    """Mirror the project's `problems/` layout into the sandbox, copying just
    enough to make the per-problem test_commands runnable in-place:
      - `problems/env.sh`               — shared toolchain discovery (verbatim).
      - `problems/<owner>/<repo>/...`   — scrubbed per-problem testbench files.
    The per-problem `<sha>.json` files are omitted (they carry rtl_diff)."""
    sandbox_problems_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PROBLEMS_DIRECTORY / "env.sh", sandbox_problems_root / "env.sh")

    problem_source_directory = problem.problem_json_path.parent
    testbench_destination_directory = (
        sandbox_problems_root / problem.owner / problem.repo_name
    )
    testbench_destination_directory.mkdir(parents=True, exist_ok=True)

    scrubber = Scrubber(
        ScrubConfig() if skip_scrub else problem.scrub_config
    )
    if skip_scrub:
        print(
            "WARNING: --no-scrub set; testbench files are copied verbatim.",
            file=sys.stderr,
        )

    for source_file_path in problem_source_directory.rglob("*"):
        if not source_file_path.is_file():
            continue
        if source_file_path.suffix not in TESTBENCH_FILE_EXTENSIONS:
            continue
        relative_path = source_file_path.relative_to(problem_source_directory)
        destination_file_path = testbench_destination_directory / relative_path

        if skip_scrub:
            destination_file_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source_file_path, destination_file_path)
            continue

        scrubber.scrub_file(
            source_file_path=source_file_path,
            destination_file_path=destination_file_path,
            relative_path_inside_problem_dir=str(relative_path),
        )


def _write_verify_wrapper(problem: Problem, sandbox_dir: Path) -> None:
    """Write a `verify` script at the sandbox root that runs the bundled
    `test_commands` from inside the sandbox. The runner uses its original
    project-relative paths (`$SCRIPT_DIR/../../env.sh` etc.) and they
    resolve correctly because the sandbox mirrors the project layout."""
    verify_wrapper_path = sandbox_dir / "verify"
    verify_wrapper_path.write_text(
        "#!/usr/bin/env bash\n"
        "set -euo pipefail\n"
        'cd "$(dirname "$0")"\n'
        + "\n".join(problem.test_commands)
        + "\n"
    )
    verify_wrapper_path.chmod(0o755)


def _problem_brief(problem: Problem) -> str:
    rtl_file_lines = "\n".join(f"- `{path}`" for path in problem.rtl_files_changed)
    return (
        f"# Debug me — `{problem.owner}/{problem.repo_name}`\n"
        f"\n"
        f"This is a buggy snapshot of [{problem.repo_url}]({problem.repo_url}).\n"
        f"The following RTL files contain a regression that needs to be fixed:\n"
        f"\n"
        f"{rtl_file_lines}\n"
        f"\n"
        f"## Run the test (it currently fails)\n"
        f"\n"
        f"```bash\n"
        f"./verify\n"
        f"```\n"
        f"\n"
        f"`./verify` exits 0 iff the bug is fixed. Read the failing test\n"
        f"output, edit the RTL files listed above, and rerun.\n"
        f"\n"
        f"## Where things live\n"
        f"\n"
        f"- `clones/{problem.owner}/{problem.repo_name}/` — the buggy RTL.\n"
        f"  Edit files here.\n"
        f"- `problems/{problem.owner}/{problem.repo_name}/` — testbench files\n"
        f"  (comments stripped, diagnostic strings neutralized). Read-only\n"
        f"  for inspection; don't edit, your changes won't survive harness\n"
        f"  re-evaluation.\n"
    )


def main() -> None:
    typer.run(prepare_sandbox)
