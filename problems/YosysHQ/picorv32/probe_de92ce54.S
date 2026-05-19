# probe_de92ce54.S — exercises the RV32E shift-amount width bug fixed by de92ce5.
#
# Bug: with ENABLE_REGS_16_31=0, `decoded_rs2` was declared `regindex_bits-1:0`
# (4 bits), so shift instructions saw shamt[3:0] instead of shamt[4:0]. A
# `slli a1, a1, 16` silently behaved as `slli a1, a1, 0`. The fix declares
# decoded_rs2 as `[4:0]` regardless of regindex_bits. See picorv32 issue #211.
#
# Program: compute (1 << 16) and write the result to 0x20000000. The oracle
# checks `success_register == 32'h00010000`. Buggy RTL writes 0x1; fixed
# writes 0x10000.
#
# Note: the testbench instantiates picorv32 with ENABLE_REGS_16_31=0 via a
# --param override at scaffold time.

        .text
        .globl  _start
_start:
        lui     a0, 0x20000        # a0 = 0x20000000
        addi    a1, x0, 1          # a1 = 1
        slli    a1, a1, 16         # a1 = a1 << 16 (buggy: still 1)
        sw      a1, 0(a0)
        ebreak
