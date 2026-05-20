#!/usr/bin/env bash
# Focused unit-test runner for cv32e40p decoder SIMD imm6 fix (e11ee19).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cv32e40p" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cv32e40p_e11ee198
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cv32e40p_decoder_simd_imm6 \
    -o V_decoder \
    "$REPO_DIR/rtl/include/cv32e40p_pkg.sv" \
    "$REPO_DIR/rtl/include/cv32e40p_apu_core_pkg.sv" \
    "$REPO_DIR/rtl/include/cv32e40p_fpu_pkg.sv" \
    "$REPO_DIR/rtl/cv32e40p_decoder.sv" \
    "$SCRIPT_DIR/tb_e11ee198.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
