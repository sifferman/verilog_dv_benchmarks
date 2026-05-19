# probe_2cab9818.S — exercises the signed-div-by-zero bug fixed by 2cab981.
#
# Bug: in picorv32_pcpi_div, `outsign` for signed `div` was set whenever the
# sign bits of rs1 and rs2 differed, regardless of whether rs2 was zero.
# When rs1 was negative and rs2 was zero, the buggy core negated the all-ones
# quotient produced by the divide-by-zero shift loop, returning 1 instead of
# the spec-mandated -1 (0xFFFFFFFF). The fix ANDs in `|pcpi_rs2` so the
# negation is skipped when the divisor is zero.
#
# Probe:
#   a1 = -1, a3 = 0, then `div a2, a1, a3` (divide by zero).
#   Fixed RTL: a2 = 0xFFFFFFFF  (spec: signed div-by-0 returns -1).
#   Buggy RTL: a2 = 0x00000001  (negated all-ones quotient).
#   Store a2 to 0x20000000 as the success marker; oracle requires 0xFFFFFFFF.
#
# Requires PARAM_ENABLE_DIV so ENABLE_PCPI + ENABLE_DIV are both set.

        .text
        .globl  _start
_start:
        lui     a0, 0x20000        # success-marker addr
        li      a1, -1             # rs1 (negative)
        li      a3, 0              # rs2 (zero divisor)
        div     a2, a1, a3         # signed divide; spec says result = -1
        sw      a2, 0(a0)          # marker = result
        ebreak
