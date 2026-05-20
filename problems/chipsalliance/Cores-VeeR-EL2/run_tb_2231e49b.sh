#!/usr/bin/env bash
# Runner for VeeR EL2 PMPCFG WARL fix (commit 2231e49).
#
# Compiles el2_pkg + el2_dec_pmp_ctl + beh_lib (rvdffe etc.) plus the focused
# testbench tb_2231e49b.sv with Verilator, then runs it. Exit 0 on PASS,
# non-zero on FAIL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/chipsalliance/Cores-VeeR-EL2" && pwd)"
TB_FILE="$SCRIPT_DIR/tb_2231e49b.sv"

export RV_ROOT="$REPO_DIR"
export PERL5LIB="${PERL5LIB:-}${PERL5LIB:+:}$HOME/perl5/lib/perl5/x86_64-linux-gnu-thread-multi:$HOME/perl5/lib/perl5"

BUILD_DIR="/tmp/vbuild_veer_el2_2231e49b"
SNAP_DIR="$BUILD_DIR/snapshots/default"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
BUILD_PATH=snapshots/default "$REPO_DIR/configs/veer.config" -target=default >/dev/null

verilator --binary --Wno-fatal --Wno-WIDTH --Wno-UNOPTFLAT --Wno-CASEINCOMPLETE \
    -Wno-IMPLICITSTATIC -Wno-ASCRANGE -Wno-INITIALDLY -Wno-SIDEEFFECT \
    -Wno-LATCH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
    -CFLAGS "-std=c++17" \
    --Mdir "$BUILD_DIR/obj_dir" \
    --top-module tb_2231e49b \
    -o Vtb_2231e49b \
    +incdir+"$SNAP_DIR" \
    +incdir+"$REPO_DIR/design/include" \
    +incdir+"$REPO_DIR/design/lib" \
    "$SNAP_DIR/common_defines.vh" \
    "$REPO_DIR/design/include/el2_def.sv" \
    "$REPO_DIR/design/lib/beh_lib.sv" \
    "$REPO_DIR/design/dec/el2_dec_pmp_ctl.sv" \
    "$TB_FILE" >/dev/null

timeout 30 "$BUILD_DIR/obj_dir/Vtb_2231e49b"
