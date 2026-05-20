#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/hwpe-stream hwpe_stream_fifo
# EMPTY-state push_pointer wrap fix (commit 3bc9694).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/hwpe-stream" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_hwpe_stream_3bc96947
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_3bc96947 \
    -o V_hwpe_stream_fifo \
    "$REPO_DIR/rtl/hwpe_stream_package.sv" \
    "$REPO_DIR/rtl/hwpe_stream_interfaces.sv" \
    "$REPO_DIR/rtl/fifo/hwpe_stream_fifo.sv" \
    "$SCRIPT_DIR/tb_3bc96947.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_hwpe_stream_fifo"
