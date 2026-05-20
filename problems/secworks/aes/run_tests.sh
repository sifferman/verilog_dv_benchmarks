#!/usr/bin/env bash
# Build and run the secworks/aes top-level testbench (tb_aes) with iverilog.
# tb_aes prints "*** All NN test cases completed successfully" on pass and
# "*** NN tests completed - MM test cases did not complete successfully." on
# fail, but always exits via $finish. We grep stdout to derive an exit code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/secworks/aes" && pwd)"
RTL="$REPO_DIR/src/rtl"
TB="$REPO_DIR/src/tb"

BUILD="/tmp/dvbench_secworks_aes"
rm -rf "$BUILD"
mkdir -p "$BUILD"

iverilog -Wall -o "$BUILD/sim" \
    "$TB/tb_aes.v" \
    "$RTL/aes.v" "$RTL/aes_core.v" \
    "$RTL/aes_key_mem.v" "$RTL/aes_sbox.v" "$RTL/aes_inv_sbox.v" \
    "$RTL/aes_encipher_block.v" "$RTL/aes_decipher_block.v"

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
