#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/per2axi per2axi_req_channel
# handshake fix (commit 9226058).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/per2axi" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_per2axi_92260580
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_92260580 \
    -o V_per2axi_req_channel \
    "$REPO_DIR/src/per2axi_req_channel.sv" \
    "$SCRIPT_DIR/tb_92260580.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_per2axi_req_channel"
