#!/usr/bin/env bash
# Populate tb/lowRISC/ibex/vendor/ with the lowrisc_ip files needed by
# run_tb_cs_registers.sh and run_tests.sh, plus three hand-written
# abstraction-layer wrappers (prim_buf, prim_flop, prim_clock_gating).
#
# Files come from the ibex clone at origin/master — that ref always has the
# full vendor tree (older commits may have a sparser set, e.g. no mubi).
# This makes the runners FuseSoC-free and stable across all instance commits.
#
# The output directory tb/lowRISC/ibex/vendor/ is gitignored; this script is
# the canonical way to (re)create it. Run it once after cloning the project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)/clones/lowRISC__ibex"
DEST="$SCRIPT_DIR/vendor"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Cloning lowRISC/ibex..." >&2
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --filter=blob:none https://github.com/lowRISC/ibex "$REPO_DIR"
fi

echo "Fetching origin/master to source vendor files from..." >&2
git -C "$REPO_DIR" fetch --filter=blob:none --quiet origin master

mkdir -p "$DEST"

# Files to lift verbatim from origin/master:vendor/lowrisc_ip/.
# Listed by destination path → source path within vendor/lowrisc_ip/.
declare -a FILES=(
  # Packages and primitives.
  "prim_cipher_pkg.sv:ip/prim/rtl/prim_cipher_pkg.sv"
  "prim_lfsr.sv:ip/prim/rtl/prim_lfsr.sv"
  # SECDED package + all encoders/decoders/wrappers.
  "prim_secded_pkg.sv:ip/prim/rtl/prim_secded_pkg.sv"
  # MUBI package + all variants.
  "prim_mubi_pkg.sv:ip/prim/rtl/prim_mubi_pkg.sv"
  # Assertion infrastructure.
  "prim_assert.sv:ip/prim/rtl/prim_assert.sv"
  "prim_assert_dummy_macros.svh:ip/prim/rtl/prim_assert_dummy_macros.svh"
  "prim_assert_standard_macros.svh:ip/prim/rtl/prim_assert_standard_macros.svh"
  "prim_assert_yosys_macros.svh:ip/prim/rtl/prim_assert_yosys_macros.svh"
  "prim_assert_sec_cm.svh:ip/prim/rtl/prim_assert_sec_cm.svh"
  # prim_flop_macros.sv is `include'd by prim_assert.sv on recent versions.
  "prim_flop_macros.sv:ip/prim/rtl/prim_flop_macros.sv"
  # FCOV macros (used by the cs_registers TB).
  "dv_fcov_macros.svh:dv/sv/dv_utils/dv_fcov_macros.svh"
  # Verilator waiver files.
  "common.vlt:lint/tools/verilator/common.vlt"
  "prim_assert.vlt:ip/prim/lint/prim_assert.vlt"
  "prim_xilinx_clock_gating.vlt:ip/prim_xilinx/lint/prim_xilinx_clock_gating.vlt"
)

for entry in "${FILES[@]}"; do
  dest_name="${entry%%:*}"
  src_path="${entry#*:}"
  git -C "$REPO_DIR" show "origin/master:vendor/lowrisc_ip/$src_path" > "$DEST/$dest_name"
done

# Glob-extract all SECDED encoders/decoders and MUBI variants.
extract_glob() {
  local src_dir="$1" pattern="$2"
  git -C "$REPO_DIR" ls-tree -r --name-only origin/master "vendor/lowrisc_ip/$src_dir/" \
    | grep -E "$pattern" \
    | while read -r path; do
        git -C "$REPO_DIR" show "origin/master:$path" > "$DEST/$(basename "$path")"
      done
}
extract_glob "ip/prim/rtl" 'prim_secded_.*\.svh?$'
extract_glob "ip/prim/rtl" 'prim_mubi[0-9].*\.sv$'

# Hand-written wrappers (FuseSoC normally generates these; we don't have it).
# Semantics matched to the upstream lowrisc_ip generic/xilinx implementations.

cat > "$DEST/prim_buf.sv" << 'EOF'
// Hand-written passthrough wrapper for prim_buf (originally FuseSoC-generated).
// Double-invert to prevent synthesis from optimizing the buffer away.
`include "prim_assert.sv"
module prim_buf #(
  parameter int Width = 1
) (
  input        [Width-1:0] in_i,
  output logic [Width-1:0] out_o
);
  logic [Width-1:0] inv;
  assign inv   = ~in_i;
  assign out_o = ~inv;
endmodule
EOF

cat > "$DEST/prim_flop.sv" << 'EOF'
// Hand-written wrapper for prim_flop (originally FuseSoC-generated).
`include "prim_assert.sv"
module prim_flop #(
  parameter int               Width      = 1,
  parameter logic [Width-1:0] ResetValue = 0
) (
  input                    clk_i,
  input                    rst_ni,
  input        [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) q_o <= ResetValue;
    else         q_o <= d_i;
  end
endmodule
EOF

cat > "$DEST/prim_clock_gating.sv" << 'EOF'
// Hand-written wrapper for prim_clock_gating (originally FuseSoC-generated).
// For Verilator simulation we use a behavioral latch-based gater.
module prim_clock_gating #(
  parameter bit NoFpgaGate    = 1'b0,
  parameter bit FpgaBufGlobal = 1'b1
) (
  input        clk_i,
  input        en_i,
  input        test_en_i,
  output logic clk_o
);
  logic en_latch;
  // Behavioral active-low latch: capture en when clk is low.
  always_latch begin
    if (!clk_i) en_latch = en_i | test_en_i;
  end
  assign clk_o = clk_i & en_latch;
endmodule
EOF

echo "Populated $DEST with $(ls "$DEST" | wc -l) files." >&2
