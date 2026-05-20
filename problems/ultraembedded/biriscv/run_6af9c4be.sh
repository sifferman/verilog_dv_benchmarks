#!/usr/bin/env bash
# Focused runner for biriscv 6af9c4b (SRET/MRET decoder split).
#
# Builds the iverilog testbench (shared with other biriscv problems but with
# SUPPORT_SUPER=1 to enable SEPC and SRET behaviour) plus the repo's src/core
# RTL. Probe writes distinct values to MEPC and SEPC, then executes `sret`.
#
# Fixed RTL: jumps to SEPC -> probe prints PASS -> exit 0.
# Buggy RTL: SRET decoded as MRET, jumps to MEPC -> probe prints FAIL -> exit 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/ultraembedded/biriscv" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build_6af9c4be"
mkdir -p "$BUILD_DIR"

# 1) Assemble the focused probe into a raw binary loaded at 0x80000000.
"$DVBENCH_RISCV32_GCC" -x assembler-with-cpp -nostdlib -nostartfiles \
    -march=rv32i_zicsr -mabi=ilp32 \
    -Wl,-Ttext=0x80000000 \
    "$SCRIPT_DIR/probe_6af9c4be.S" \
    -o "$BUILD_DIR/probe.elf"

riscv32-unknown-elf-objcopy -O binary -j .text \
    "$BUILD_DIR/probe.elf" "$BUILD_DIR/tcm.bin"

# 2) Compile the testbench: our TB harness + repo's src/core RTL.
SRCS=()
for v in "$REPO_DIR/src/core"/*.v; do
    SRCS+=("$v")
done
SRCS+=("$SCRIPT_DIR/tb_top_6af9c4be.v" \
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
    echo "RESULT: buggy RTL decoded SRET as MRET." >&2
    exit 1
fi
echo "RESULT: probe did not print PASS or FAIL." >&2
exit 2
