#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/riscv-dbg dmi_jtag_tap fix
# (d7b8670 -- "src: Fix wrong reset state for TAP after trst_ni").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/riscv-dbg" && pwd)"
TECH_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/tech_cells_generic" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_riscv_dbg_d7b86704
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_d7b86704 \
    -o V_dmi_jtag_tap \
    "$TECH_DIR/src/rtl/tc_clk.sv" \
    "$REPO_DIR/src/dmi_jtag_tap.sv" \
    "$SCRIPT_DIR/tb_d7b86704.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_dmi_jtag_tap"
