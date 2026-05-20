#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/common_cells fifo_v3 fall-through fix
# (4f099df -- "fifo_v3: Fix data output when pushing into empty fall-through FIFO").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/common_cells" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_common_cells_4f099df8
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    +incdir+"$REPO_DIR/include" \
    +define+COMMON_CELLS_ASSERTS_OFF \
    --top-module tb_4f099df8 \
    -o V_fifo_v3 \
    "$REPO_DIR/src/fifo_v3.sv" \
    "$SCRIPT_DIR/tb_4f099df8.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_fifo_v3"
