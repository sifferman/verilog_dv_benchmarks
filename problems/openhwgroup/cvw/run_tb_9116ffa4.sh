#!/usr/bin/env bash
# Focused unit-test runner for openhwgroup/cvw bmuctrl w-type-in-RV32 fix
# (commit 9116ffa4). Builds bmuctrl.sv + cvw.sv against the rv32gc config
# and checks that slliw is rejected as illegal in RV32.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cvw" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cvw_9116ffa4
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_9116ffa4 \
    -o V_tb_9116ffa4 \
    "+incdir+$REPO_DIR/config/shared" \
    "+incdir+$REPO_DIR/config/rv32gc" \
    -y "$REPO_DIR/src/generic/flop" \
    "$REPO_DIR/src/cvw.sv" \
    "$REPO_DIR/src/ieu/bmu/bmuctrl.sv" \
    "$SCRIPT_DIR/tb_9116ffa4.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_tb_9116ffa4"
