#!/usr/bin/env bash
# Focused unit-test runner for cva6 CPOPW/CLZW/CTZW funct fix (2a16c28f).
# Era C (2026-02): parametric decoder, RV64 only (W variants). Uses
# cv64a6_imafdc_sv39 (RV64, RVB=1, CvxifEn=1); TB peeks dut.illegal_instr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_2a16c28f
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    "+incdir+$SCRIPT_DIR" \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_cpopw_funct \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv64a6_imafdc_sv39_config_pkg.sv" \
    "$REPO_DIR/core/include/build_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_2a16c28f.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
