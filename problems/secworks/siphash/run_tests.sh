#!/usr/bin/env bash
# Build and run the secworks/siphash top-level testbench (tb_siphash) with
# iverilog. The TB prints "Tests failed:   NNNN" before $finish; we grep stdout
# to derive an exit code: zero failed means pass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/secworks/siphash" && pwd)"
RTL="$REPO_DIR/src/rtl"
TB="$REPO_DIR/src/tb"

BUILD="/tmp/dvbench_secworks_siphash"
rm -rf "$BUILD"
mkdir -p "$BUILD"

iverilog -Wall -o "$BUILD/sim" \
    "$TB/tb_siphash.v" \
    "$RTL/siphash.v" "$RTL/siphash_core.v"

LOG="$BUILD/sim.log"
timeout 120 vvp "$BUILD/sim" | tee "$LOG"

# Parse "Tests failed:   NNNN" — pass only when count is exactly 0000.
if grep -qE '^Tests failed:[[:space:]]+0000' "$LOG"; then
    echo "TEST PASSED"
    exit 0
fi
echo "TEST FAILED"
exit 1
