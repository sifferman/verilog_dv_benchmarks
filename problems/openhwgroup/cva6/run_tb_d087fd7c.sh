#!/usr/bin/env bash
# Focused unit-test runner for cva6 SRET RVS=0 fix (d087fd7c).
# Era B (2023-11): decoder takes CVA6Cfg. cv32a6_embedded -> RVS=0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_cva6_d087fd7c
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_sret_rvs0 \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/config_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_embedded_config_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_d087fd7c.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
