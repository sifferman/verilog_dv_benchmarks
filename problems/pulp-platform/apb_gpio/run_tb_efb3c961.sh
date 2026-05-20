#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/apb_gpio padoutclr polarity fix
# (commit efb3c96).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/apb_gpio" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_apb_gpio_efb3c961
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_efb3c961 \
    -o V_apb_gpio \
    "$REPO_DIR/rtl/apb_gpio.sv" \
    "$SCRIPT_DIR/tb_efb3c961.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_apb_gpio"
