#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/hwpe-stream passthrough FIFO fix
# (commit 01e3910).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/hwpe-stream" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_hwpe_stream_01e39105
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_01e39105 \
    -o V_hwpe_stream_fifo_passthrough \
    "$REPO_DIR/rtl/hwpe_stream_package.sv" \
    "$REPO_DIR/rtl/hwpe_stream_interfaces.sv" \
    "$REPO_DIR/rtl/fifo/hwpe_stream_fifo.sv" \
    "$REPO_DIR/rtl/fifo/hwpe_stream_fifo_passthrough.sv" \
    "$SCRIPT_DIR/tb_01e39105.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_hwpe_stream_fifo_passthrough"
