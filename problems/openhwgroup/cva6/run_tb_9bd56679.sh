#!/usr/bin/env bash
# Focused unit-test runner for cva6 ZEXT.H rs2-check fix (9bd56679).
# Era C (2024-04+): decoder takes parametric types. cv32a65x has RVB=1 in
# this era (cv32a6_imac_sv32 has RVB=0 here -> bug path not entered).
# cv32a65x has CvxifEn=1 so the TB peeks `dut.illegal_instr` directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_9bd56679
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    "+incdir+$SCRIPT_DIR" \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_zexth_rs2 \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a65x_config_pkg.sv" \
    "$REPO_DIR/core/include/build_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_9bd56679.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
