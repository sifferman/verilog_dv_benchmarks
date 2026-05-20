#!/usr/bin/env bash
# Run the VeeR-EL2 default verilator testbench (hello_world test from canned hex).
# Exits 0 only if the simulation prints TEST_PASSED, non-zero on TEST_FAILED or build error.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../env.sh"

REPO_DIR="$(cd "$SCRIPT_DIR/../../../clones/chipsalliance/Cores-VeeR-EL2" && pwd)"
export RV_ROOT="$REPO_DIR"
TEST="${TEST:-icache}"

# Tools we install on demand: meson (for picolibc, sidestepped via fake GCC_PREFIX)
# and Perl Bit::Vector. Make them visible if they were pip-installed.
if [ -d "$HOME/.local/bin" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
if [ -d "$HOME/perl5/lib/perl5" ]; then
    export PERL5LIB="$HOME/perl5/lib/perl5/x86_64-linux-gnu-thread-multi:$HOME/perl5/lib/perl5:$PERL5LIB"
fi

# Force canned-hex path by hiding riscv64-unknown-elf-gcc (avoids picolibc build).
NO_RISCV_PATH="$(echo "$PATH" | tr ':' '\n' | grep -v 'riscv' | paste -sd: -)"

BUILD_DIR="${BUILD_DIR:-/tmp/veer_el2_build_$$}"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$BUILD_DIR"
LOG="$BUILD_DIR/run.log"
PATH="$NO_RISCV_PATH" make -f "$RV_ROOT/tools/Makefile" verilator \
    TEST="$TEST" \
    GCC_PREFIX=riscv-MISSING \
    CFLAGS="-std=c++17 -I$RV_ROOT/testbench/tcp_server -I$RV_ROOT/testbench/jtagdpi" \
    >"$LOG" 2>&1
RC=$?
if [ $RC -ne 0 ]; then
    echo "BUILD/RUN FAILED rc=$RC" >&2
    tail -80 "$LOG" >&2
    exit $RC
fi

if grep -q '^TEST_PASSED' "$LOG"; then
    echo "TEST_PASSED"
    exit 0
fi
echo "TEST_FAILED (no TEST_PASSED marker)" >&2
tail -40 "$LOG" >&2
exit 1
