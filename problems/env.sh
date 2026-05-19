#!/usr/bin/env bash
# Shared env for verilog_dv_benchmarks runners. Source from any per-problem
# run_tests.sh. Discovers each tool at runtime so the same script works on any
# host where the tools are installed somewhere on the search list.
#
# To add a new fallback location, append it to the corresponding list below
# (one path per line so diffs read cleanly).

# --- helpers ------------------------------------------------------------------

# Echo the first executable found in the candidate list. Empty if none match.
# Always returns 0 — callers may run under `set -e`, and a missing tool here
# is expected (we want an empty DVBENCH_* var, not an aborted source).
_dvbench_find_tool() {
    local candidate
    for candidate in "$@"; do
        if [ -x "$candidate" ]; then echo "$candidate"; return 0; fi
    done
    command -v "$(basename "$1")" 2>/dev/null || true
    return 0
}

# Add the directory containing $1 to PATH if it isn't already there.
_dvbench_path_add_dir_of() {
    local tool_path="$1"
    [ -z "$tool_path" ] && return 0
    local dir; dir="$(dirname "$tool_path")"
    case ":$PATH:" in *":$dir:"*) ;; *) export PATH="$dir:$PATH" ;; esac
}

# --- tool discovery -----------------------------------------------------------

# riscv64-unknown-elf toolchain (picorv32 HEAD Makefile, neorv32, nerv, caliptra)
DVBENCH_RISCV64_GCC="$(_dvbench_find_tool \
    /mada/software/riscv/old/bin/riscv64-unknown-elf-gcc \
    /mada/users/sbeamer/riscv/bin/riscv64-unknown-elf-gcc \
    /mada/users/nkabylka/riscv/bin/riscv64-unknown-elf-gcc \
    /opt/riscv/bin/riscv64-unknown-elf-gcc \
    "$HOME/riscv/bin/riscv64-unknown-elf-gcc")"

# riscv32-unknown-elf toolchain (older picorv32 commits, some PULP designs)
DVBENCH_RISCV32_GCC="$(_dvbench_find_tool \
    /opt/riscv32i/bin/riscv32-unknown-elf-gcc \
    /opt/riscv32/bin/riscv32-unknown-elf-gcc)"

# Open-source EDA suite (iverilog, vvp, verilator, yosys, tabbypy3 w/ cocotb 2.x)
DVBENCH_OSS_CAD="$(_dvbench_find_tool \
    /soe/esifferm/Utils/oss-cad-suite/bin/iverilog \
    /opt/oss-cad-suite/bin/iverilog \
    "$HOME/oss-cad-suite/bin/iverilog")"

# FuseSoC (Python entry point — usually in user site-packages)
DVBENCH_FUSESOC="$(_dvbench_find_tool \
    "$HOME/.local/bin/fusesoc" \
    /usr/local/bin/fusesoc \
    /usr/bin/fusesoc)"

# sv2v (SystemVerilog -> Verilog converter — needed by adam-maj/tiny-gpu etc.)
DVBENCH_SV2V="$(_dvbench_find_tool \
    /soe/esifferm/Utils/zachjs-sv2v/sv2v \
    /usr/local/bin/sv2v \
    "$HOME/.local/bin/sv2v")"

# --- PATH assembly ------------------------------------------------------------

_dvbench_path_add_dir_of "$DVBENCH_SV2V"
_dvbench_path_add_dir_of "$DVBENCH_FUSESOC"
_dvbench_path_add_dir_of "$DVBENCH_OSS_CAD"
_dvbench_path_add_dir_of "$DVBENCH_RISCV32_GCC"
_dvbench_path_add_dir_of "$DVBENCH_RISCV64_GCC"

# --- cocotb env helpers -------------------------------------------------------
#
# Two cocotbs typically coexist on host:
#   * oss-cad-suite Python 3.11  -> cocotb 2.x  (Make-based testbenches that
#                                                call `cocotb-config`)
#   * user Python 3.10 site-pkgs -> cocotb 1.x + cocotb-test
#                                                (pytest-driven tests)
# Mixing PYTHONPATH across the two breaks the 3.11 interpreter (encodings
# missing). The helpers below isolate each invocation.

# Run a Make-based cocotb testbench: keeps PATH, strips PYTHONPATH.
# Usage: dvbench_cocotb_make make SIM=icarus
dvbench_cocotb_make() {
    env -u PYTHONPATH PATH="$PATH" "$@"
}

# Run a pytest-driven cocotb-test testbench under system Python 3.10.
# Usage: dvbench_cocotb_pytest python3 -m pytest test_foo.py
dvbench_cocotb_pytest() {
    env PATH="$PATH" \
        PYTHONPATH="$HOME/.local/lib/python3.10/site-packages" \
        "$@"
}

# Default behavior: strip PYTHONPATH so runners not opted into the helpers above
# default to the safe (oss-cad-suite-only) behavior.
unset PYTHONPATH

# --- FuseSoC config -----------------------------------------------------------

# Path to the project-local fusesoc.conf (sets build_root, cache_root, library).
# Generated locally with `fusesoc --config <this path> library add ...`; kept
# out of git because it embeds absolute paths. Lives at the project root
# (../fusesoc/ from this env.sh).
DVBENCH_FUSESOC_CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fusesoc/fusesoc.conf"
