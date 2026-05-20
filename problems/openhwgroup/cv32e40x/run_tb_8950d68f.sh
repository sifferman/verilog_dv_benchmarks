#!/usr/bin/env bash
# Focused unit-test runner for cv32e40x b_decoder zext.h rs2 check (8950d68).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cv32e40x" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cv32e40x_8950d68f
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cv32e40x_b_decoder_zexth_rs2 \
    -o V_b_decoder \
    "$REPO_DIR/rtl/include/cv32e40x_pkg.sv" \
    "$REPO_DIR/rtl/cv32e40x_b_decoder.sv" \
    "$SCRIPT_DIR/tb_8950d68f.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_b_decoder"
