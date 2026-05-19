// DPI side of run_instructions.sv (cva6 probe harness).
//
// Mirrors problems/YosysHQ/picorv32/run_instructions.cpp but adapted for an
// AXI bus where writes arrive as (longint addr, longint data64): the SV
// snooper provides per-beat byte address + the full 64-bit beat data; we
// extract the 32-bit half that lines up with SUCCESS_ADDR.
//
// Environment inputs:
//   SUCCESS_ADDR    — address the probe writes to mark success. Default
//                     0x20000000. Must be 4-byte aligned.
//   EXPECTED_VALUE  — optional 32-bit value the probe is expected to write.
//                     If unset, any write to SUCCESS_ADDR ends sim PASS.
//
// Pass/fail signalling:
//   - dpi_observe_write captures any AXI write beat. If the address window of
//     the beat covers SUCCESS_ADDR, we record the relevant 32-bit lane and
//     either PASS (no expected value, or expected value matches) or FAIL
//     (expected value mismatch).
//   - dpi_poll_done returns 0 until the verdict is set, then 1 (pass) or 2
//     (fail). The SV harness polls every cycle.

#include <cstdint>
#include <cstdio>
#include <cstdlib>

namespace {

uint64_t g_success_addr   = 0x20000000ull;
uint32_t g_expected_value = 0;
bool     g_has_expected   = false;

// 0 = continue, 1 = pass, 2 = fail.
int      g_verdict        = 0;

}  // namespace

extern "C" void dpi_init() {
    if (const char* env = std::getenv("SUCCESS_ADDR")) {
        g_success_addr = std::strtoull(env, nullptr, 0);
    }
    if (const char* env = std::getenv("EXPECTED_VALUE")) {
        g_expected_value = static_cast<uint32_t>(std::strtoul(env, nullptr, 0));
        g_has_expected   = true;
    }
    std::fprintf(stderr,
                 "dpi_init: success_addr=0x%016lx expected=%s%08x\n",
                 (unsigned long)g_success_addr,
                 g_has_expected ? "0x" : "(any) 0x",
                 g_expected_value);
}

extern "C" void dpi_observe_write(long long addr, long long data) {
    // Each W beat is 8 bytes wide (DataWidth=64). Determine which 32-bit lane
    // (low/high) of this beat covers SUCCESS_ADDR.
    uint64_t beat_addr = static_cast<uint64_t>(addr) & ~uint64_t{7};
    uint64_t beat_data = static_cast<uint64_t>(data);
    if (beat_addr > g_success_addr || beat_addr + 8 <= g_success_addr) return;

    uint32_t observed;
    if ((g_success_addr & 0x4) == 0) {
        observed = static_cast<uint32_t>(beat_data & 0xFFFFFFFFu);
    } else {
        observed = static_cast<uint32_t>((beat_data >> 32) & 0xFFFFFFFFu);
    }

    if (g_has_expected && observed != g_expected_value) {
        std::fprintf(stderr,
                     "FAIL: write to 0x%016lx = 0x%08x, expected 0x%08x.\n",
                     (unsigned long)g_success_addr, observed, g_expected_value);
        g_verdict = 2;
        return;
    }
    std::fprintf(stderr, "PASS: write to 0x%016lx = 0x%08x.\n",
                 (unsigned long)g_success_addr, observed);
    g_verdict = 1;
}

extern "C" int dpi_poll_done() {
    return g_verdict;
}
