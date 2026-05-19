#!/usr/bin/env bash
# Focused unit-test runner for cva6 compressed_decoder c.sh fix (e6867b8f).
# Era 2025-07 (parametric types): compressed_decoder takes CVA6Cfg. Use
# cv32a60x (RVZCB=1) so the c.sh Zcb path is enabled.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_e6867b8f
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    "+incdir+$REPO_DIR/core/include" \
    --top-module tb_cva6_csh \
    -o V_compressed_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a60x_config_pkg.sv" \
    "$REPO_DIR/core/include/build_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/compressed_decoder.sv" \
    "$SCRIPT_DIR/tb_e6867b8f.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_compressed_decoder"
