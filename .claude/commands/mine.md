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
python scripts/mine_repo.py check-url "<url>"
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
git clone --filter=blob:none "<repo_url>" clones/<owner>__<repo_name>
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
python scripts/mine_repo.py update-log --repo-url "<url>" --reason "DV in separate repo"
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
make sim                                      # Makefile target in clone
fusesoc run --target=sim <core>               # FuseSoC
python -m pytest dv/                          # cocotb / pytest
bash clones/<owner>__<repo>__tb/run_tests.sh  # custom runner script
```

If the existing DV is too complex to run (requires licensed simulators, special
hardware, large external deps), write a **minimal custom Verilator testbench**
and a runner script in `clones/<owner>__<repo>__tb/`. The runner script must:
- Resolve its own location with `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`
- Derive the repo path as `REPO_DIR="$(cd "$SCRIPT_DIR/../<owner>__<repo>" && pwd)"`
- Resolve any input `TB_FILE` path to absolute **before** any `cd` that changes CWD

```bash
# Example compile-and-run inside the runner script:
verilator --binary --timing --top-module tb_<name> \
  --Mdir /tmp/vbuild_<name> --Wno-fatal \
  <pkg.sv first, then RTL, then tb.sv>
timeout 30 /tmp/vbuild_<name>/Vtb_<name>
```

**IMPORTANT: The `--Mdir` build cache may use `/tmp`. Testbench source files
(`.sv`, `.sh`) MUST live permanently in `clones/<owner>__<repo>__tb/` — never
in `/tmp`. Test/setup commands in JSON files must use relative paths only.**

### 2d. Verify the test runner at HEAD

Run the test command. It **must pass** at HEAD before mining commits.

If it fails:
- Read the error and attempt to fix the build/simulation setup (edit Makefile
  targets, missing flags, wrong file paths, etc.).
- Up to 3 attempts. If it still doesn't pass, skip this repo:

```bash
python scripts/mine_repo.py update-log \
  --repo-url "<url>" --reason "cannot run build"
```

If it passes, record the confirmed setup:

```bash
python scripts/mine_repo.py update-log \
  --repo-url "<url>" \
  --rtl-dir  "<rtl_dir>" \
  --dv-dir   "<dv_dir>" \
  --test-cmd "<test_cmd>"
```

---

## Phase 3 — Mine commits

```bash
python scripts/mine_repo.py list-candidates clones/<owner>__<repo_name> \
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
cd clones/<owner>__<repo_name>
git log --oneline -- <rtl_files>
git show <fix_commit> -- <rtl_files>
cd -
```

**Keep `data/log.csv` up to date as you walk commits.** After each batch of
candidates triaged (even if none were saved), update `commits_walked`:
```bash
python3 scripts/mine_repo.py update-log \
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
python scripts/mine_repo.py try-commit clones/<owner>__<repo_name> \
  --repo-url    "<repo_url>" \
  --fix-commit  "<fix_commit>" \
  --prev-commit "<prev_commit>" \
  --rtl-dir     "<rtl_dir>" \
  --dv-dir      "<dv_dir>" \
  --rtl-files   <rtl_files...> \
  --test-cmd    "<test_cmd>"
```

The script:
1. Checks out `fix_commit` cleanly and runs the test (must pass).
2. Reverts `rtl_files` to `prev_commit` and runs the test again (must fail).
3. On success, saves `data/<owner>/<repo_name>/<fix_commit>.json`.

The result JSON has `"outcome"` ∈ `{success, skip, error}`. Log skips/errors
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
to save the instance by running `try-commit` again.

If compile errors cannot be resolved with minimal changes in ≤ 3 attempts,
skip the candidate.

### 4c. Per-candidate testbenches

When the standard test command doesn't work for a specific commit pair
(e.g., the general TB tests a feature not yet present at `prev_commit`),
write a **focused testbench** that tests only the behavior introduced by
`fix_commit`. Pass it via the `--test-cmd` override rather than modifying the
shared testbench.

Store per-candidate testbenches alongside the shared assets (outside the clone):
```
clones/<owner>__<repo_name>__tb/
  run_tests.sh          # shared runner, reads TB_FILE env var
  tb_shared.sv          # general multi-test TB
  tb_<fix_commit_8>.sv  # focused single-candidate TB
```

---

## Phase 5 — Iterate all repos from `./repos`

When called without arguments, process every non-blank, non-comment line in
`./repos` through Phases 1–4 in sequence. Comment lines start with `#`.

---

## Output summary

After processing, print a summary:
- Repos checked / viable / skipped
- Candidates found / instances saved
- Point the user to `data/log.csv` for the full tracking table

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

## Saved instance JSON schema

Each saved `data/<owner>/<repo>/<fix_commit>.json` contains:

| Field | Description |
|-------|-------------|
| `instance_id` | `<owner>__<repo>__<fix_commit>` |
| `fix_commit` | SHA of the commit that fixed the bug |
| `buggy_rtl_commit` | SHA of the parent (buggy state) |
| `fix_commit_msg` | Full commit message (title + body) |
| `problem_statement` | Same as `fix_commit_msg` — describes the bug to the LLM |
| `rtl_files_changed` | Files reverted to create the buggy state |
| `test_commands` | Command(s) to verify: exits 0 = fixed, non-0 = buggy |
| `setup_commands` | Steps to reproduce the buggy state from scratch |
| `rtl_diff` | The ground-truth fix diff |
| `rtl_diff_lines` | Added + removed lines (signal for task difficulty) |
