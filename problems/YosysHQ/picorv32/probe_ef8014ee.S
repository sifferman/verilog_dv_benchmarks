# probe_ef8014ee.S — exercises the two C.ADDI4SPN decode bugs fixed by ef8014e.
#
# Bugs (both pre-fix):
#   1. The constructed immediate for the underlying `addi sp, sp, nzuimm`
#      was missing the trailing 2'b00, so nzuimm was effectively scaled 1/4.
#   2. `decoded_rd <= 8 + mem_rdata_latched[9:7]` should have been
#      `8 + mem_rdata_latched[4:2]`. The rd' field of C.ADDI4SPN lives in
#      bits[4:2], not bits[9:7]; the buggy core wrote to the wrong register.
#
# Probe:
#   sp = 0x100; a4 initialized to 0xBAD (a known bad sentinel);
#   `c.addi4spn a4, sp, 16` — should set a4 = sp + 16 = 0x110.
#     Fixed RTL:  a4 = 0x110 (both fields correct).
#     Buggy RTL:  rd' decode is wrong, so a4 stays 0xBAD (and s0 gets 0x104
#                 from the misaligned immediate as a side effect).
#   Marker = a4; oracle requires 0x110.

        .text
        .option rvc
        .globl  _start
_start:
        lui        a0, 0x20000     # success-marker addr
        li         sp, 0x100       # sp = 0x100 (known base)
        li         a4, 0xBAD       # sentinel — buggy RTL leaves a4 == 0xBAD
        c.addi4spn a4, sp, 16      # fixed: a4 = sp + 16 = 0x110
        sw         a4, 0(a0)
        ebreak
