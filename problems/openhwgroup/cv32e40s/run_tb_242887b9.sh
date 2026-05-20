#!/usr/bin/env bash
# Focused unit-test runner for cv32e40s a_decoder lsu_size fix (242887b9).
# At this commit the file name is still rtl/cv32e40x_a_decoder.sv (pre-rename).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cv32e40s" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cv32e40s_242887b9
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cv32e40s_a_decoder_lsusize \
    -o V_a_decoder \
    "$REPO_DIR/rtl/include/cv32e40x_pkg.sv" \
    "$REPO_DIR/rtl/cv32e40x_a_decoder.sv" \
    "$SCRIPT_DIR/tb_242887b9.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_a_decoder"
