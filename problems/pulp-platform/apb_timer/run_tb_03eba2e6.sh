#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/apb_timer timer.sv prescaler fix
# (commit 03eba2e).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/apb_timer" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_apb_timer_03eba2e6
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_03eba2e6 \
    -o V_apb_timer \
    "$REPO_DIR/src/timer.sv" \
    "$SCRIPT_DIR/tb_03eba2e6.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_apb_timer"
