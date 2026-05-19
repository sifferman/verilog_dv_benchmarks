# probe_29102c00.S — exercises the fence-decode bug fixed by 29102c0.
#
# Bug: the rv32i `fence` instruction was decoded as illegal and trapped.
# Fix: a single decode line was added. See picorv32 issue #228, PR #229.
#
# Program: write the value 0xCAFE0001 to 0x20000000 (success marker), but
# put a `fence` *before* the store. On the fixed RTL, fence is a NOP and
# the store happens. On the buggy RTL, fence traps as illegal instr before
# the store, so success_marker_written stays 0 and the oracle fires FAIL.

        .text
        .globl  _start
_start:
        lui     a0, 0x20000        # a0 = 0x20000000
        fence   iorw, iorw         # the bug — buggy RTL traps here
        li      a1, 0xCAFE0001     # success value
        sw      a1, 0(a0)
        ebreak
