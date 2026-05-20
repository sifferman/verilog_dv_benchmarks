#!/usr/bin/env bash
# Focused runner for the alexforencich/verilog-axi `axi_adapter` testbench
# exercising the **wide-master to narrow-master** code path
# (S_DATA_WIDTH=32, M_DATA_WIDTH=8). The bundled cocotb test sweeps
# (un)aligned addresses with `length, offset, size = ...` permutations,
# which is the exact path broken by commit 211f674~ ("buggy" parent).
#
# Buggy parent: deadlocks during unaligned write/read bursts -> timeout.
# Fixed RTL: completes 25 cocotb tests in ~40s with PASS=25.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/alexforencich/verilog-axi" && pwd)"
TB_DIR="$REPO_DIR/tb/axi_adapter"

# Clean leftover sim_build from prior runs
env -u PYTHONPATH PATH="$PATH" make -C "$TB_DIR" SIM=icarus clean >/dev/null 2>&1 || true
rm -rf "$TB_DIR/sim_build"

# Hard wall-clock cap: HEAD finishes in ~40s; buggy parent deadlocks. Use 90s.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
set +e
timeout 90 env -u PYTHONPATH PATH="$PATH" make -C "$TB_DIR" SIM=icarus \
    PARAM_S_DATA_WIDTH=32 PARAM_M_DATA_WIDTH=8 \
    PARAM_S_STRB_WIDTH=4 PARAM_M_STRB_WIDTH=1 \
    > "$LOG" 2>&1
RC=$?
set -e
tail -40 "$LOG"

# Treat any non-zero make return as test failure, but explicitly require we
# saw the PASS=25 success marker.
if grep -qE 'TESTS=25 PASS=25 FAIL=0' "$LOG"; then
    exit 0
fi
echo "TEST FAILED (rc=$RC)"
exit 1
