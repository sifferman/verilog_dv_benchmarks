// Focused unit test for cv32e40x b_decoder sext.h encoding fix
// (commit 973e0f4, 2021-11-25).
//
// Bug: sext.h case in the OPCODE_OPIMM branch of the Zbb sub-decoder used
//   {7'b110_0000, 5'b0_0101, 3'b001}  (funct7 = 7'b1100000)
// which is *not* the Zbb-defined encoding (and has bit 31=1, which would be
// reserved). The fix changes it to
//   {7'b011_0000, 5'b0_0101, 3'b001}  (funct7 = 7'b0110000)
// matching the Zbb sext.h encoding from the spec. (The same commit also adds
// the zext.h instruction, but the sext.h fix is the cleanest observable.)
//
// Probe: legal sext.h on x0 = sext.h(x0). Encoding = funct7=0110000,
// rs2=00101, rs1=00000, funct3=001, rd=00000, opcode=OPIMM(7'h13).
// -> 32'h60501013.
//   Fixed RTL:    illegal_insn = 0 (sext.h recognized)         -> PASS.
//   Buggy RTL:    illegal_insn = 1 (encoding does not match)   -> FAIL.

`timescale 1ns/1ps
module tb_cv32e40x_b_decoder_sexth;

  import cv32e40x_pkg::*;

  logic [31:0]    instr_rdata;
  decoder_ctrl_t  decoder_ctrl;

  cv32e40x_b_decoder #(
      .B_EXT (ZBA_ZBB_ZBS)
  ) dut (
      .instr_rdata_i (instr_rdata),
      .decoder_ctrl_o(decoder_ctrl)
  );

  initial begin
    // sext.h x0, x0  -> 0x60501013
    instr_rdata = 32'h6050_1013;
    #1;
    if (decoder_ctrl.illegal_insn) begin
      $display("FAIL: sext.h (0x60501013) flagged illegal_insn=1 with Zbb enabled.");
      $fatal(1, "buggy b_decoder used wrong sext.h funct7 encoding");
    end else begin
      $display("PASS: sext.h recognized (illegal_insn=0, alu_operator=%0d).",
               decoder_ctrl.alu_operator);
      $finish;
    end
  end
endmodule
