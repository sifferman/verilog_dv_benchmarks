#!/usr/bin/env bash
# Focused unit-test runner for vortexgpgpu/vortex VX_cyclic_arbiter fix
# (commit 6c1ee9bf).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/vortexgpgpu/vortex" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_vortex_6c1ee9bf
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -DSIMULATION \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    +incdir+"$REPO_DIR/hw/rtl" \
    +incdir+"$REPO_DIR/hw/rtl/libs" \
    +incdir+"$REPO_DIR/hw/dpi" \
    --top-module tb_6c1ee9bf \
    -o Vtb_6c1ee9bf \
    "$REPO_DIR/hw/rtl/libs/VX_priority_encoder.sv" \
    "$REPO_DIR/hw/rtl/libs/VX_cyclic_arbiter.sv" \
    "$SCRIPT_DIR/tb_6c1ee9bf.sv"

timeout 30 "$BUILD_DIR/obj_dir/Vtb_6c1ee9bf"
