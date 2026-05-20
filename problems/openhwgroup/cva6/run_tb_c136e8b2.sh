#!/usr/bin/env bash
# Focused unit-test runner for cva6 MCONFIGPTR read fix (c136e8b2).
# Era B (pre-2024) csr_regfile. Uses ariane_pkg::cva6_cfg_t directly (no
# build_config_pkg). cv32a6_imac_sv32: XLEN=32, CvxifEn=0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

# The TB needs dm_pkg.sv from cva6's riscv-dbg submodule.
dvbench_init_submodule "$REPO_DIR" corev_apu/riscv-dbg

BUILD_DIR=/tmp/vbuild_cva6_c136e8b2
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-LATCH -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_csr_mconfigptr \
    -o V_csr_regfile \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imac_sv32_config_pkg.sv" \
    "$REPO_DIR/corev_apu/riscv-dbg/src/dm_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/csr_regfile.sv" \
    "$SCRIPT_DIR/tb_c136e8b2.sv"

timeout 60 "$BUILD_DIR/obj_dir/V_csr_regfile"
