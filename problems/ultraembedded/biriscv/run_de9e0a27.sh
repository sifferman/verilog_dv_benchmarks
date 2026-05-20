#!/usr/bin/env bash
# Focused runner for biriscv de9e0a2 (ext_intr -> S-mode delegation).
#
# Drives ext_intr_i high in the TB while a M-mode probe configures
# mideleg[MEIP] and reads MIP. In the fix MIP[SEIP] is set; in the buggy
# parent MIP[MEIP] is set unconditionally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/ultraembedded/biriscv" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build_de9e0a27"
mkdir -p "$BUILD_DIR"

# 1) Assemble the focused probe into a raw binary loaded at 0x80000000.
"$DVBENCH_RISCV32_GCC" -x assembler-with-cpp -nostdlib -nostartfiles \
    -march=rv32i_zicsr -mabi=ilp32 \
    -Wl,-Ttext=0x80000000 \
    "$SCRIPT_DIR/probe_de9e0a27.S" \
    -o "$BUILD_DIR/probe.elf"

riscv32-unknown-elf-objcopy -O binary -j .text \
    "$BUILD_DIR/probe.elf" "$BUILD_DIR/tcm.bin"

# 2) Compile the testbench: our TB harness + repo's src/core RTL.
SRCS=()
for v in "$REPO_DIR/src/core"/*.v; do
    SRCS+=("$v")
done
SRCS+=("$SCRIPT_DIR/tb_top_de9e0a27.v" \
       "$SCRIPT_DIR/tcm_mem.v" \
       "$SCRIPT_DIR/tcm_mem_ram.v")

iverilog \
    -I"$REPO_DIR/src/core" -I"$SCRIPT_DIR" \
    -DTRACE=0 -Dverilog_sim \
    -o "$BUILD_DIR/sim.out" \
    "${SRCS[@]}"

# 3) Run the simulation.
OUTPUT=$(timeout 30 vvp "$BUILD_DIR/sim.out" "+tcm=$BUILD_DIR/tcm.bin" 2>&1 || true)
echo "$OUTPUT"

# 4) Decide pass/fail from probe output.
if echo "$OUTPUT" | grep -q "^PASS$"; then
    exit 0
fi
if echo "$OUTPUT" | grep -q "^FAIL$"; then
    echo "RESULT: buggy RTL ignored mideleg routing of ext_intr." >&2
    exit 1
fi
echo "RESULT: probe did not print PASS or FAIL." >&2
exit 2
