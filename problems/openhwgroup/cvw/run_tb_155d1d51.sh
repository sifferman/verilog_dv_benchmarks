#!/usr/bin/env bash
# Focused unit-test runner for openhwgroup/cvw privdec sinval.vma funct7 fix
# (commit 155d1d51). Uses rv64gc config which enables SVINVAL_SUPPORTED.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cvw" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cvw_155d1d51
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_155d1d51 \
    -o V_tb_155d1d51 \
    "+incdir+$REPO_DIR/config/shared" \
    "+incdir+$REPO_DIR/config/rv64gc" \
    -y "$REPO_DIR/src/generic/flop" \
    "$REPO_DIR/src/cvw.sv" \
    "$REPO_DIR/src/privileged/privdec.sv" \
    "$SCRIPT_DIR/tb_155d1d51.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_tb_155d1d51"
