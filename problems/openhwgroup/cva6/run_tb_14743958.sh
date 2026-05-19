#!/usr/bin/env bash
# Focused unit-test runner for cva6 SFENCE.VMA RVS=0 fix (14743958).
# Era B (2024-02): decoder takes CVA6Cfg parameter; cva6_config_pkg::cva6_cfg
# is already a cva6_cfg_t struct at this era. Uses cv32a6_embedded
# (CVA6ConfigRVS=0) to trigger the bug path. The TB peeks `dut.illegal_instr`
# directly so CvxifEn=1 doesn't mask the decoder's verdict.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_14743958
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_sfencevma_rvs0 \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_embedded_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_14743958.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
