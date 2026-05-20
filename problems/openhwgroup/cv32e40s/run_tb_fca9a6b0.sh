#!/usr/bin/env bash
# Focused unit-test runner for cv32e40s compressed_decoder cm.lbu fix (fca9a6b0).
# At this commit the file name is still rtl/cv32e40x_compressed_decoder.sv (pre-rename).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cv32e40s" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cv32e40s_fca9a6b0
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cv32e40s_compressed_decoder_cmlbu \
    -o V_compressed_decoder \
    "$REPO_DIR/rtl/include/cv32e40x_pkg.sv" \
    "$REPO_DIR/rtl/cv32e40x_compressed_decoder.sv" \
    "$SCRIPT_DIR/tb_fca9a6b0.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_compressed_decoder"
