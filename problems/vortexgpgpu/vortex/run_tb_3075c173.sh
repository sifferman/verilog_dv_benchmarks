#!/usr/bin/env bash
# Focused unit-test runner for vortexgpgpu/vortex VX_onehot_encoder N=1 fix
# (commit 3075c173).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/vortexgpgpu/vortex" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_vortex_3075c173
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -DSIMULATION \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    +incdir+"$REPO_DIR/hw/rtl" \
    +incdir+"$REPO_DIR/hw/rtl/libs" \
    +incdir+"$REPO_DIR/hw/dpi" \
    --top-module tb_3075c173 \
    -o Vtb_3075c173 \
    "$REPO_DIR/hw/rtl/libs/VX_onehot_encoder.sv" \
    "$SCRIPT_DIR/tb_3075c173.sv"

timeout 30 "$BUILD_DIR/obj_dir/Vtb_3075c173"
