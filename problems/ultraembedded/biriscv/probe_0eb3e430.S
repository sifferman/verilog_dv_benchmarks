# Focused probe for biriscv v0.7 bug fix (0eb3e43):
#   "Remove write support on cycle counter register"
#
# The buggy v0.6 csr_regfile accepted CSRRW to CSR_MCYCLE (0xc00) and
# CSR_MTIME (0xc01) — the case statement updated csr_mcycle_r with the
# user value. v0.7 removes those lines so writes are silently ignored.
#
# Probe:
#   1. Disable interrupts.
#   2. Write 0 to CSR_MCYCLE.
#   3. Spin for ~16 ticks so the counter increments substantially.
#   4. Read CSR_MCYCLE -> a0.
#   5. If a0 < 0x100, the write was honored (buggy) -> FAIL.
#      If a0 >= 0x100, the counter ran from where it had been (fixed) -> PASS.
#
# The buggy core would also reset MCYCLE to 0 from whatever it was;
# after ~16 nops it should still be far below 0x100. The fixed core
# leaves MCYCLE running normally and the value at read time is the
# total cycle count from reset (well above 0x100 by then).
#
# Magic CSR_SIM_CTRL (0x8b2):
#     write 0x01_XX_XX_XX -> putc(XX)
#     write 0x00_00_00_00 -> $finish

        .text
        .globl  _start
_start:
        # Make sure we are in machine mode with interrupts off.
        csrwi   mstatus, 0
        csrwi   mie, 0

        # Try to clobber CSR_MCYCLE with a huge sentinel value. On the
        # buggy core the write is honoured and MCYCLE jumps to ~0xDEADBEEF
        # +/- a few. On the fixed core the write is silently ignored and
        # MCYCLE keeps the small natural cycle count.
        li      t0, 0xDEADBEEF
        csrrw   x0, 0xc00, t0

        # Burn a handful of cycles so the read is observable in either case.
        li      t1, 8
spin:
        addi    t1, t1, -1
        bnez    t1, spin

        # Capture MCYCLE.
        csrrs   a0, 0xc00, x0

        # Pass/fail: if a0 >= 0x80000000 (sentinel survived the write),
        # the core is buggy. Otherwise the write was ignored, fixed RTL.
        srli    t2, a0, 31
        bnez    t2, fail

pass:
        # Print "PASS\n" then exit.
        li      a1, 0x01000050       # 'P'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x01000041       # 'A'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x01000053       # 'S'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x01000053       # 'S'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x0100000A       # '\n'
        csrrw   x0, 0x8b2, a1
        li      a1, 0
        csrrw   x0, 0x8b2, a1        # SIM_CTRL_EXIT
1:      j       1b

fail:
        # Print "FAIL\n" then exit.
        li      a1, 0x01000046       # 'F'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x01000041       # 'A'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x01000049       # 'I'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x0100004C       # 'L'
        csrrw   x0, 0x8b2, a1
        li      a1, 0x0100000A       # '\n'
        csrrw   x0, 0x8b2, a1
        li      a1, 0
        csrrw   x0, 0x8b2, a1        # SIM_CTRL_EXIT
2:      j       2b
