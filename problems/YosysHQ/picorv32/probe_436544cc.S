# probe_436544cc.S — exercises the C.ADDI HINT-encoding bug fixed by 436544c.
#
# History: bf96870 added a guard to reject C.ADDI encodings with rd=x0 and
# non-zero immediate (then-believed reserved by the ISA manual). 436544c
# removed that guard after the ISA manual was clarified — those encodings
# are HINT space and must be accepted as an effective NOP.
#
# Probe: execute the compressed `c.addi x0, 1` encoding (0x0005) BEFORE
# writing the success marker. A `c.nop` (0x0001) trails it to keep the
# stream aligned.
#
#   Fixed RTL: c.addi x0, 1 -> effective NOP -> store marker -> ebreak -> PASS.
#   Buggy RTL: c.addi x0, 1 not latched into any instr_* flag -> trap fires
#              as an illegal-instruction (or the CPU stalls) BEFORE the
#              marker store -> FAIL (marker not written).
#
# Requires PARAM_COMPRESSED so picorv32 is built with COMPRESSED_ISA=1'b1.

        .text
        .option rvc
        .globl  _start
_start:
        lui     a0, 0x20000        # success-marker addr

        .half   0x0005             # c.addi x0, 1 — the corner-case HINT
        .half   0x0001             # c.nop (alignment filler)

        li      a4, 0xC001D00D
        sw      a4, 0(a0)          # write marker AFTER the corner-case insn

        ebreak
