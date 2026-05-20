#!/usr/bin/env bash
# Focused unit-test runner for serv_immdec signedness fix (b10a871).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/olofk/serv" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_olofk_serv_b10a8714
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_serv_immdec_signbit \
    -o V_immdec \
    "$REPO_DIR/rtl/serv_immdec.v" \
    "$SCRIPT_DIR/tb_b10a8714.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_immdec"
