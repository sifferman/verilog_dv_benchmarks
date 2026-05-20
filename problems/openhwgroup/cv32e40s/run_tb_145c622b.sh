#!/usr/bin/env bash
# Focused unit-test runner for cv32e40s m_decoder div ZMMUL fix (145c622b).
# At this commit the file name is still rtl/cv32e40x_m_decoder.sv (pre-rename).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cv32e40s" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cv32e40s_145c622b
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cv32e40s_m_decoder_div_zmmul \
    -o V_m_decoder \
    "$REPO_DIR/rtl/include/cv32e40x_pkg.sv" \
    "$REPO_DIR/rtl/cv32e40x_m_decoder.sv" \
    "$SCRIPT_DIR/tb_145c622b.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_m_decoder"
