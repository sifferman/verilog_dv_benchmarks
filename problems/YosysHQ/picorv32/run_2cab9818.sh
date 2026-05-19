#!/usr/bin/env bash
# Runner for picorv32 signed-div-by-zero bug (fix 2cab981).
# Builds picorv32 with ENABLE_DIV=1 + ENABLE_PCPI=1 (via PARAM_ENABLE_DIV).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/YosysHQ/picorv32" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

if [ -z "${DVBENCH_RISCV32_GCC:-}" ]; then
    echo "needs riscv32-unknown-elf-gcc; not found by env.sh" >&2
    exit 2
fi
RISCV32_PREFIX="${DVBENCH_RISCV32_GCC%-gcc}"

BUILD_DIR=/tmp/vbuild_picorv32_2cab9818
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# rv32im so the assembler accepts `div`.
"$RISCV32_PREFIX-as" -march=rv32im \
    "$SCRIPT_DIR/probe_2cab9818.S" -o "$BUILD_DIR/probe.o"
"$RISCV32_PREFIX-ld" -m elf32lriscv -Ttext=0 --no-relax \
    "$BUILD_DIR/probe.o" -o "$BUILD_DIR/probe.elf"
"$RISCV32_PREFIX-objcopy" -O binary -j .text \
    "$BUILD_DIR/probe.elf" "$BUILD_DIR/probe.bin"

verilator --binary --timing -Wno-fatal \
    --Mdir "$BUILD_DIR/obj_dir" \
    -CFLAGS "-std=c++17" \
    +define+PARAM_ENABLE_DIV \
    --top-module run_instructions \
    -o Vrun_instructions \
    "$REPO_DIR/picorv32.v" \
    "$SCRIPT_DIR/run_instructions.sv" \
    "$SCRIPT_DIR/run_instructions.cpp"

PROBE_BIN="$BUILD_DIR/probe.bin" \
EXPECTED_VALUE=0xFFFFFFFF \
    timeout 30 "$BUILD_DIR/obj_dir/Vrun_instructions"
