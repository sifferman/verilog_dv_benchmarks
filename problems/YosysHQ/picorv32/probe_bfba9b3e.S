# probe_bfba9b3e.S — exercises the picorv32_pcpi_fast_mul signed-mul bug
# fixed by bfba9b3.
#
# Bug: `rd <= rs1 * rs2` was an unsigned multiply. For `mulh` (the high
# 32 bits of signed*signed), this produces the wrong upper word whenever
# either operand is negative. The fix uses `$signed(rs1) * $signed(rs2)`.
#
# Probe:
#   a1 = a2 = -1 (0xFFFFFFFF). mulh a3, a1, a2 — signed (-1) * (-1) = 1,
#   high 32 bits = 0x00000000.
#     Fixed RTL: a3 = 0x00000000.
#     Buggy RTL: unsigned 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001,
#                high half = 0xFFFFFFFE.
#   Marker = a3. Oracle requires 0x00000000.
#
# Requires PARAM_ENABLE_FAST_MUL so the fast_mul PCPI coprocessor is built in.

        .text
        .globl  _start
_start:
        lui     a0, 0x20000        # success-marker addr
        li      a1, -1
        li      a2, -1
        mulh    a3, a1, a2         # signed*signed high half
        sw      a3, 0(a0)
        ebreak
