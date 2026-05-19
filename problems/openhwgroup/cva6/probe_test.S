# Smoke-test probe for the cva6 .S harness.
#
# Boots at 0x0 in M-mode, writes 0xCAFE0001 to the success address, then
# busy-loops. The harness watches the AXI bus for the magic-address write
# and ends simulation PASS the moment it sees it. Crashes never reach the
# success write, so the watchdog catches them as FAIL.
#
# The runner exports SUCCESS_ADDR=0x20000000 and EXPECTED_VALUE=0xCAFE0001.

    .section .text
    .globl _start
_start:
    li      t0, 0x20000000     # success addr
    li      t1, 0xCAFE0001     # expected value
    sw      t1, 0(t0)
    fence
1:  j       1b
