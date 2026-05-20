#!/usr/bin/env bash
# Focused unit-test runner for pulp-platform/apb_event_unit addressing fix
# (commit adcb49e).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/pulp-platform/apb_event_unit" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

BUILD_DIR=/tmp/vbuild_apb_event_unit_adcb49e7
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

verilator --binary -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE \
    -I"$REPO_DIR/include" \
    --Mdir "$BUILD_DIR/obj_dir" -CFLAGS "-std=c++17" \
    --top-module tb_adcb49e7 \
    -o V_apb_event_unit \
    "$REPO_DIR/generic_service_unit.sv" \
    "$REPO_DIR/sleep_unit.sv" \
    "$REPO_DIR/apb_event_unit.sv" \
    "$SCRIPT_DIR/tb_adcb49e7.sv"

timeout 30 "$BUILD_DIR/obj_dir/V_apb_event_unit"
