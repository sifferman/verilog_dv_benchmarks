#!/usr/bin/env bash
# Focused unit-test runner for cva6 decoder ZEXT.H fix (99acdc27).
# Era 2023-05: decoder takes no CVA6Cfg parameter; Zbb gating comes from
# cva6_config_pkg's CVA6ConfigBExtEn (=0 in cv32a6_ima_sv32_fpga).
# rvfi_pkg lives at common/local/rvfi/ at this era; dm pkg is the in-tree
# ariane_dm_pkg.sv (not the riscv-dbg submodule).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_99acdc27
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_zexth \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_ima_sv32_fpga_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_dm_pkg.sv" \
    "$REPO_DIR/common/local/rvfi/rvfi_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_99acdc27.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
