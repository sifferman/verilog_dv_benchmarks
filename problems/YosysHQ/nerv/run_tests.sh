#!/usr/bin/env bash
# Run YosysHQ/nerv's bundled testbench (iverilog + vvp).
# `make test` compiles nerv.sv with testbench.sv and runs vvp.
# A test mismatch -> $stop -> non-zero vvp exit; success -> $finish -> 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/YosysHQ/nerv" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

if [ -z "${DVBENCH_RISCV32_GCC:-}" ]; then
    echo "nerv needs riscv32-unknown-elf-gcc; not found by env.sh" >&2
    exit 2
fi
export TOOLCHAIN_PREFIX="riscv32-unknown-elf-"

rm -f "$REPO_DIR/testbench" "$REPO_DIR/firmware.hex" "$REPO_DIR/firmware.elf"
make -C "$REPO_DIR" test
