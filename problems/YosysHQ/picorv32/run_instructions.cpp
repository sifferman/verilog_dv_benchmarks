// DPI side of run_instructions.sv. Memory + oracle live here so the SV TB
// can stay stateless. Verilator links this in via --exe.
//
// Environment inputs:
//   PROBE_BIN       — path to a raw little-endian binary (one 32-bit instr
//                     per word, .text only). Output of:
//                       riscv32-unknown-elf-as -march=rv32i probe.S -o probe.o
//                       riscv32-unknown-elf-objcopy -O binary -j .text probe.o probe.bin
//   EXPECTED_VALUE  — optional. If set, dpi_on_trap requires the last 32-bit
//                     value written to 0x20000000 to equal this (hex/dec/octal
//                     accepted via strtoul base=0).
//   SUCCESS_ADDR    — optional. Override the magic write address. Default
//                     0x20000000 (matches the picorv32 bundled testbench).
//
// Oracle (in dpi_on_trap): PASS iff (a) success_marker_written is true and
// (b) if EXPECTED_VALUE was provided, success_register equals it. Otherwise
// FAIL.

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {

constexpr size_t PROG_WORDS = 1u << 14;  // 64 KiB / 4
uint32_t       g_prog[PROG_WORDS] = {0};

uint32_t       g_success_addr     = 0x2000'0000u;
uint32_t       g_success_register = 0;
bool           g_success_written  = false;

uint32_t       g_expected_value = 0;
bool           g_has_expected   = false;

void load_probe(const char* path) {
    FILE* fp = std::fopen(path, "rb");
    if (!fp) {
        std::fprintf(stderr, "dpi_init: cannot open PROBE_BIN=%s\n", path);
        std::exit(2);
    }
    size_t n = std::fread(g_prog, sizeof(uint32_t), PROG_WORDS, fp);
    std::fclose(fp);
    std::fprintf(stderr, "dpi_init: loaded %zu words from %s\n", n, path);
}

}  // namespace

extern "C" void dpi_init() {
    const char* probe = std::getenv("PROBE_BIN");
    if (!probe) {
        std::fprintf(stderr, "dpi_init: PROBE_BIN env not set\n");
        std::exit(2);
    }
    load_probe(probe);

    if (const char* addr_env = std::getenv("SUCCESS_ADDR")) {
        g_success_addr = static_cast<uint32_t>(std::strtoul(addr_env, nullptr, 0));
    }

    if (const char* exp_env = std::getenv("EXPECTED_VALUE")) {
        g_expected_value = static_cast<uint32_t>(std::strtoul(exp_env, nullptr, 0));
        g_has_expected   = true;
    }
}

extern "C" int dpi_read_word(int addr) {
    uint32_t word_addr = static_cast<uint32_t>(addr) >> 2;
    if (word_addr >= PROG_WORDS) return 0;
    return static_cast<int>(g_prog[word_addr]);
}

extern "C" void dpi_observe_write(int addr, int data, int /*wstrb*/) {
    if (static_cast<uint32_t>(addr) == g_success_addr) {
        g_success_register = static_cast<uint32_t>(data);
        g_success_written  = true;
    }
}

extern "C" int dpi_on_trap() {
    if (!g_success_written) {
        std::fprintf(stderr,
                     "FAIL: trap fired before any write to success addr 0x%08x.\n",
                     g_success_addr);
        return 1;
    }
    if (g_has_expected && g_success_register != g_expected_value) {
        std::fprintf(stderr,
                     "FAIL: success register = 0x%08x, expected 0x%08x.\n",
                     g_success_register, g_expected_value);
        return 1;
    }
    std::fprintf(stderr, "PASS: success register = 0x%08x.\n", g_success_register);
    return 0;
}
