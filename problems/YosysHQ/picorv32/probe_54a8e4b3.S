# probe_54a8e4b3.S — exercises the misaligned-jump-catch bug fixed by 54a8e4b.
#
# Bug: picorv32 used to silently mask `reg_pc[1:0]` and `reg_next_pc[1:0]` to
# zero on every commit, even when CATCH_MISALIGN was enabled. That hid the
# misaligned-instruction trap entirely — a `jalr` to a target with bit 1 set
# would silently realign down and execute the aligned instruction. The fix
# only masks PC bits when `!CATCH_MISALIGN`, so with CATCH_MISALIGN=1 the
# trap fires as the spec requires.
#
# Strategy:
#   - Write the CORRECT marker (0xC001D00D) to 0x20000000.
#   - jalr to a misaligned address 0x1A (bit 1 set).
#       Fixed RTL: traps on misalign before fetching anywhere new -> oracle
#                  sees correct marker -> PASS.
#       Buggy RTL: silently masks 0x1A -> 0x18 -> executes the OVERWRITE
#                  block at 0x18 which stores 0xDEADBEEF and ebreaks ->
#                  oracle sees wrong marker -> FAIL.
#
# Requires the default CATCH_MISALIGN=1 (no PARAM override needed).

        .text
        .globl  _start
_start:                                # PC=0x00
        lui     a0, 0x20000             #     a0 = 0x20000000
        li      a4, 0xC001D00D          # PC=0x04, 0x08 (lui+addi)
        sw      a4, 0(a0)               # PC=0x0C  write CORRECT marker
        addi    a1, x0, 0x1A            # PC=0x10  a1 = misaligned target
        jalr    x0, a1, 0               # PC=0x14  -> 0x1A
        # PC=0x18 is the buggy landing pad (after masking off bits[1:0]).
        .balign 4
overwrite_marker:                       # PC=0x18
        li      a4, 0xDEADBEEF          # PC=0x18, 0x1C (lui+addi)
        sw      a4, 0(a0)               # PC=0x20  buggy: overwrites with WRONG marker
        ebreak                          # PC=0x24
