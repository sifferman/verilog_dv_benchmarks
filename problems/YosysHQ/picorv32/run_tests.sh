#!/usr/bin/env bash
# Run picorv32's bundled testbench.v / testbench.vvp through iverilog+vvp.
# picorv32's own Makefile compiles testbench.v + picorv32.v, loads
# firmware/firmware.hex, runs with vvp -N.
#
# `$stop` on test mismatch -> non-zero vvp exit; `$finish` after ALL TESTS
# PASSED -> 0. So the Makefile's exit code is the test verdict directly.
#
# firmware/firmware.hex is rebuilt by make from the .S/.c sources using the
# riscv32-unknown-elf toolchain that env.sh puts on PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/YosysHQ/picorv32" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

if [ -z "${DVBENCH_RISCV32_GCC:-}" ]; then
    echo "picorv32 needs riscv32-unknown-elf-gcc; not found by env.sh" >&2
    exit 2
fi

rm -f "$REPO_DIR/testbench.vvp"
make -C "$REPO_DIR" test
