#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/common_cells delta_counter fix
# (554ebbc -- "delta_counter: Fix inverted reset").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/common_cells" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_common_cells_554ebbcd
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_554ebbcd \
    -o V_delta_counter \
    "$REPO_DIR/src/delta_counter.sv" \
    "$SCRIPT_DIR/tb_554ebbcd.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_delta_counter"
