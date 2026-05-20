#!/usr/bin/env bash
# Focused unit-test runner for openhwgroup/cvw bmuctrl rv32 shift fix (37c68798).
# Builds bmuctrl.sv + cvw.sv against the rv32gc config and checks that
# `srli x1, x0, 32` (illegal in RV32) is flagged by the decoder.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cvw" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cvw_37c68798
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_37c68798 \
    -o V_tb_37c68798 \
    "+incdir+$REPO_DIR/config/shared" \
    "+incdir+$REPO_DIR/config/rv32gc" \
    -y "$REPO_DIR/src/generic/flop" \
    "$REPO_DIR/src/cvw.sv" \
    "$REPO_DIR/src/ieu/bmu/bmuctrl.sv" \
    "$SCRIPT_DIR/tb_37c68798.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_tb_37c68798"
