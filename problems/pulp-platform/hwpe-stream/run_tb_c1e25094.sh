#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/hwpe-stream hwpe_stream_fifo
# "Correctly assign almost full signal" (c1e2509).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/hwpe-stream" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_hwpe_stream_c1e25094
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_c1e25094 \
    -o V_hwpe_stream_fifo \
    "$REPO_DIR/rtl/hwpe_stream_package.sv" \
    "$REPO_DIR/rtl/hwpe_stream_interfaces.sv" \
    "$REPO_DIR/rtl/fifo/hwpe_stream_fifo.sv" \
    "$SCRIPT_DIR/tb_c1e25094.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_hwpe_stream_fifo"
