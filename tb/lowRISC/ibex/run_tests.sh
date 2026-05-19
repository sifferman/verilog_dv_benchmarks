#!/usr/bin/env bash
# Build and run a custom ibex CSR-related testbench.
#
# Self-contained: ibex RTL from the live clone working tree; lowrisc_ip vendor
# files from tb/lowRISC/ibex/vendor/. No FuseSoC required.
#
# Used by per-instance custom testbenches (e.g. tb_csr_misa, tb_csr_mseccfgh)
# that test specific behaviors not covered by the official tb_cs_registers.
#
# Inputs (env vars):
#   TOP_MODULE — top-level testbench module name
#   TB_FILE    — path to the testbench .sv file (resolved to absolute)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/lowRISC__ibex" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/vendor"
IBEX_RTL="$REPO_DIR/rtl"

# Populate vendor/ on first run (it's gitignored).
if [ ! -d "$VENDOR_DIR" ] || [ -z "$(ls -A "$VENDOR_DIR" 2>/dev/null)" ]; then
  bash "$SCRIPT_DIR/populate_vendor.sh"
fi

TOP="${TOP_MODULE:-tb_csr_simple}"
_DEFAULT_TB="$SCRIPT_DIR/tb_csr_simple.sv"
TB_FILE="$(cd "$(dirname "${TB_FILE:-$_DEFAULT_TB}")" && pwd)/$(basename "${TB_FILE:-$_DEFAULT_TB}")"

# Vendored lowrisc_ip SV files. Packages first.
VENDOR_SV=(
  "$VENDOR_DIR/prim_cipher_pkg.sv"
  "$VENDOR_DIR/prim_mubi_pkg.sv"
  "$VENDOR_DIR/prim_buf.sv"
  "$VENDOR_DIR/prim_flop.sv"
  "$VENDOR_DIR/prim_clock_gating.sv"
  "$VENDOR_DIR/prim_lfsr.sv"
)
# Glob picks up prim_secded_pkg.sv plus all encoders/decoders.
for f in "$VENDOR_DIR"/prim_secded_*.sv; do VENDOR_SV+=("$f"); done
for f in "$VENDOR_DIR"/prim_mubi*.sv; do
  case "$(basename "$f")" in prim_mubi_pkg.sv) ;; *) VENDOR_SV+=("$f") ;; esac
done

VLT_FILES=(
  "$VENDOR_DIR/common.vlt"
  "$VENDOR_DIR/prim_assert.vlt"
  "$VENDOR_DIR/prim_xilinx_clock_gating.vlt"
  "$REPO_DIR/lint/verilator_waiver.vlt"
)

# ibex RTL (live working tree). ibex_pkg first, then everything else.
IBEX_SV=("$IBEX_RTL/ibex_pkg.sv")
for f in "$IBEX_RTL"/ibex_*.sv; do
  case "$(basename "$f")" in ibex_pkg.sv) ;; *) IBEX_SV+=("$f") ;; esac
done

INCDIRS=(
  "+incdir+$VENDOR_DIR"
  "+incdir+$IBEX_RTL"
)

MDIR="/tmp/vbuild_ibex_${TOP}"
mkdir -p "$MDIR"

verilator --binary \
  --top-module "$TOP" \
  --Mdir "$MDIR" \
  --Wno-fatal \
  "${INCDIRS[@]}" \
  "${VLT_FILES[@]}" \
  "${VENDOR_SV[@]}" \
  "$VENDOR_DIR/prim_assert.sv" \
  "${IBEX_SV[@]}" \
  "$TB_FILE" 2>&1

timeout 30 "$MDIR/V${TOP}"
