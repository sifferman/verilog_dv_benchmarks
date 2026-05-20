#!/usr/bin/env bash
# Focused unit-test runner for bsg_fifo_1r1w_small_hardened bypass fix
# (commit 527b3be).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/bespoke-silicon-group/basejump_stl" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_basejump_527b3bec
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# basejump_stl files use `include "bsg_defines.sv"`; the file lives in
# bsg_misc/. Add it to the include path.
verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    -Wno-INITIALDLY -Wno-MULTIDRIVEN -Wno-UNUSED -Wno-UNSIGNED -Wno-CMPCONST \
    -Wno-PINMISSING -Wno-DECLFILENAME -Wno-VARHIDDEN -Wno-SYNCASYNCNET \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_527b3bec \
    -o V_tb \
    "+incdir+$REPO_DIR/bsg_misc" \
    "$REPO_DIR/bsg_misc/bsg_defines.sv" \
    "$REPO_DIR/bsg_misc/bsg_dff.sv" \
    "$REPO_DIR/bsg_misc/bsg_dff_en.sv" \
    "$REPO_DIR/bsg_misc/bsg_dff_en_bypass.sv" \
    "$REPO_DIR/bsg_misc/bsg_dff_reset_set_clear.sv" \
    "$REPO_DIR/bsg_mem/bsg_mem_1r1w_sync_synth.sv" \
    "$REPO_DIR/bsg_mem/bsg_mem_1r1w_sync.sv" \
    "$REPO_DIR/bsg_dataflow/bsg_fifo_tracker.sv" \
    "$REPO_DIR/bsg_dataflow/bsg_fifo_1r1w_small_hardened.sv" \
    "$SCRIPT_DIR/tb_527b3bec.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_tb"
