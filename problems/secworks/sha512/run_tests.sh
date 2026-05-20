#!/usr/bin/env bash
# Build and run the secworks/sha512 core-level testbench (tb_sha512_core) with
# iverilog. The TB exits via $finish regardless of result, so we grep stdout to
# derive an exit code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/secworks/sha512" && pwd)"
RTL="$REPO_DIR/src/rtl"
TB="$REPO_DIR/src/tb"

BUILD="/tmp/dvbench_secworks_sha512"
rm -rf "$BUILD"
mkdir -p "$BUILD"

iverilog -Wall -o "$BUILD/sim" \
    "$TB/tb_sha512_core.v" \
    "$RTL/sha512_core.v" "$RTL/sha512_h_constants.v" \
    "$RTL/sha512_k_constants.v" "$RTL/sha512_w_mem.v"

LOG="$BUILD/sim.log"
timeout 120 vvp "$BUILD/sim" | tee "$LOG"

if grep -qE 'did not complete successfully' "$LOG"; then
    echo "TEST FAILED"
    exit 1
fi
if ! grep -qE 'completed successfully' "$LOG"; then
    echo "TEST FAILED: no success marker"
    exit 1
fi
echo "TEST PASSED"
exit 0
