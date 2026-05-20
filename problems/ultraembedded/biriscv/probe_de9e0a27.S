# Focused probe for biriscv commit de9e0a2:
#   "Additional support for routing external (and timer) interrupts to
#    supervisor mode (if enabled via csr_mideleg)."
#
# Buggy parent (0eb3e43): csr_regfile unconditionally sets
#   csr_mip_next_r[SR_IP_MEIP_R] = 1 when ext_intr_i is asserted, regardless
#   of csr_mideleg_q. So MIP[11] (MEIP) is observed set, MIP[9] (SEIP) is 0.
#
# Fixed (de9e0a2): when mideleg[MEIP_R] is set, ext_intr_i routes to
#   csr_mip_next_r[SR_IP_SEIP_R] instead. So MIP[9] (SEIP) is set,
#   MIP[11] (MEIP) is 0.
#
# Probe:
#   1. Mask interrupts (MSTATUS.MIE=0, MIE=0) so we never take a trap.
#   2. Set MIDELEG bit 11 (delegate ext interrupt to S).
#   3. Wait long enough for ext_intr_i to be sampled (TB pulses it high).
#   4. Read MIP, isolate bits 11 (MEIP) and 9 (SEIP).
#   5. If MIP[11]=1 -> buggy path, FAIL.
#      If MIP[9]=1  -> fixed path, PASS.

        .text
        .globl  _start

        .equ    CSR_SIM_CTRL, 0x8b2
        .equ    CSR_MSTATUS,  0x300
        .equ    CSR_MIE,      0x304
        .equ    CSR_MIDELEG,  0x303
        .equ    CSR_MIP,      0x344

_start:
        # Mask all interrupts.
        csrw    CSR_MSTATUS, x0
        csrw    CSR_MIE,     x0

        # Delegate external interrupt to S-mode.
        li      t0, 0x800            # bit 11 = MEIP
        csrw    CSR_MIDELEG, t0

        # Spin long enough for the TB's ext_intr_i pulse to register.
        li      t1, 64
spin:
        addi    t1, t1, -1
        bnez    t1, spin

        # Read MIP.
        csrr    a0, CSR_MIP

        # Test MIP[11] (MEIP); if set -> buggy.
        li      t2, 0x800
        and     t3, a0, t2
        bnez    t3, fail

        # Test MIP[9] (SEIP); if set -> fixed.
        li      t2, 0x200
        and     t3, a0, t2
        bnez    t3, pass

        # Neither bit set -> probe is wrong, treat as fail.
        j       fail

pass:
        # Print "PASS\n".
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

fail:
        # Print "FAIL\n".
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
