#!/usr/bin/env bash
# Focused unit-test runner for cva6 branch_unit tval fix (0e04a86b).
# Era 2026-03 (parametric types): branch_unit needs all type params. Use
# the cv32a6_ima_sv32_fpga config (CExtEn=0 -> RVC=0) so the misaligned
# target raises the exception this fix is about.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_0e04a86b
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    "+incdir+$REPO_DIR/core/include" \
    --top-module tb_cva6_branch_tval \
    -o V_branch_unit \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_ima_sv32_fpga_config_pkg.sv" \
    "$REPO_DIR/core/include/build_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/branch_unit.sv" \
    "$SCRIPT_DIR/tb_0e04a86b.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_branch_unit"
