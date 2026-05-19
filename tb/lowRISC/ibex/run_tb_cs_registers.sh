#!/usr/bin/env bash
# Build and run the official ibex cs_registers testbench.
# Compiles with `verilator --binary` (--binary implies --timing).
#
# Self-contained: ibex RTL + DV come from the live ibex clone working tree;
# all lowrisc_ip vendor files come from tb/lowRISC/ibex/vendor/ (committed
# in this repo). No FuseSoC required.
#
# Two minimal patches are applied to tb_cs_registers.sv at build time:
#   1. Remove `ifndef VERILATOR guard so the clock/reset generator runs.
#   2. Change $finish() to $fatal(1) on failure for a non-zero exit code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/lowRISC__ibex" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/vendor"
DV_DIR="$REPO_DIR/dv/cs_registers"
IBEX_RTL="$REPO_DIR/rtl"
MDIR="/tmp/vbuild_ibex_cs_registers"

# Populate vendor/ on first run (it's gitignored).
if [ ! -d "$VENDOR_DIR" ] || [ -z "$(ls -A "$VENDOR_DIR" 2>/dev/null)" ]; then
  bash "$SCRIPT_DIR/populate_vendor.sh"
fi

mkdir -p "$MDIR"

# Patch tb_cs_registers.sv: remove `ifndef VERILATOR guard, fix exit code.
PATCHED_TB="$MDIR/tb_cs_registers.sv"
python3 - "$DV_DIR/tb/tb_cs_registers.sv" "$PATCHED_TB" << 'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
content = re.sub(r'`ifndef VERILATOR\n', '', content, count=1)
content = re.sub(r'`endif\n', '', content, count=1)
content = content.replace(
    '    $finish();',
    '    if (test_passed) $finish(0);\n    else $fatal(1, "TEST FAILED");'
)
with open(sys.argv[2], 'w') as f:
    f.write(content)
PYEOF

# C++ DPI sources from the ibex DV tree.
DPI_CC=(
  "$DV_DIR/env/env_dpi.cc"
  "$DV_DIR/env/register_environment.cc"
  "$DV_DIR/env/simctrl.cc"
  "$DV_DIR/model/base_register.cc"
  "$DV_DIR/model/register_model.cc"
  "$DV_DIR/reg_driver/reg_dpi.cc"
  "$DV_DIR/reg_driver/register_driver.cc"
  "$DV_DIR/reg_driver/register_transaction.cc"
  "$DV_DIR/rst_driver/reset_driver.cc"
  "$DV_DIR/rst_driver/rst_dpi.cc"
)

# Vendored lowrisc_ip SV files. prim_*_pkg.sv must come before users.
VENDOR_SV=(
  "$VENDOR_DIR/prim_cipher_pkg.sv"
  "$VENDOR_DIR/prim_mubi_pkg.sv"
  "$VENDOR_DIR/prim_buf.sv"
  "$VENDOR_DIR/prim_flop.sv"
  "$VENDOR_DIR/prim_clock_gating.sv"
  "$VENDOR_DIR/prim_lfsr.sv"
)
# prim_secded_pkg.sv must come before its consumers; the glob below picks up
# both the package and all encoders/decoders.
for f in "$VENDOR_DIR"/prim_secded_*.sv; do VENDOR_SV+=("$f"); done
for f in "$VENDOR_DIR"/prim_mubi*.sv; do
  case "$(basename "$f")" in prim_mubi_pkg.sv) ;; *) VENDOR_SV+=("$f") ;; esac
done

VLT_FILES=(
  "$VENDOR_DIR/common.vlt"
  "$VENDOR_DIR/prim_assert.vlt"
  "$VENDOR_DIR/prim_xilinx_clock_gating.vlt"
  "$REPO_DIR/lint/verilator_waiver.vlt"
  "$DV_DIR/lint/verilator_waiver.vlt"
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
CFLAGS="-I$DV_DIR/env -I$DV_DIR/model -I$DV_DIR/reg_driver -I$DV_DIR/rst_driver -std=c++17"

verilator --binary \
  --top-module tb_cs_registers \
  --Mdir "$MDIR" \
  --Wno-fatal \
  -GPMPEnable=1 -GPMPNumRegions=4 -GPMPGranularity=0 \
  -GMHPMCounterNum=8 -GMHPMCounterWidth=40 \
  -CFLAGS "$CFLAGS" \
  "${INCDIRS[@]}" \
  "${VLT_FILES[@]}" \
  "${VENDOR_SV[@]}" \
  "$VENDOR_DIR/prim_assert.sv" \
  "${IBEX_SV[@]}" \
  "$DV_DIR/env/env_dpi.sv" \
  "$DV_DIR/rst_driver/rst_dpi.sv" \
  "$DV_DIR/reg_driver/reg_dpi.sv" \
  "${DPI_CC[@]}" \
  "$PATCHED_TB" 2>&1

timeout 60 "$MDIR/Vtb_cs_registers"
