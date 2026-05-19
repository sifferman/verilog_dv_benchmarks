#!/usr/bin/env bash
# Focused unit-test runner for cva6 mvendorid fix (43bd267b).
# Era A (pre-CVA6Cfg) csr_regfile: only DmBaseAddress / AsidWidth /
# NrCommitPorts / NrPMPEntries params; no parametric types.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_43bd267b
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-LATCH -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_csr_mvendorid \
    -o V_csr_regfile \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imac_sv32_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_dm_pkg.sv" \
    "$REPO_DIR/core/include/ariane_rvfi_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/csr_regfile.sv" \
    "$SCRIPT_DIR/tb_43bd267b.sv"

timeout 60 "$BUILD_DIR/obj_dir/V_csr_regfile"
