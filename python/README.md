# python/dvbench/ — problem mining + verification

Two CLI tools for building and validating a Verilog/SV LLM debugging benchmark:

- **`python/mine_repo.py`** — mine GitHub repos for buggy → fixed commit pairs and save them as benchmark problems.
- **`python/verify_problem.py`** — re-run a saved problem to confirm the solution still passes and the buggy state still fails.

See `requirements.txt` for dependencies. For implementation internals, see `TRACE.md`.

## Quick start

### Mine a repo for problems

```bash
# 1. Check viability of a GitHub URL (license, HDL %, commit count)
python python/mine_repo.py check-url https://github.com/lowRISC/ibex

# 2. Walk commit history for candidate (prev → fix) pairs
python python/mine_repo.py list-candidates clones/lowRISC/ibex \
    --repo-url https://github.com/lowRISC/ibex \
    --rtl-dir rtl/ --dv-dir dv/cs_registers

# 3. Verify one candidate: test passes at fix, fails at prev
python python/mine_repo.py try-commit clones/lowRISC/ibex \
    --repo-url https://github.com/lowRISC/ibex \
    --fix-commit <sha> --prev-commit <prev_sha> \
    --rtl-dir rtl/ --dv-dir dv/cs_registers \
    --test-cmd "tb/lowRISC/ibex/run_tb_cs_registers.sh" \
    -- rtl/ibex_cs_registers.sv
```

The full mining flow with LLM-assisted triage is automated by the `/mine` slash command (see `.claude/commands/mine.md`).

### Verify saved problems

```bash
# One problem
python python/verify_problem.py --problem-id lowRISC/ibex/<sha>

# All problems, in parallel
python python/verify_problem.py --all --workers 4

# Only the solution phase (skip buggy verification)
python python/verify_problem.py --all --mode solution
```

Per problem, the harness writes `logs/{problem_id}/result.json` plus the raw test output, and prints a summary table at the end.

## Output artifacts

| Path | Written by | Contents |
|---|---|---|
| `problems/{owner}/{repo}/{sha}.json` | `try-commit` | One benchmark problem (fix commit, buggy state, test commands, rtl diff) |
| `problems/log.csv` | all `mine_repo` subcommands | Per-repo tracking: viability, walk progress, commits used |
| `logs/{problem_id}/result.json` | `verify_problem` | Verification verdict + exit codes |
| `logs/{problem_id}/solution.log` | `verify_problem` | Test output at fix commit |
| `logs/{problem_id}/buggy.log` | `verify_problem` | Test output with RTL reverted to prev |
| `clones/{owner}/{repo}/` | first git clone | Local mirror (gitignored) |

## CLI reference

### `mine_repo.py`

| Subcommand | Purpose |
|---|---|
| `check-url <github_url>` | Resolve a repo/org/user URL, screen by license + language + commit count, log to CSV |
| `list-candidates <clone_dir>` | Emit JSONL of (prev → fix) commit pairs that touched both RTL and DV |
| `try-commit <clone_dir>` | Verify one candidate end-to-end and save its problem JSON |
| `update-log` | Upsert one row in `problems/log.csv` |

Pass `-h` / `--help` to any subcommand for the full flag list.

### `verify_problem.py`

One command with three modes:

| `--mode` | What it checks |
|---|---|
| `verify` (default) | solution passes AND buggy state fails |
| `solution` | solution passes |
| `buggy` | buggy state fails |

`--workers N` runs problems in parallel; per-repo `fcntl` locks serialize workers that share a clone directory.

## External contract (don't break)

- CLI flag names, subcommand names, Makefile target names
- JSONL output keys for `mine_repo` subcommands
- `problems/log.csv` column order
- `problems/{owner}/{repo}/{sha}.json` schema (`problem_id`, `description`, …)
- `logs/{problem_id}/result.json` schema (`problem_id`, `mode`, `solution_exit_code`, `buggy_exit_code`, `result`, `duration_s`)
