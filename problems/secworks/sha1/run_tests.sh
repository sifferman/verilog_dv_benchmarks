#!/usr/bin/env bash
# Build and run the secworks/sha1 core-level testbench (tb_sha1_core) with
# iverilog. The TB exits via $finish regardless of result, so we grep stdout to
# derive an exit code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/secworks/sha1" && pwd)"
RTL="$REPO_DIR/src/rtl"
TB="$REPO_DIR/src/tb"

BUILD="/tmp/dvbench_secworks_sha1"
rm -rf "$BUILD"
mkdir -p "$BUILD"

iverilog -Wall -o "$BUILD/sim" \
    "$TB/tb_sha1_core.v" \
    "$RTL/sha1_core.v" "$RTL/sha1_w_mem.v"

LOG="$BUILD/sim.log"
timeout 60 vvp "$BUILD/sim" | tee "$LOG"

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
