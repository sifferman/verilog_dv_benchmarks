#!/usr/bin/env bash
# Focused runner for corundum commit edc59031 (rx_fifo / tx_fifo
# per-port status connection fix). Compiles a small wrapper TB around
# fpga/common/rtl/rx_fifo.v with PORTS=2 and confirms that the upper
# port's status_good_frame[1] strobes when a frame goes through port 1.
#
# Fixed RTL: PASSES (exit 0)
# Buggy RTL: FAILS  (exit 1 -- status_good_frame[1] is stuck at 0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/corundum/corundum" && pwd)"
BUILD="$(mktemp -d -t corundum_edc59031_XXXX)"
trap 'rm -rf "$BUILD"' EXIT

RTL_DIR="$REPO_DIR/fpga/common/rtl"
AXIS_RTL="$REPO_DIR/fpga/lib/eth/lib/axis/rtl"

# Compile with iverilog -- iverilog is what corundum's cocotb tbs target,
# and it tolerates the buggy code's port width mismatch (padding warning)
# which is the regime where the bug manifests.
iverilog \
    -g2005-sv \
    -o "$BUILD/sim" \
    -s tb_edc59031 \
    "$SCRIPT_DIR/tb_edc59031.sv" \
    "$RTL_DIR/rx_fifo.v" \
    "$AXIS_RTL/axis_fifo_adapter.v" \
    "$AXIS_RTL/axis_fifo.v" \
    "$AXIS_RTL/axis_adapter.v" \
    "$AXIS_RTL/axis_arb_mux.v" \
    "$AXIS_RTL/arbiter.v" \
    "$AXIS_RTL/priority_encoder.v" 2>&1 | tee "$BUILD/compile.log" | tail -20

if ! grep -q "^$BUILD/sim$" <(ls "$BUILD" 2>/dev/null) && [ ! -x "$BUILD/sim" ]; then
    echo "COMPILE FAILED"
    exit 1
fi

LOG="$BUILD/sim.log"
set +e
timeout 30 vvp -n "$BUILD/sim" > "$LOG" 2>&1
RC=$?
set -e
tail -20 "$LOG"

if grep -q "^PASS:" "$LOG"; then
    exit 0
fi
echo "TEST FAILED (rc=$RC)"
exit 1
