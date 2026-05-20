#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/apb_spi_master spi_master_apb_if
# spi_data_tx fix (commit 4fce41f).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/apb_spi_master" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_apb_spi_master_4fce41f5
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_4fce41f5 \
    -o V_apb_spi_master \
    "$REPO_DIR/spi_master_apb_if.sv" \
    "$SCRIPT_DIR/tb_4fce41f5.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_apb_spi_master"
