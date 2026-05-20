// Focused unit test for VeeR EL2 c.lwsp rd==0 illegal-instruction fix
// (commit 550b335, 2024-08-20).
//
// Bug: el2_ifu_compress_ctl.sv accepted c.lwsp with rd==0 as a legal
// compressed instruction. RISC-V spec marks "c.lwsp x0, ..." as reserved
// (rd!=0 required). The fix replaces the wide `c.lwsp` espresso term with
// the union of c.lwsp{0..4} which require at least one bit of rd[4:0] to
// be set.
//
// Probe: din = 16'h4002 = [15:13]=010 (c.lwsp funct3), [12]=0 (imm[5]),
// [11:7]=00000 (rd=x0), [6:2]=00000 (imm[4:2,7:6]), [1:0]=10 (op).
// This is "c.lwsp x0, 0(x2)" -- reserved encoding per RISC-V spec.
//   Fixed RTL:  legal=0 -> dout=0       -> PASS.
//   Buggy RTL:  legal=1 -> dout != 0    -> FAIL.

`timescale 1ns/1ps
module tb_550b3353;

  logic [15:0] din;
  logic [31:0] dout;

  el2_ifu_compress_ctl dut (
    .din  (din),
    .dout (dout)
  );

  initial begin
    // c.lwsp x0, 0(x2) -- reserved encoding per RISC-V spec
    din = 16'h4002;
    #1;
    if (dout == 32'd0) begin
      $display("PASS: c.lwsp rd=x0 produces dout=0 (illegal as expected).");
      $finish;
    end else begin
      $display("FAIL: c.lwsp rd=x0 produced non-zero dout=%h (decoded as legal).", dout);
      $fatal(1, "buggy compress_ctl accepted reserved c.lwsp rd=x0");
    end
  end
endmodule
