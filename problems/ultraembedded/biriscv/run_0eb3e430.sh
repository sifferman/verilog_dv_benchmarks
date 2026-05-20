#!/usr/bin/env bash
# Focused runner for biriscv 0eb3e43 (cycle-counter write bug).
#
# Builds the bundled icarus testbench (kept under problems/, so it's the same
# at every commit) plus the repo's src/core RTL at whatever the working tree
# is currently checked out to. The probe is a short rv32i program that writes
# 0 to CSR_MCYCLE and then reads it back after a fixed spin loop.
#
# Fixed RTL: write is ignored -> MCYCLE >= threshold -> probe prints PASS.
# Buggy RTL: write is honoured -> MCYCLE < threshold  -> probe prints FAIL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/ultraembedded/biriscv" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build_0eb3e430"
mkdir -p "$BUILD_DIR"

# 1) Assemble the focused probe into a raw binary loaded at 0x80000000.
"$DVBENCH_RISCV32_GCC" -x assembler-with-cpp -nostdlib -nostartfiles \
    -march=rv32i -mabi=ilp32 \
    -Wl,-Ttext=0x80000000 \
    "$SCRIPT_DIR/probe_0eb3e430.S" \
    -o "$BUILD_DIR/probe.elf"

riscv32-unknown-elf-objcopy -O binary -j .text \
    "$BUILD_DIR/probe.elf" "$BUILD_DIR/tcm.bin"

# 2) Compile the testbench: our TB harness + repo's src/core RTL.
SRCS=()
for v in "$REPO_DIR/src/core"/*.v; do
    SRCS+=("$v")
done
SRCS+=("$SCRIPT_DIR/tb_top_0eb3e430.v" \
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
    echo "RESULT: buggy RTL accepted CSR_MCYCLE write." >&2
    exit 1
fi
echo "RESULT: probe did not print PASS or FAIL." >&2
exit 2
