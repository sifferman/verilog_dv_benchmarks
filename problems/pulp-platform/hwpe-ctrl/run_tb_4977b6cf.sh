#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/hwpe-ctrl
# hwpe_ctrl_regfile_ff 1-cycle latency fix (commit 4977b6c).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/hwpe-ctrl" && pwd)"
TECH_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/tech_cells_generic" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_hwpe_ctrl_4977b6cf
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_4977b6cf \
    -o V_regfile_ff \
    "$TECH_DIR/src/rtl/tc_clk.sv" \
    "$REPO_DIR/rtl/hwpe_ctrl_regfile_ff.sv" \
    "$SCRIPT_DIR/tb_4977b6cf.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_regfile_ff"
