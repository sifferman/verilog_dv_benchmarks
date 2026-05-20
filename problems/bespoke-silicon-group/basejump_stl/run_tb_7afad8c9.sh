#!/usr/bin/env bash
# Focused unit-test runner for bsg_counter_clear_up_multi rollover fix
# (commit 7afad8c).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/bespoke-silicon-group/basejump_stl" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_basejump_7afad8c9
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-UNUSED -Wno-UNSIGNED -Wno-CMPCONST \
    -Wno-PINMISSING -Wno-DECLFILENAME -Wno-VARHIDDEN -Wno-SYNCASYNCNET \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-WIDTHCONCAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_7afad8c9 \
    -o V_tb \
    "+incdir+$REPO_DIR/bsg_misc" \
    "$REPO_DIR/bsg_misc/bsg_defines.sv" \
    "$REPO_DIR/bsg_misc/bsg_popcount.sv" \
    "$REPO_DIR/bsg_misc/bsg_counter_clear_up_multi.sv" \
    "$SCRIPT_DIR/tb_7afad8c9.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_tb"
