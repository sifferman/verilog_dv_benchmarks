#!/usr/bin/env bash
# Focused unit-test runner for cva6 branch_unit not-taken-misalign fix
# (283177c2). Era B (pre-2024): branch_unit takes CVA6Cfg parameter,
# cva6_config_pkg::cva6_cfg is already a cva6_cfg_t struct.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_283177c2
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_branch_not_taken_misalign \
    -o V_branch_unit \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imac_sv32_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/branch_unit.sv" \
    "$SCRIPT_DIR/tb_283177c2.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_branch_unit"
