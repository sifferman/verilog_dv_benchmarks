# Generic harness for verilog_dv_benchmarks problems.
#
# Single problem:
#   make verify   PROBLEM=lowRISC/ibex/dbc2b6f5dc5384c38ebda9d7efa6b0cd51522a84
#   make solution PROBLEM=...   # check out the solution RTL, execute tests (expect PASS)
#   make buggy    PROBLEM=...   # revert RTL to the buggy commit, execute tests (expect FAIL)
#   make sandbox  PROBLEM=...   # materialize a buggy snapshot under sandboxes/ (POC)
#
# Whole dataset:
#   make verify-all                  # sequential
#   make verify-all WORKERS=4        # parallel (across distinct repos)
#
# Logs at logs/{problem_id}/{solution,buggy}.log + result.json.

PROBLEM ?=
MODE    ?= verify
WORKERS ?= 1

PY              := python3 python/verify_problem.py
PY_SANDBOX      := python3 python/prepare_sandbox.py
PY_TEST_SANDBOX := python3 python/test_sandboxes.py

.PHONY: verify solution buggy sandbox verify-all test-sandboxes test-sandboxes-all clean-logs

verify solution buggy:
	$(PY) --problem-id $(PROBLEM) --mode=$@

sandbox:
	$(PY_SANDBOX) --problem-id $(PROBLEM) --overwrite

verify-all:
	$(PY) --all --mode=$(MODE) --workers=$(WORKERS)

# Build a sandbox for one problem, run its verify wrapper, expect non-zero exit.
test-sandboxes:
	$(PY_TEST_SANDBOX) --problem-id $(PROBLEM)

# Same, across the whole dataset.
test-sandboxes-all:
	$(PY_TEST_SANDBOX) --all --workers=$(WORKERS)

clean-logs:
	rm -rf logs/
