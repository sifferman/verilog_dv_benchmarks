# /fix-ci — Inspect the latest GitHub Actions run and fix any failures

## Argument

`$ARGUMENTS` — optional. One of:
- Empty → use the most recent run of the `verify.yml` workflow on the current branch
- A run ID (e.g. `12345678`) → use that specific run
- A branch name → most recent run on that branch

---

## Prereqs

- `$GITHUB_TOKEN` must be set in the environment (a personal access token with
  `actions:read` scope). The skill uses `curl` against the GitHub REST API —
  `gh` CLI is **not** required.
- `curl -L` is needed because the REST API issues a 301 from the repo path to
  its numeric ID and a 302 from the logs endpoint to a signed download URL.

The owner/repo for `origin`:

```bash
REPO_SLUG="$(git remote get-url origin | sed -E 's#.*github\.com[:/](.+/.+)\.git#\1#')"
# e.g. sifferman/dvbench
```

---

## Phase 1 — Fetch the latest run

```bash
curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_SLUG/actions/workflows/verify.yml/runs?per_page=1" \
    | python3 -c "
import json, sys
r = json.load(sys.stdin)['workflow_runs'][0]
for k in ('id','status','conclusion','head_branch','display_title','created_at','html_url'):
    print(f'{k}: {r[k]}')
"
```

If `$ARGUMENTS` is a run ID, skip this and use it directly. If it's a branch,
add `&branch=<name>` to the query. Record `id` as `RUN_ID`.

Decide based on `status` / `conclusion`:
- `completed` + `success` → nothing to fix; report and stop.
- `completed` + `failure` / `timed_out` / `cancelled` → proceed to Phase 2.
- `in_progress` / `queued` → tell the user the run isn't done; offer to wait or
  inspect once finished. Do **not** spin in a poll loop.

---

## Phase 2 — Pull the log

The logs endpoint returns a zip of per-step `.txt` files:

```bash
RUN_ID=<from phase 1>
curl -sL -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO_SLUG/actions/runs/$RUN_ID/logs" \
    -o /tmp/ci-logs.zip
unzip -p /tmp/ci-logs.zip '*VerifyAll*Run make verify-all*.txt' > ci.log 2>/dev/null \
    || unzip -p /tmp/ci-logs.zip '0_VerifyAll.txt' > ci.log
wc -l ci.log
```

The combined `0_VerifyAll.txt` member always exists and contains every step;
prefer the targeted `7_Run make verify-all` step file when present — it's
~95% smaller. `ci.log` is gitignored by convention; overwrite it freely.

---

## Phase 3 — Triage failures

For this repo the relevant signals are:

```bash
# 1. Verifier's own summary table — the authoritative list of failing problems:
grep -E "did_not_pass|did_not_fail|solution_failed_build|buggy_failed_build|Summary" ci.log

# 2. Workflow-level fatal errors (apt/pip install, toolchain download, etc.):
grep -E "##\[error|E: Unable|ERROR: Could not|fatal:|404|No such file" ci.log
```

Group failures by **root cause**, not by problem ID — one root cause usually
explains several rows in the summary table (e.g. a missing system package
breaks every problem in one repo family).

For each failing problem, jump to its invocation in the log to read the actual
error:

```bash
grep -n "<problem_short_sha>" ci.log | head
```

Then `Read` the surrounding lines to see compile/runtime output.

---

## Phase 4 — Fix

Match each root cause to the right file to edit:

| Symptom | Fix location |
|---|---|
| Missing apt package (`Can't locate Foo.pm`, `command not found`) | `.github/workflows/verify.yml` apt install step |
| Missing Python module in oss-cad-suite (`ModuleNotFoundError`) | workflow's `tabbypy3 -m pip install --no-deps …` line |
| Missing Python module in system Python (pytest-driven cocotb) | workflow's `pip3 install` line |
| Missing git submodule of a cloned repo | source `problems/env.sh` and call `dvbench_init_submodule "$REPO_DIR" <path>` in the run script |
| Missing sibling repo (referenced by a runner but never cloned) | `dvbench_ensure_sibling_clone "$CLONES_ROOT" <owner> <repo>` |
| Toolchain rejected an instruction extension (`extension 'zicsr' required`) | bump `-march=` in the affected `run_*.sh` |
| Cocotb test timed out but otherwise passed | bump the `timeout <s>` in the affected `run_*.sh` |
| Buggy RTL not actually failing (`buggy_did_not_fail`) | the bundled DV doesn't exercise the bug — consider a focused probe (see `/mine` Phase 4.5) or drop the problem |

Make the **smallest fix that addresses the root cause**. Do not refactor the
harness or rename problems while you're in here.

---

## Phase 5 — Verify locally

For every problem whose runner you touched (or that was failing for a reason
you believe is fixed), re-run it locally before pushing:

```bash
python3 python/verify_problem.py --problem-id <owner>/<repo>/<full_sha> --mode=verify
```

Expect `verified` in the result column. If `solution_did_not_pass` persists
locally, the fix isn't complete — diagnose further before claiming success.

For workflow-only changes (apt/pip), you generally can't reproduce CI locally;
say so explicitly and note that CI re-run is the validation step.

---

## Phase 6 — Report

Print a short summary:
- Run ID inspected, branch, conclusion
- Number of failing problems, grouped by root cause
- Files changed (with brief description per file)
- Which problems were re-verified locally vs. left for CI

Do not commit or push — the user will review the diff and commit themselves.

---

## Notes

- Never edit RTL inside `clones/` — those are upstream sources. Fixes always
  land in `problems/<owner>/<repo>/`, `problems/env.sh`, or
  `.github/workflows/verify.yml`.
- Don't silence a real test failure by widening the pass criterion. If a
  testbench legitimately catches a bug, the fix is in the RTL/probe/runner —
  not in loosening `grep -q PASS`.
- Failures in problems marked `buggy` mode are *expected* — those tests are
  designed to fail on the buggy RTL. Only `solution_*` and `buggy_did_not_fail`
  rows are real regressions.
