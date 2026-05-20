#!/usr/bin/env bash
# Focused unit-test runner for cva6 mstatus.UBE scrub (061694e3).
# Era B csr_regfile with config_pkg::cva6_cfg_t built via build_config_pkg.
# cv32a6_imac_sv32: XLEN=32, CvxifEn=0, RVU=1.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

# The TB needs dm_pkg.sv from cva6's riscv-dbg submodule.
dvbench_init_submodule "$REPO_DIR" corev_apu/riscv-dbg

BUILD_DIR=/tmp/vbuild_cva6_061694e3
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-LATCH -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_csr_ube_scrub \
    -o V_csr_regfile \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imac_sv32_config_pkg.sv" \
    "$REPO_DIR/corev_apu/riscv-dbg/src/dm_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/csr_regfile.sv" \
    "$SCRIPT_DIR/tb_061694e3.sv"

timeout 60 "$BUILD_DIR/obj_dir/V_csr_regfile"
