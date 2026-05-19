#!/usr/bin/env bash
# Focused unit-test runner for cva6 compressed_decoder c.ld/c.sd FP fix
# (6d263a60). Era 2022-09 (era A): compressed_decoder is non-parametric
# and reads `riscv::XLEN` directly. cv32a6_imafc_sv32 -> XLEN=32 + RVF=1
# so c.ld must remap to c.flw.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_6d263a60
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_csd_fp \
    -o V_compressed_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imafc_sv32_config_pkg.sv" \
    "$REPO_DIR/corev_apu/riscv-dbg/src/dm_pkg.sv" \
    "$REPO_DIR/core/include/ariane_rvfi_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/compressed_decoder.sv" \
    "$SCRIPT_DIR/tb_6d263a60.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_compressed_decoder"
