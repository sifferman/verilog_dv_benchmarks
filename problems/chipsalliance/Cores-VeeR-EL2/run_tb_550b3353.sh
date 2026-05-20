#!/usr/bin/env bash
# Runner for VeeR EL2 c.lwsp rd==0 decoder bug (commit 550b335).
#
# Compiles el2_pkg + el2_ifu_compress_ctl from the live RTL plus the focused
# focused testbench tb_550b3353.sv with Verilator, then runs it. Exit 0 on
# PASS, non-zero on FAIL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/chipsalliance/Cores-VeeR-EL2" && pwd)"
TB_FILE="$SCRIPT_DIR/tb_550b3353.sv"

# Build snapshot (generates el2_param.vh / el2_pdef.vh / common_defines.vh).
# Uses default target; iccm_enable not required for compress_ctl.
export RV_ROOT="$REPO_DIR"
export PERL5LIB="${PERL5LIB:-}${PERL5LIB:+:}$HOME/perl5/lib/perl5/x86_64-linux-gnu-thread-multi:$HOME/perl5/lib/perl5"

BUILD_DIR="/tmp/vbuild_veer_el2_550b3353"
SNAP_DIR="$BUILD_DIR/snapshots/default"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
BUILD_PATH=snapshots/default "$REPO_DIR/configs/veer.config" -target=default >/dev/null

# Verilator compile: SV TB + DUT + package. lib/beh_lib.sv defines rvdffe etc.
# but compress_ctl is purely combinational so we don't need beh_lib.
verilator --binary --Wno-fatal --Wno-WIDTH --Wno-UNOPTFLAT --Wno-CASEINCOMPLETE \
    -Wno-IMPLICITSTATIC -Wno-ASCRANGE -Wno-INITIALDLY -Wno-SIDEEFFECT \
    -Wno-LATCH -Wno-TIMESCALEMOD \
    -CFLAGS "-std=c++17" \
    --Mdir "$BUILD_DIR/obj_dir" \
    --top-module tb_550b3353 \
    -o Vtb_550b3353 \
    +incdir+"$SNAP_DIR" \
    +incdir+"$REPO_DIR/design/include" \
    +incdir+"$REPO_DIR/design/lib" \
    "$SNAP_DIR/common_defines.vh" \
    "$REPO_DIR/design/include/el2_def.sv" \
    "$REPO_DIR/design/ifu/el2_ifu_compress_ctl.sv" \
    "$TB_FILE" >/dev/null

timeout 30 "$BUILD_DIR/obj_dir/Vtb_550b3353"
