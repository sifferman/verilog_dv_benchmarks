# probe_bf968702.S — exercises the "0x67 with non-zero funct3 decoded as jalr"
# bug fixed by bf96870.
#
# Bug: instr_jalr was set from opcode == 7'b1100111 only. The RV32I spec
# requires funct3 == 000 as well, so encodings like (opcode=0x67, funct3=001)
# are reserved/illegal. The buggy decoder silently treated them as jalr,
# producing a jump to rs1 + imm.
#
# Probe strategy: write the success marker FIRST, then emit a hand-encoded
# word with opcode=0x67 and funct3=001 (rs1=x0, rd=x0, imm=0):
#   Fixed RTL: traps as illegal instruction -> dpi_on_trap sees marker -> PASS.
#   Buggy RTL: treats as `jalr x0, 0(x0)` -> jumps to PC=0 -> infinite loop ->
#              watchdog $fatal -> FAIL (the simulator exits non-zero).
#
# Oracle: success_marker_written && success_register == 0xC001D00D.

        .text
        .globl  _start
_start:
        lui     a0, 0x20000        # a0 = 0x20000000 (success-marker addr)
        li      a4, 0xC001D00D     # success value
        sw      a4, 0(a0)          # write marker first
        .word   0x00001067         # opcode=0x67, funct3=001 — illegal per RV32I
        ebreak                     # unreachable on fixed RTL (trap fires above)
