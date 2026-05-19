# /mine — Mine Verilog/SV repos for LLM debugging benchmarks

## Argument

`$ARGUMENTS` — one of:
- A GitHub URL (direct repo, org listing page, or user listing page)
- A path to a newline-delimited file of GitHub URLs
- Empty → read `./repos` line by line

---

## Phase 1 — Discover repos

Parse `$ARGUMENTS` (or `./repos` if empty) into a list of GitHub URLs.
For each URL, run:

```bash
python python/mine_repo.py check-url "<url>"
```

This emits JSONL to stdout — one record per discovered repository.
Collect every record where `"viable": true`. Skip (log) any where `"viable": false`.

If the URL is an org or user listing, the script expands it to all public repos
automatically.

---

## Phase 2 — Clone and inspect (agent-assisted)

For each viable repo, working through them one at a time:

### 2a. Clone

Clone into the project-local `clones/` directory (tracked in `.gitignore`):

```bash
git clone --filter=blob:none "<repo_url>" clones/<owner>/<repo_name>
```

`--filter=blob:none` gives full commit history with on-demand blob fetching.

### 2b. Identify RTL and DV directories

Inspect the repo structure. Common patterns:

| Role | Typical directories |
|------|---------------------|
| RTL  | `rtl/`, `src/rtl/`, `hdl/`, `verilog/`, `sv/`, `src/` |
| DV   | `dv/`, `tb/`, `sim/`, `testbench/`, `test/`, `tests/`, `bench/`, `verification/` |

Use `find` to locate `.sv`/`.v` files (RTL) and `*_tb.sv`, `*_test.sv`, files
containing `initial begin` / assertion syntax (DV). Use your judgment.

Both `rtl_dir` and `dv_dir` must be distinct paths. If the repo combines them
in one directory (e.g., everything under `src/`), choose the most specific
sub-paths you can distinguish.

If the DV lives in a separate repo, record `"reason_skipped": "DV in separate
repo"` and skip with:

```bash
python python/mine_repo.py update-log --repo-url "<url>" --reason "DV in separate repo"
```

### 2c. Identify the build / simulation system

Look for: `Makefile`, `*.core` (FuseSoC), `CMakeLists.txt`, `pyproject.toml`
with cocotb, `run*.sh`, or a top-level `README` describing how to run tests.

Write a single test command `<test_cmd>` that:
- Compiles and simulates the design
- Exits **0** on pass, **non-zero** on failure
- Uses **relative paths from the project root** — never absolute paths, never `/tmp`
- Works when run from the project root (the default `test_cwd` for `mine_repo.py`)

Common examples (paths relative to project root):
```bash
make sim                                          # Makefile target in clone
fusesoc run --target=sim <core>                   # FuseSoC
python -m pytest dv/                              # cocotb / pytest
bash problems/<owner>/<repo>/run_tests.sh         # custom runner script
```

#### Toolchain policy

A repo with a **unique build toolchain** is fine to mine as long as one of
these is true:

1. **The toolchain can be replicated** with what we already have. The most
   common case: a repo's official DV runs on commercial VCS / Questa /
   Xcelium, but the same testbench compiles under modern Verilator with
   `--binary` (see "Verilator version note" below). Replicate, don't import.
2. **The tool can be installed in CI** — extend
   `.github/workflows/verify.yml` to install it and add the binary to
   `$GITHUB_PATH`. Already supported there: oss-cad-suite (iverilog,
   verilator, yosys), sv2v, FuseSoC (`pip install fusesoc`), cocotb 1.x +
   cocotb-test stack, riscv32-unknown-elf-gcc. Source `problems/env.sh`
   from your runner so it discovers the same tools locally.

If a repo requires a **new toolchain** that's neither replicable nor on the
list above, do not silently skip — instead:
- Add an install step to `.github/workflows/verify.yml` (Apache/MIT-licensed
  prebuilt binary preferred; document the source URL inline).
- Add a discovery block to `problems/env.sh` so local runs find it.
- Then write the runner.

Hard blockers that *do* warrant `update-log --reason ...` and skipping:
- Tools that can't be redistributed (e.g. Questa, VCS, Vivado, Quartus) and
  the repo's testbench has no open-source equivalent path.
- Tools that require a license server you don't control.
- Anything that depends on a hardware target board to run.

Mark these with reasons like `"Questa/VCS-only DV"` or `"hardware-in-the-loop only"`.

**STRONGLY PREFER using the repo's own DV.** Even if the full test suite can't
run, look hard for a subset that can:
- A standalone directed test or unit test that exercises the changed RTL
- A Verilator-compatible testbench (look for `ifndef VERILATOR` guards — these
  often just need `--timing` and a minor patch to the clock generator)
- A C++/DPI-based testbench that compiles with `verilator --binary --timing`
  plus the DPI source files from the same commit
- A formal property that can be reframed as a simulation assertion

**Only write a custom testbench as a last resort** when no official DV exists
for the changed module at all. Custom (AI-generated) testbenches are fragile,
may test the wrong thing, and undermine benchmark credibility. If you must
write one, document clearly why no official DV was usable.

**Verilator version note** — Many older repos were written for VCS/Questa and
may have guards like `` `ifndef VERILATOR `` or assume simulation semantics not
available in older Verilator. Modern Verilator (5.x) is highly compatible with
VCS when you use `--binary`, which generates its own `main()` and **implies
`--timing`** (so never write `--binary --timing` — `--binary` alone is
sufficient and correct).

**Patching official DV for Verilator** — minimal patches are acceptable:
- Remove `` `ifndef VERILATOR `` guard around clock/reset generators (`--binary`
  handles timing natively)
- Change `$finish()` to `$fatal(1)` on test failure for correct exit codes
- Add missing `inout` port drivers for ports the C++ top used to drive
Store the patch inline in the runner script (via `python3 -c` or `sed`) so the
official source file is never modified in-place. Both the DV C++ model and the
RTL must come from the **same checked-out commit** so they stay consistent.

If even patching is too invasive and no DV exists, write a **minimal custom
Verilator testbench** and a runner script in `problems/<owner>/<repo>/`. The
runner script must:
- Source the shared env: `. "$SCRIPT_DIR/../../env.sh"`
- Resolve its own location with `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`
- Derive the repo path as `REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/<owner>/<repo>" && pwd)"`
- Resolve any input `TB_FILE` path to absolute **before** any `cd` that changes CWD

```bash
# Example compile-and-run inside the runner script:
verilator --binary --top-module tb_<fix_commit_8> \
  --Mdir /tmp/vbuild_<name> --Wno-fatal \
  <pkg.sv first, then RTL, then tb.sv>
timeout 30 /tmp/vbuild_<name>/Vtb_<fix_commit_8>
```

**IMPORTANT: The `--Mdir` build cache may use `/tmp`. Testbench source files
(`.sv`, `.sh`) MUST live permanently in `problems/<owner>/<repo>/` — never in
`/tmp`. Test/setup commands in JSON files must use relative paths only.**

### 2d. Verify the test runner at HEAD

Run the test command. It **must pass** at HEAD before mining commits.

If it fails:
- Read the error and attempt to fix the build/simulation setup (edit Makefile
  targets, missing flags, wrong file paths, etc.).
- Up to 3 attempts. If it still doesn't pass, skip this repo:

```bash
python python/mine_repo.py update-log \
  --repo-url "<url>" --reason "cannot run build"
```

If it passes, record the confirmed setup:

```bash
python python/mine_repo.py update-log \
  --repo-url "<url>" \
  --rtl-dir  "<rtl_dir>" \
  --dv-dir   "<dv_dir>" \
  --test-cmd "<test_cmd>"
```

---

## Phase 3 — Mine commits

```bash
python python/mine_repo.py list-candidates clones/<owner>/<repo_name> \
  --repo-url "<repo_url>" \
  --rtl-dir  "<rtl_dir>" \
  --dv-dir   "<dv_dir>"
```

This emits JSONL records — each with:
- `fix_commit`, `prev_commit`
- `commit_msg` (full message of the fix commit — already fetched)
- `rtl_files` (files that changed in RTL dir)
- `diff_lines` (total added+removed lines in RTL)
- `rtl_diff` (the full diff)

Coverage-only commits (`[fcov]`, `[cov]`, `[dv,fcov]`, etc.) are **filtered
out automatically** by the script and will not appear in the output.

**Quick triage** — before spending time on `try-commit`, scan each candidate's
`commit_msg` for obvious signals:
- Skip if the message describes only test infrastructure, linting, style, or
  naming changes (no behavioral RTL change)
- Prefer candidates whose message mentions a specific bug, incorrect value,
  missing feature, or RISC-V spec compliance issue

To inspect a candidate's full diff without checking out, `cd` into the clone
first (so `git show`/`git log` operate on that repo, not some arbitrary path).
**Never use `git -C <path>` — always `cd` first:**
```bash
cd clones/<owner>/<repo_name>
git log --oneline -- <rtl_files>
git show <fix_commit> -- <rtl_files>
cd -
```

**Keep `problems/log.csv` up to date as you walk commits.** After each batch of
candidates triaged (even if none were saved), update `commits_walked`:
```bash
python3 python/mine_repo.py update-log \
  --repo-url "<repo_url>" \
  --add-commits-walked <N>
```
This lets you resume later from a known position and gives an accurate picture
of coverage in the log.

---

## Phase 4 — Verify candidates (agent-assisted)

For each candidate record from Phase 3:

### 4a. Try the commit pair

```bash
python python/mine_repo.py try-commit clones/<owner>/<repo_name> \
  --repo-url    "<repo_url>" \
  --fix-commit  "<fix_commit>" \
  --prev-commit "<prev_commit>" \
  --rtl-dir     "<rtl_dir>" \
  --dv-dir      "<dv_dir>" \
  --test-cmd    "<test_cmd>" \
  <rtl_files...>
```

`<rtl_files...>` is a space-separated list of RTL paths, given as trailing
positional arguments.

The script:
1. Checks out `fix_commit` cleanly and runs the test (must pass).
2. Reverts `rtl_files` to `prev_commit` and runs the test again (must fail).
3. On success, saves `problems/<owner>/<repo_name>/<fix_commit>.json`.

The result JSON has `"outcome"` in `{success, skip, error}`. Log skips/errors
and move on.

### 4b. Handle compile/elaboration failures (agent-assisted)

If the test fails with a **compile or elaboration error** (not a runtime/assertion
failure) after reverting the RTL, the DV may reference new ports or signals
added by the fix. Make **only minimal** structural changes to allow compilation:

**Allowed fixes:**
- Add a port that the DV references but the reverted RTL doesn't have
  (stub it as `output logic <name>` or `input logic <name>` and tie to `'0`)
- Rename a signal/module that was renamed in the fix commit
- Add a missing parameter with a placeholder default

**Not allowed:**
- Fixing logic, behavior, or state machines
- Implementing missing features
- Changing timing or handshake logic

After each minimal fix, re-run the test. If compilation succeeds and the test
now fails at **runtime** (the assertion or simulation failure we want), proceed
to save the problem by running `try-commit` again.

If compile errors cannot be resolved with minimal changes in ≤ 3 attempts,
skip the candidate.

### 4c. Per-candidate testbenches

**Strongly prefer official DV** (see Phase 2c). Only fall back to a custom
testbench when no official DV exists for the changed module.

When a custom testbench is necessary, write a **focused testbench** that tests
only the behavior introduced by `fix_commit`. Pass it via the `--test-cmd`
override rather than modifying the shared testbench.

**Naming rule**: custom testbench files must be named after the fix commit
(first 8 chars) — `tb_<fix_commit_8>.sv` — not after the module. This makes
the association between testbench and problem unambiguous.

Store per-candidate testbenches alongside their problem instances under
`problems/<owner>/<repo_name>/` (never inside `clones/`, which is gitignored):
```
problems/<owner>/<repo_name>/
  <fix_commit>.json        # instance spec (SWE-bench style)
  run_tests.sh             # shared runner, reads TB_FILE env var
  run_tb_official.sh       # official DV runner (preferred)
  tb_<fix_commit_8>.sv     # focused single-candidate TB (last resort)
```

The `problems/env.sh` file at the top of `problems/` provides shared toolchain
discovery (riscv32/64-gcc, FuseSoC, oss-cad-suite, sv2v) plus cocotb-env
helpers (`dvbench_cocotb_make`, `dvbench_cocotb_pytest`). Source it from every
runner.

---

## Phase 5 — Iterate all repos from `./repos`

When called without arguments, process every non-blank, non-comment line in
`./repos` through Phases 1–4 in sequence. Comment lines start with `#`.

---

## Output summary

After processing, print a summary:
- Repos checked / viable / skipped
- Candidates found / problems saved
- Point the user to `problems/log.csv` for the full tracking table

---

## Suggesting new permissions

If you need to run a command not already covered by `.claude/settings.json`,
**propose adding it** to `.claude/settings.json` with a minimal-scope pattern
and ask the user to confirm before proceeding.

Rules for new permission patterns:
- **Scope to this project**: prefer commands that work by `cd`-ing into a
  subdirectory of this project first, rather than patterns with arbitrary paths.
  `Bash(git show *)` (works after `cd clones/…`) is acceptable;
  `Bash(git -C * show *)` (targets any path) is not.
- **No broad wildcards on destructive commands**: never propose `Bash(git checkout *)`,
  `Bash(git reset *)`, `Bash(rm *)`, etc.
- **One tool per permission**: don't bundle unrelated commands into a single
  `Bash(foo * && bar *)` pattern.
- **Document the reason**: when proposing, state which phase needs the command
  and why the existing permissions don't cover it.

---

## Saved problem JSON schema

Each saved `problems/<owner>/<repo>/<fix_commit>.json` contains:

| Field | Description |
|-------|-------------|
| `problem_id` | `<owner>/<repo>/<fix_commit>` |
| `fix_commit` | SHA of the commit that fixed the bug |
| `buggy_rtl_commit` | SHA of the parent (buggy state) |
| `fix_commit_msg` | Full commit message (title + body) |
| `description` | Same as `fix_commit_msg` — describes the bug to the LLM |
| `rtl_files_changed` | Files reverted to create the buggy state |
| `test_commands` | Command(s) to verify: exits 0 = solution passes, non-0 = buggy. Run from project root. |
| `rtl_diff` | The ground-truth fix diff |
| `rtl_diff_lines` | Added + removed lines (signal for task difficulty) |
