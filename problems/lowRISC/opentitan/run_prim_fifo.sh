#!/usr/bin/env bash
# Compile and run opentitan Verilator testbenches.
# Dispatches on TOP_MODULE:
#   tb_prim_fifo_sync_depth0    (default) — prim_fifo_sync Depth==0 full_o fix
#   tb_prim_sha2_pad_continue             — prim_sha2_pad hash_continue digest mode fix
#   tb_prim_subreg_rc                     — prim_subreg RC access corner case fix
# Run from anywhere; REPO_DIR is resolved relative to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/lowRISC/opentitan" && pwd)"
PRIM_RTL="$REPO_DIR/hw/ip/prim/rtl"

TOP="${TOP_MODULE:-tb_prim_fifo_sync_depth0}"
MDIR="/tmp/vbuild_ot_${TOP}"
# Wipe the cache so stale Vtb_*.mk paths from earlier clone layouts don't
# survive into a fresh run.
rm -rf "$MDIR"
mkdir -p "$MDIR"

case "$TOP" in
  tb_prim_subreg_rc)
    TB_FILE="${TB_FILE:-$SCRIPT_DIR/tb_d08268e9.sv}"
    verilator --binary \
      --top-module "$TOP" \
      --Mdir "$MDIR" \
      --Wno-fatal \
      "+incdir+$PRIM_RTL" \
      "$PRIM_RTL/prim_assert.sv" \
      "$PRIM_RTL/prim_mubi_pkg.sv" \
      "$PRIM_RTL/prim_subreg_pkg.sv" \
      "$PRIM_RTL/prim_subreg_arb.sv" \
      "$PRIM_RTL/prim_subreg.sv" \
      "$TB_FILE"
    ;;
  tb_prim_sha2_pad_continue)
    TB_FILE="${TB_FILE:-$SCRIPT_DIR/tb_a7cb9a48.sv}"
    verilator --binary \
      --top-module "$TOP" \
      --Mdir "$MDIR" \
      --Wno-fatal \
      "+incdir+$PRIM_RTL" \
      "$PRIM_RTL/prim_util_pkg.sv" \
      "$PRIM_RTL/prim_count_pkg.sv" \
      "$PRIM_RTL/prim_sha2_pkg.sv" \
      "$PRIM_RTL/prim_assert.sv" \
      "$PRIM_RTL/prim_sha2_pad.sv" \
      "$TB_FILE"
    ;;
  *)
    TB_FILE="${TB_FILE:-$SCRIPT_DIR/tb_3d4980cd.sv}"
    verilator --binary \
      --top-module "$TOP" \
      --Mdir "$MDIR" \
      --Wno-fatal \
      "+incdir+$PRIM_RTL" \
      "$PRIM_RTL/prim_util_pkg.sv" \
      "$PRIM_RTL/prim_count_pkg.sv" \
      "$PRIM_RTL/prim_assert.sv" \
      "$PRIM_RTL/prim_fifo_sync.sv" \
      "$TB_FILE"
    ;;
esac

timeout 30 "$MDIR/V${TOP}"
