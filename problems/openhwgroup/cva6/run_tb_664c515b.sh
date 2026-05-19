#!/usr/bin/env bash
# Focused unit-test runner for cva6 RV32 BCLRI bit-25 fix (664c515b).
# Era C (2025-01): parametric decoder. cv32a6_imac_sv32 -> RVB=1, IS_XLEN32=1,
# CvxifEn=0 so the BITMANIP RV32 path exercises the fix and ex.valid fires.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_664c515b
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    "+incdir+$SCRIPT_DIR" \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_bclri_bit25 \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imac_sv32_config_pkg.sv" \
    "$REPO_DIR/core/include/build_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_664c515b.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
