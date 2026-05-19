# probe_aa17d587.S — exercises the C.SRAI decode bug fixed by aa17d58.
#
# Bug: the C.SRAI decode check was `mem_rdata_latched[11:10] == 2'b00`, but
# bits[11:10]=00 is the encoding for C.SRLI; C.SRAI is 2'b01. The buggy
# decoder rewrote both C.SRLI and C.SRAI as SRAI (arithmetic shift), so a
# C.SRLI of a negative value sign-extended instead of zero-extending.
#
# Probe:
#   a3 = 0x80000000, then c.srli a3, 1.
#   Fixed RTL: 0x80000000 >> 1 logically -> a3 = 0x40000000.
#   Buggy RTL: misdecoded as SRAI -> 0x80000000 >>> 1 -> a3 = 0xC0000000.
#   Marker = result. Oracle requires 0x40000000.

        .text
        .option rvc
        .globl  _start
_start:
        lui     a0, 0x20000        # success-marker addr
        lui     a3, 0x80000        # a3 = 0x80000000 (msb set, lower 20 = 0)
        c.srli  a3, 1              # logical shift right by 1
        sw      a3, 0(a0)
        ebreak
