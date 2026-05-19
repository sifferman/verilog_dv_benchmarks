# probe_bb9ebeb9.S — exercises the jalr-target lsb bug fixed by bb9ebeb9.
#
# Bug: when computing `next_pc` for a `jalr`, the buggy RTL used `reg_out`
# directly instead of `reg_out & ~1`. RISC-V spec requires bit 0 of the
# jalr target to be ignored (jalr xN, 0  with xN odd should still produce
# an even PC). The buggy core takes the odd PC, fetches the next
# instruction at the misaligned address, and traps via CATCH_MISALIGN.
#
# Program:
#   - Build a1 = address-of-ok_target | 1 (i.e. with bit 0 set).
#   - jalr x0, a1, 0 — fixed RTL masks bit 0 and jumps to ok_target.
#                       buggy RTL preserves bit 0 and traps on misalign.
#   - ok_target writes the success value to 0x20000000 and ebreak.
#
# Oracle: success_marker_written && success_register == 0xC001D00D.

        .text
        .globl  _start
_start:
        lui     a0, 0x20000        # a0 = 0x20000000 (success-marker addr)
        la      a1, ok_target      # a1 = absolute addr of ok_target
        ori     a1, a1, 1          # set bit 0 → odd
        jalr    x0, a1, 0          # jump indirect (no link)
        ebreak                     # unreachable on fixed RTL

        .balign 4
ok_target:
        li      a2, 0xC001D00D
        sw      a2, 0(a0)
        ebreak
