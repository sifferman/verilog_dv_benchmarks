# Benchmarking LLMs on DV Bench

How well can LLMs from different providers (Anthropic, OpenAI, ...) solve our
Verilog RTL bugs, and *how efficiently*? This doc describes the evaluation
framework — heavily borrowed from [SWE-bench](https://www.swebench.com/), with
one explicit twist: a model that fixes the bug with fewer tokens should
visibly win, not tie.

## Goal

For each `(model, problem)` pair, record:

- **Resolved?** boolean — does the model's patch make `make verify` pass?
- **Tokens** — input, cached, output, broken out per turn and summed.
- **Wall time** and **dollars** — derived from tokens × provider pricing.

Aggregate into two headline metrics:

1. **% Resolved** — fraction of the 95 problems the model fixed.
2. **Token-efficiency AUC** — cumulative-resolved vs. cumulative-tokens curve,
   normalized to [0, 1]. A model that hits 80% resolved at 200K tokens beats
   one that hits 80% resolved at 800K tokens, even though the resolve rate is
   identical. Pattern borrowed from [SWE-Effi](https://arxiv.org/abs/2509.09853).

## What we borrow from SWE-bench

SWE-bench has worked out the contract between *dataset*, *agent*, and *harness*
better than anything else in the space. We mirror it where we can:

| SWE-bench concept                              | DV Bench analog                                                |
| ---------------------------------------------- | -------------------------------------------------------------- |
| `instance_id`                                  | `problem_id` = `<owner>/<repo>/<fix_commit>`                   |
| `base_commit`                                  | `buggy_rtl_commit`                                             |
| `patch` (gold, hidden)                         | `rtl_diff` in the problem JSON (never copied into the sandbox) |
| `problem_statement`                            | `description` in the problem JSON (commit message)             |
| `test_patch` (hidden, applied post-edit)       | runner+TB visible in sandbox, but comment-scrubbed (see below) |
| `FAIL_TO_PASS` + `PASS_TO_PASS`                | the runner's exit code: `0` = resolved                         |
| Predictions JSONL (`{instance_id, model_patch}`) | same — one line per problem                                  |
| `swebench.harness.run_evaluation`              | `python3 benchmarks/evaluate.py`                               |

What we **don't** borrow:

- Docker-per-instance. Our toolchain is heavier (Verilator, oss-cad-suite,
  riscv32-gcc) and the existing harness in `python/verify_problem.py` already
  uses per-repo locking and `clones/` reuse. Stick with that; revisit if we
  need stricter isolation.
- The `FAIL_TO_PASS` / `PASS_TO_PASS` split. Our runners are single-target —
  one runner exits 0 iff the bug is fixed AND no regressions. Good enough.

## Problem format

Already in place. `problems/<owner>/<repo>/<fix_commit>.json`:

```json
{
  "problem_id": "lowRISC/ibex/dbc2b6f5...",
  "description": "src: Fix CSR write ...",        // shown to the model
  "buggy_rtl_commit": "...",                      // checkout starting point
  "rtl_files_changed": ["..."],                   // files the agent may edit
  "rtl_diff": "...",                              // gold patch — never copied into the sandbox
  "test_commands": ["bash problems/.../run_*.sh"] // runner — visible but scrubbed
}
```

## Threat model

**Assume the LLM can see everything in the sandbox.** No clever hiding of test
files — anyone who looked closely at `problems/` could read them, and any
sandbox restriction the agent could bypass with a `find` or `cat` is theatre.
Instead: harden what we put *into* the sandbox.

Concretely, three things must not be readable from inside the sandbox:

1. **The `.git` directory of the cloned repo.** Otherwise `git log --all`
   trivially names the fix commit, and `git diff buggy fix -- <files>` hands
   over the gold patch. Move it out of the sandbox (or set `GIT_DIR` to a
   path outside) when materializing.
2. **The full problem JSON** — it contains `rtl_diff` and the full commit
   message including its title (often "fix X by doing Y"). Copy only
   `description` into a `PROBLEM.md` in the sandbox; never the JSON itself.
3. **Comments in testbench/runner files.** Our own per-problem testbenches
   tend to narrate the bug — e.g. `# Focused runner for VeeR EL2 PMPCFG WARL
   fix (commit 2231e49).` or `# Buggy v0.6 csr_regfile accepted CSRRW to
   CSR_MCYCLE.` A comment-scrub pass over copied `.sv` / `.v` / `.cpp` /
   `.sh` files strips this without us having to audit every testbench by
   hand. The source-of-truth files in `problems/` keep their comments; only
   the sandbox copy is scrubbed.

What the LLM CAN see, by design:
- The repo files at `fix_commit`, with `rtl_files_changed` reverted to
  `buggy_rtl_commit`.
- The testbench source (`.sv` / `.cpp`) — without comments. If the
  un-commented test code itself reveals the bug ("expected value 0xCAFE0001
  after instruction X"), that's fine. The test is the oracle; reading it is
  what a developer would do too.
- `PROBLEM.md` — the bug description we'd give a human, minus the fix.
- A `make verify` style entry point.

What the LLM CAN'T do, post-hardening:
- `git log` / `git show` (no `.git`).
- `grep -r "rtl_diff"` anywhere — it's not in the sandbox.
- Read `<fix_commit>.json`, `MEMORY.md`, or any other harness-side file —
  the sandbox is a tmpdir, not a view of the repo root.

## Agent contract

The agent is **whatever loop wraps the LLM** — Claude Code with this repo,
OpenAI Codex CLI, Aider, a custom Python script, etc. The contract is:

**Input** (per problem): one sandbox directory, materialized fresh per run by
the harness (see "Sandbox layout" below). The agent has read/write access to
it and may run any shell command. No network access (we can't trust an agent
not to `curl` GitHub for the fix commit otherwise).

**Output** (one JSONL line per problem):

```json
{
  "problem_id": "lowRISC/ibex/dbc2b6f5...",
  "model_name": "claude-opus-4-7",
  "model_patch": "diff --git a/rtl/... \n--- \n+++ \n@@ ...",
  "usage": {
    "input_tokens": 18234,
    "cached_input_tokens": 12001,
    "output_tokens": 3492,
    "turns": 7,
    "wall_time_s": 41.2
  }
}
```

`model_patch` is a unified diff against `buggy_rtl_commit`, restricted to
files in `rtl_files_changed`. The harness rejects patches that touch other
files (this is the equivalent of SWE-bench reapplying `test_patch` to
prevent test-gaming).

## Sandbox layout

`benchmarks/prepare_sandbox.py` builds this layout per problem, in a tmpdir:

```
<tmpdir>/sandbox/
  PROBLEM.md                 # just `description` — no diff, no fix-commit SHA
  rtl/                       # repo at fix_commit, rtl_files_changed reverted
    ...                      # NO .git inside
  testbench/                 # copy of problems/<owner>/<repo>/*.sv|*.cpp|*.sh
    run.sh                   # scrubbed copy of the runner — no comments
    tb_*.sv                  # scrubbed
  verify                     # thin wrapper: `cd $sandbox && ./testbench/run.sh`
```

Harness-side, parallel to the sandbox:

```
<tmpdir>/oracle/
  problem.json               # the full problem JSON, used only by the harness
  rtl-baseline/              # untouched repo at fix_commit (the comparison point)
```

Scrubbing rules (applied to every file under `testbench/`):

**Pass 1 — strip comments.** Tokenizer-aware so we don't mangle string
literals containing `//`:
- `.sv` / `.v`: `verible-verilog-preprocessor strip-comments <file>`
  (verible replaces comments with whitespace; leaves string literals alone).
- `.cpp` / `.h`: small libclang or hand-rolled C tokenizer pass.
- `.sh`: drop any line whose first non-whitespace char is `#`, *except*
  preserve a `#!/usr/bin/env bash` shebang on line 1.

**Pass 2 — neutralize PASS/FAIL strings.** Comment-scrub catches 83% of
fix-revealing language in our testbenches, but the remaining 17% lives in
runtime diagnostic strings — `$display("FAIL: WSTRB shift wrong — got
0x%02h, expected 0xF0", m_wstrb)` or `$fatal(1, "apb_timer prescaler bug --
counts too slowly")`. The LLM reading the source sees the bug description
in plain English. Rewrite these:
- For SV: replace string-literal arguments of `$display` / `$fatal` /
  `$error` / `$warning` / `$info` with empty strings (or with `"PASS"` /
  `"FAIL"` when the test branch makes the polarity obvious).
- For shell: replace string-literal arguments of `echo` / `printf` that
  contain "bug", "fix", "buggy", or other fix-revealing tokens.

Identifiers that look fix-revealing (e.g. `wire expected_after_mcycle_write_ignored;`)
are rare in practice — the audit found one cluster (`logic illegal;` in
ibex CSR TBs, which is legitimate domain vocab). Spot-fix in source where
egregious; don't try to scrub at sandbox-build time.

The scrub is idempotent and runs per-sandbox-build, so adding new comments
or diagnostic strings to testbenches in `problems/` is safe — they just
won't appear in the sandbox.

## Harness

`benchmarks/evaluate.py` consumes one predictions JSONL and produces one
scores JSON:

```bash
python3 benchmarks/evaluate.py \
    --predictions benchmarks/predictions/claude-opus-4-7.jsonl \
    --out         benchmarks/scores/claude-opus-4-7.json
```

For each prediction:

1. Acquire the per-repo lock (reuses `python/dvbench/verifier.py` machinery).
2. Reset the clone to `fix_commit`, then revert `rtl_files_changed` to
   `buggy_rtl_commit` — same starting point the agent saw.
3. Apply `model_patch` with `git apply`. On rejection, mark as `error:patch_failed`.
4. Reject any patch that modifies files outside `rtl_files_changed`.
5. Run `test_commands`. Exit 0 → `resolved`. Non-zero → `unresolved`.
6. Write per-problem result to `benchmarks/runs/<run_id>/<problem_id>.json`
   (logs included for triage).

Scores JSON shape:

```json
{
  "model_name": "claude-opus-4-7",
  "run_id": "2026-05-20T12-30-00",
  "total":     95,
  "resolved":  82,
  "unresolved": 11,
  "error":      2,
  "tokens": { "input": 1342103, "cached_input": 884221, "output": 162449 },
  "cost_usd": 12.83,
  "by_problem": { /* per-problem details for plotting */ }
}
```

## Metrics & plots

`benchmarks/plot.py` reads N scores JSONs and emits:

**1. Resolve-rate bar chart** — one bar per model, sorted by % Resolved.
This is the SWE-bench leaderboard analog and answers "did it work?"

**2. Token-efficiency curve** — cumulative resolved (Y) vs. cumulative output
tokens (X), one line per model. Sort each model's problems by tokens-spent
ascending, then accumulate. The model whose curve climbs fastest is the most
token-efficient. Report **AUC** on the same chart as a number — a model that
solves 80/95 problems in 200K total tokens has higher AUC than one that solves
80/95 in 800K, even though both report `82% resolved`.

**3. Cost-efficiency curve** — same shape, X-axis in USD instead of tokens.
Tokens are provider-agnostic; dollars depend on pricing. Both views matter:
the token graph compares "model intelligence," the dollar graph compares
"what you'd actually pay this quarter."

**4. Per-problem heatmap** — rows = models, columns = problems, cell = green
(resolved) / red / gray. Useful for spotting problems no model can solve
(those are probably bad benchmarks or need richer context).

## Cross-provider plan

You have Anthropic+ChatGPT subscriptions. The agent layer should be a thin
shim so the same loop runs against either provider's API; only the model name
and pricing table change.

Minimal model matrix to start:

| Provider  | Model ID                  | Notes                                       |
| --------- | ------------------------- | ------------------------------------------- |
| Anthropic | `claude-opus-4-8`         | Frontier; reasoning + tool use              |
| Anthropic | `claude-sonnet-4-6`       | Workhorse                                   |
| Anthropic | `claude-haiku-4-5`        | Cheap; baseline                             |
| OpenAI    | `gpt-5.5`                 | Frontier                                    |
| OpenAI    | `gpt-5`                   | Prior-gen frontier                          |
| OpenAI    | `o-series` (reasoning)    | Throughput differs; report tokens honestly  |

Token accounting from each provider's API:

- Anthropic: `response.usage.input_tokens`, `cache_read_input_tokens`,
  `cache_creation_input_tokens`, `output_tokens`. Pricing differs across the
  three input categories — don't sum naively.
- OpenAI: `response.usage.prompt_tokens`, `completion_tokens`,
  `prompt_tokens_details.cached_tokens` (for prompt caching).

Pricing table goes in `benchmarks/pricing.toml` and is the only thing that
needs updating when providers change rates.

## Implementation phases

**Phase 1 — Harness skeleton (no agent yet).**
Write `benchmarks/evaluate.py` that consumes a JSONL of *gold* patches (we
already have these in `rtl_diff` for every problem). Confirm we score 95/95
resolved when fed the gold patches — sanity check that the harness itself is
correct before any model gets blamed for our bugs.

**Phase 2 — Single-shot agent.**
One LLM call per problem: prompt = `description` + the buggy RTL files +
"return a unified diff." No tool use, no iteration. Establishes the cheap
baseline and surfaces tokenization quirks. Worth running before adding
complexity.

**Phase 3 — Tool-using agent.**
Give the model the ability to read files and run `make verify`. Loop until
the verifier passes, the model gives up, or a token budget (e.g. 500K) is
exhausted. This is where reasoning-heavy models start earning their cost.

**Phase 4 — Plots & leaderboard.**
`benchmarks/plot.py` for the four charts above. A markdown summary that
checks into the repo so the leaderboard updates with each rerun.

## Open questions

- **Comment-scrub correctness.** A regex strip will mangle SV string literals
  containing `//`. Use `verible-verilog-format --strip-comments` (or
  equivalent tokenizer-aware tool) for `.sv`/`.v`. Validate with a CI check
  that the scrubbed testbench still compiles and the gold patch still scores
  resolved — same Phase-1 sanity run, against scrubbed sandboxes instead of
  the raw repo.
- **Variable / signal names that hint.** Comment-scrubbing won't help if the
  testbench defines `wire expected_after_mcycle_write_ignored;`. Spot-check
  the testbench names in `problems/<owner>/<repo>/tb_*.sv` for fix-revealing
  identifiers; rename in source where they're egregious.
- **Models that don't expose a token count.** Some providers return only
  billable tokens, not the raw split. Document the limitation per model;
  don't fudge.
- **What counts as a "turn"?** For tool-using runs, defining `turns` matters
  for fairness. Recommended: count one turn per LLM response from the
  agent's perspective, regardless of how many tool calls happen in parallel.

## References

- [SWE-bench](https://www.swebench.com/) — problem format, harness, leaderboard
- [SWE-bench paper (arXiv 2310.06770)](https://arxiv.org/abs/2310.06770)
- [SWE-bench Verified](https://www.swebench.com/verified.html) — the
  human-curated 500-instance subset; what serious evaluations target
- [SWE-Effi (arXiv 2509.09853)](https://arxiv.org/abs/2509.09853) — the
  resolved-vs-tokens AUC metric we're copying
- [SWE-rebench](https://swe-rebench.com/) — example leaderboard breaking out
  input/cache/output tokens per model
