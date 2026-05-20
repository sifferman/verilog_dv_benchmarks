#!/usr/bin/env bash
# Build and run the secworks/cmac top-level testbench (tb_cmac) with iverilog.
# cmac instantiates the secworks/aes core, so we pull AES RTL from the sibling
# clones/secworks/aes checkout. The TB exits via $finish regardless of result,
# so we grep stdout to derive an exit code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/secworks/cmac" && pwd)"
AES_DIR="$(cd "$SCRIPT_DIR/../../../clones/secworks/aes" && pwd)"
RTL="$REPO_DIR/src/rtl"
TB="$REPO_DIR/src/tb"
AES_RTL="$AES_DIR/src/rtl"

BUILD="/tmp/dvbench_secworks_cmac"
rm -rf "$BUILD"
mkdir -p "$BUILD"

# Early commits had everything inside cmac.v; later commits split out
# cmac_core.v. Include it only if present so the runner works on both eras.
CORE_SRC=""
if [ -f "$RTL/cmac_core.v" ]; then
    CORE_SRC="$RTL/cmac_core.v"
fi

iverilog -Wall -o "$BUILD/sim" \
    "$TB/tb_cmac.v" \
    "$RTL/cmac.v" $CORE_SRC \
    "$AES_RTL/aes_core.v" "$AES_RTL/aes_key_mem.v" \
    "$AES_RTL/aes_sbox.v" "$AES_RTL/aes_inv_sbox.v" \
    "$AES_RTL/aes_encipher_block.v" "$AES_RTL/aes_decipher_block.v"

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
