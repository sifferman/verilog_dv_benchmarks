#!/usr/bin/env bash
# Focused unit-test runner for wb2axip axilupsz WSTRB shift fix (4414539).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/ZipCPU/wb2axip" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_zipcpu_wb2axip_44145397
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_44145397 \
    -o V_axilupsz \
    "$REPO_DIR/rtl/skidbuffer.v" \
    "$REPO_DIR/rtl/sfifo.v" \
    "$REPO_DIR/rtl/axilupsz.v" \
    "$SCRIPT_DIR/tb_44145397.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_axilupsz"
