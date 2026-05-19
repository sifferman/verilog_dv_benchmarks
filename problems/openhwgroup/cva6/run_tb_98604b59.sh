#!/usr/bin/env bash
# Focused unit-test runner for cva6 MIP.SEIP RVS=0 fix (98604b59).
# Era C csr_regfile. cv32a6_embedded has RVU=0 (the bug path), and tw_o
# is a top-level module output so CvxifEn=1 doesn't gate it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_98604b59
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-LATCH -Wno-CASEINCOMPLETE \
    "+incdir+$SCRIPT_DIR" \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_csr_mip_seip_rvs0 \
    -o V_csr_regfile \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a60x_config_pkg.sv" \
    "$REPO_DIR/core/include/build_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/csr_regfile.sv" \
    "$SCRIPT_DIR/tb_98604b59.sv"

timeout 60 "$BUILD_DIR/obj_dir/V_csr_regfile"
