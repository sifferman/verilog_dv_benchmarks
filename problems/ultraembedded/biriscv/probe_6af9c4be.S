# Focused probe for biriscv v0.8.1 (6af9c4b):
#   "Improve xRET instruction support (sret, mret, ...)"
#
# Buggy parent (5614f5c == v0.8): INST_MRET_MASK was 0xdfffffff which clears
# bit 29 of the opcode — so `sret` (0x10200073) decodes as `mret`. The CSR
# unit then routes the ERET branch to MEPC unconditionally.
#
# Fixed (6af9c4b): the instruction is matched with INST_ERET_MASK (0xcfffffff),
# eret_priv_w = opcode[29:28], and the branch target is csr_mepc_q only when
# the encoded priv level is MACHINE; otherwise (SRET) it routes to csr_sepc_q.
#
# Probe:
#   1. Write MEPC = address of fail_marker.
#   2. Write SEPC = address of pass_marker.
#   3. Execute `sret`.
#   4. Buggy core: jumps to MEPC -> prints FAIL.
#   5. Fixed core: jumps to SEPC -> prints PASS.

        .text
        .globl  _start

        # Magic CSR_SIM_CTRL (0x8b2):
        #     write 0x01_XX_XX_XX -> putc(XX)
        #     write 0x00_00_00_00 -> $finish
        .equ    CSR_SIM_CTRL, 0x8b2
        .equ    CSR_MEPC,     0x341
        .equ    CSR_SEPC,     0x141
        .equ    CSR_MSTATUS,  0x300
        .equ    CSR_MIE,      0x304

_start:
        # Make sure we are in machine mode with interrupts off.
        csrw    CSR_MSTATUS, x0
        csrw    CSR_MIE,     x0

        # MEPC <- fail_marker (8-byte aligned via labels)
        la      t0, fail_marker
        csrw    CSR_MEPC, t0

        # SEPC <- pass_marker
        la      t1, pass_marker
        csrw    CSR_SEPC, t1

        # Execute SRET. In buggy RTL this is decoded as MRET and the CPU
        # branches to MEPC (fail_marker). In fixed RTL it branches to SEPC
        # (pass_marker).
        sret

        # Should never reach here.
        j       fail_marker

        .balign 4
pass_marker:
        # Print "PASS\n" then exit.
        li      a1, 0x01000050
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x01000041
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x01000053
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x01000053
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x0100000A
        csrw    CSR_SIM_CTRL, a1
        csrw    CSR_SIM_CTRL, x0
1:      j       1b

        .balign 4
fail_marker:
        # Print "FAIL\n" then exit.
        li      a1, 0x01000046
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x01000041
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x01000049
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x0100004C
        csrw    CSR_SIM_CTRL, a1
        li      a1, 0x0100000A
        csrw    CSR_SIM_CTRL, a1
        csrw    CSR_SIM_CTRL, x0
2:      j       2b
