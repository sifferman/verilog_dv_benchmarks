#!/usr/bin/env bash
# Focused runner for alexforencich/verilog-axis `axis_adapter` testbench in
# the S_KEEP_ENABLE=0 + upsize (M_BYTE_LANES > S_BYTE_LANES) configuration
# that exposes the tkeep handling bug fixed in commit c1c3dc0b.
#
# Default tb params use S=M=8 (bypass path) which never trips the bug.
# Here we set S_DATA=8 (S_KEEP_ENABLE=0) and M_DATA=16 (M_KEEP_ENABLE=1),
# matching the upsize path where buggy RTL clocked raw `s_axis_tkeep` (=0)
# into the output register instead of the all-ones default.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/alexforencich/verilog-axis" && pwd)"
TB_DIR="$REPO_DIR/tb/axis_adapter"

env -u PYTHONPATH PATH="$PATH" make -C "$TB_DIR" SIM=icarus clean >/dev/null 2>&1 || true
rm -rf "$TB_DIR/sim_build"

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
set +e
timeout 90 env -u PYTHONPATH PATH="$PATH" make -C "$TB_DIR" SIM=icarus \
    PARAM_S_DATA_WIDTH=8 PARAM_M_DATA_WIDTH=16 \
    PARAM_S_KEEP_ENABLE=0 PARAM_M_KEEP_ENABLE=1 \
    PARAM_S_KEEP_WIDTH=1 PARAM_M_KEEP_WIDTH=2 \
    > "$LOG" 2>&1
RC=$?
set -e
tail -30 "$LOG"

if grep -qE 'TESTS=[0-9]+ PASS=[0-9]+ FAIL=0 SKIP=0' "$LOG" && grep -qE 'TESTS=[1-9]' "$LOG"; then
    exit 0
fi
echo "TEST FAILED (rc=$RC)"
exit 1
