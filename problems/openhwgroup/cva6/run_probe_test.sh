#!/usr/bin/env bash
# Smoke runner for the cva6 .S-on-full-CPU harness.
#
# Builds probe_test.S -> probe.bin -> probe.mem, expands the cva6 source
# manifests, and verilator-compiles run_instructions.{sv,cpp} with the full
# cva6 core. Pass criterion: the probe writes 0xCAFE0001 to 0x20000000 and
# the harness snoops it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/openhwgroup/cva6" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

PROBE_NAME="${1:-probe_test}"
PROBE_S="$SCRIPT_DIR/${PROBE_NAME}.S"
[[ -f "$PROBE_S" ]] || { echo "no probe at $PROBE_S" >&2; exit 2; }

BUILD_DIR="/tmp/vbuild_cva6_${PROBE_NAME}_${TARGET_CFG:-cv32a6_imac_sv32}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# -- Step 1: assemble + link probe to a flat binary at offset 0 --------------
riscv32-unknown-elf-as      -march=rv32ima -mabi=ilp32 -o "$BUILD_DIR/probe.o" "$PROBE_S"
riscv32-unknown-elf-ld      -m elf32lriscv -Ttext=0 --no-relax -o "$BUILD_DIR/probe.elf" "$BUILD_DIR/probe.o"
riscv32-unknown-elf-objcopy -O binary -j .text "$BUILD_DIR/probe.elf" "$BUILD_DIR/probe.bin"

# .mem: one 32-bit little-endian word per line, hex (for $readmemh)
hexdump -v -e '"%08x\n"' "$BUILD_DIR/probe.bin" > "$BUILD_DIR/probe.mem"

# -- Step 2: expand cva6's Flists into a single sources file -----------------
export CVA6_REPO_DIR="$REPO_DIR"
export HPDCACHE_DIR="$REPO_DIR/core/cache_subsystem/hpdcache"
# TARGET_CFG selects which core/include/${TARGET_CFG}_config_pkg.sv to compile.
# Per-bug runners override this when the bug only triggers under a specific
# config (e.g. cv32a6_ima_sv32_fpga has CExtEn=0 for the misaligned-branch bug).
: "${TARGET_CFG:=cv32a6_imac_sv32}"
export TARGET_CFG

FLIST="$BUILD_DIR/cva6.f"
{
    # Core flist (envsubst expands $CVA6_REPO_DIR/$HPDCACHE_DIR/$TARGET_CFG)
    envsubst < "$REPO_DIR/core/Flist.cva6"
    echo ""
    envsubst < "$REPO_DIR/core/cache_subsystem/hpdcache/rtl/hpdcache.Flist"
    echo ""
    # Additional include paths
    echo "+incdir+$REPO_DIR/corev_apu/riscv-dbg/src"
    echo "+incdir+$REPO_DIR/corev_apu/register_interface/include"
    # AXI memory model (pulp-axi) + helper macros
    echo "$REPO_DIR/vendor/pulp-platform/axi/src/axi_sim_mem.sv"
    # debug-module pkg (referenced by cva6 internals)
    echo "$REPO_DIR/corev_apu/riscv-dbg/src/dm_pkg.sv"
    # ariane axi types (corev_apu/tb)
    echo "$REPO_DIR/corev_apu/tb/ariane_axi_pkg.sv"
    # the ariane wrapper around cva6 (handles cvxif stub etc.)
    echo "$REPO_DIR/corev_apu/src/ariane.sv"
    # our harness
    echo "$SCRIPT_DIR/run_instructions.sv"
    echo "$SCRIPT_DIR/run_instructions.cpp"
} > "$FLIST"

# -- Step 3: verilate ---------------------------------------------------------
export SUCCESS_ADDR="${SUCCESS_ADDR:-0x20000000}"
export EXPECTED_VALUE="${EXPECTED_VALUE:-0xCAFE0001}"

verilator --binary --timing \
    -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-LATCH -Wno-CASEINCOMPLETE \
    +define+HPDCACHE_ASSERT_OFF \
    --Mdir "$BUILD_DIR/obj_dir" \
    -CFLAGS "-std=c++17" \
    --top-module run_instructions \
    -o V_run_instructions \
    -f "$FLIST"

# -- Step 4: run --------------------------------------------------------------
timeout 120 "$BUILD_DIR/obj_dir/V_run_instructions" \
    "+MEMFILE=$BUILD_DIR/probe.mem" \
    "+MAX_CYCLES=200000"
