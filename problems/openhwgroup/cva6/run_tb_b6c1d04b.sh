#!/usr/bin/env bash
# Focused unit-test runner for cva6 decoder SFENCE.VMA fix (b6c1d04b).
# 2022 era: cv32a60x_config_pkg + ariane_rvfi_pkg (combined, no separate
# ariane_dm + rvfi packages).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

# The TB needs dm_pkg.sv from cva6's riscv-dbg submodule.
dvbench_init_submodule "$REPO_DIR" corev_apu/riscv-dbg

BUILD_DIR=/tmp/vbuild_cva6_b6c1d04b
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_sfencevma \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imac_sv32_config_pkg.sv" \
    "$REPO_DIR/corev_apu/riscv-dbg/src/dm_pkg.sv" \
    "$REPO_DIR/core/include/ariane_rvfi_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_b6c1d04b.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
