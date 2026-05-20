#!/usr/bin/env bash
# Focused unit-test runner for cva6 decoder DRET fix (4ab5ef93).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

# The TB needs dm_pkg.sv from cva6's riscv-dbg submodule.
dvbench_init_submodule "$REPO_DIR" corev_apu/riscv-dbg

BUILD_DIR=/tmp/vbuild_cva6_4ab5ef93
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_cva6_decoder_dret \
    -o V_decoder \
    "$REPO_DIR/core/include/riscv_pkg.sv" \
    "$REPO_DIR/core/include/cv32a6_imac_sv32_config_pkg.sv" \
    "$REPO_DIR/corev_apu/riscv-dbg/src/dm_pkg.sv" \
    "$REPO_DIR/core/include/ariane_rvfi_pkg.sv" \
    "$REPO_DIR/core/include/ariane_pkg.sv" \
    "$REPO_DIR/core/decoder.sv" \
    "$SCRIPT_DIR/tb_4ab5ef93.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_decoder"
