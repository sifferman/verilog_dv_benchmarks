#!/usr/bin/env bash
# biriscv runner: builds the bundled Icarus testbench (tb/tb_core_icarus)
# and runs the bundled test.elf. PASS = simulation finishes cleanly via
# CSR_SIM_CTRL_EXIT $finish AND we see all 10 numbered test labels in
# stdout AND no "Incorrect" string appears.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/ultraembedded/biriscv" && pwd)"

BUILD_DIR="/tmp/biriscv_build_$$"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$REPO_DIR/tb/tb_core_icarus"

OUT_LOG="$BUILD_DIR/out.log"
# Build & run via the bundled makefile. Note: do NOT `make clean` first —
# its rule rm -rf's $(BUILD_DIR), which would race with our $OUT_LOG.
if ! timeout 90 make BUILD_DIR="$BUILD_DIR/" >"$OUT_LOG" 2>&1; then
    cat "$OUT_LOG"
    echo "biriscv: build/sim failed (non-zero exit)" >&2
    exit 1
fi

cat "$OUT_LOG"

# Detect runtime PASS: all 10 numbered labels printed, no "Incorrect" string,
# and $finish was reached.
if grep -q "Incorrect" "$OUT_LOG"; then
    echo "biriscv: detected 'Incorrect' in trace -> FAIL" >&2
    exit 2
fi
if ! grep -q '\$finish called' "$OUT_LOG"; then
    echo "biriscv: simulation did not reach \$finish -> FAIL" >&2
    exit 3
fi
for label in \
    "1. Initialised data" \
    "2. Multiply" \
    "3. Divide" \
    "4. Shift left" \
    "5. Shift right" \
    "6. Shift right arithmetic" \
    "7. Signed comparision" \
    "8. Word access" \
    "9. Byte access" \
    "10. Comparision"
do
    if ! grep -qF "$label" "$OUT_LOG"; then
        echo "biriscv: missing label '$label' -> FAIL" >&2
        exit 4
    fi
done

echo "biriscv: PASS"
exit 0
