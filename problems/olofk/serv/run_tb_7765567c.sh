#!/usr/bin/env bash
# Focused unit-test runner for serv_rf_if mem_rd gating fix (7765567).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/olofk/serv" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_olofk_serv_7765567c
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_serv_rf_if_mem_rd_gate \
    -o V_rf_if \
    "$REPO_DIR/rtl/serv_rf_if.v" \
    "$SCRIPT_DIR/tb_7765567c.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_rf_if"
