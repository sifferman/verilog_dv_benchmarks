#!/usr/bin/env bash
# Focused unit-test runner for cva6 misaligned-branch fix (2b339269).
# Era 2023-12: branch_unit takes CVA6Cfg parameter (cva6_cfg_t struct).
# ariane_pkg has hartinfo locally (no separate dm pkg compile needed);
# rvfi lives only in verif/ which we don't need for the focused unit test.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_2b339269
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_branch_misaligned \
    -o V_branch_unit \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_ima_sv32_fpga_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/branch_unit.sv" \
    "$SCRIPT_DIR/tb_2b339269.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_branch_unit"
