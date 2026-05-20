
# DV Bench

A benchmark of historical Verilog/SystemVerilog RTL bugs, each paired with a focused testbench that passes on the fix commit and fails on the buggy parent. Currently 100+ problems across several RISC-V cores, small IPs, peripherals, and bus controllers.

## Layout

```
problems/<owner>/<repo>/<commit>.json     problem metadata: commit SHAs, files, commands
problems/<owner>/<repo>/run_*.sh          per-problem testbench runner
python/verify_problem.py                  harness
.github/workflows/verify.yml              CI
```

## Running

Run a single problem (clones the repo if missing, runs solution and buggy modes):

```bash
make verify PROBLEM=lowRISC/ibex/dbc2b6f5dc5384c38ebda9d7efa6b0cd51522a84
```

Other modes:

```bash
make solution PROBLEM=...    # solution RTL only, expect PASS
make buggy    PROBLEM=...    # revert RTL to buggy commit, expect FAIL
make sandbox  PROBLEM=...    # materialize a buggy snapshot under sandboxes/
```

The whole dataset:

```bash
make verify-all              # sequential
make verify-all WORKERS=4    # parallel across repos
```

Logs to `logs/<problem_id>/{solution,buggy}.log` and `result.json`.

## Mining new problems

The `/mine` Claude Code skill walks a list of repos and proposes new problems. Source URLs come from one of:

- a GitHub repo / org / user URL passed as the argument
- a path to a newline-delimited file of URLs
- `./repos` (the default), one URL per line

```text
/mine https://github.com/<owner>/<repo>
/mine ./repos
```

Output: new `problems/<owner>/<repo>/<commit>.json` files and the matching `run_*.sh` runner, ready to feed back into `make verify`.
