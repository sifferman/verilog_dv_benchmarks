// Focused unit test for cv32e40x b_decoder zext.h rs2 reserved-field check
// (commit 8950d68, 2021-11-25).
//
// Bug: zext.h matches funct7=0000100, funct3=100 under OPCODE_OP. The Zbb
// spec mandates rs2 (instr_rdata_i[24:20]) be zero. The original case
// statement ignored that field, so encodings with rs2 != 0 were silently
// accepted as legal zext.h. The fix adds:
//   if (instr_rdata_i[24:20] != 5'b00000) decoder_ctrl_o = ILLEGAL_INSN;
//
// Probe: zext.h-shaped encoding with rs2=5 (non-zero -> reserved).
// funct7=0000100, rs2=00101, rs1=00000, funct3=100, rd=00000,
// opcode=OPCODE_OP (7'h33). -> 32'h08504033.
//   Fixed RTL:    illegal_insn = 1 (rs2!=0 caught)   -> PASS.
//   Buggy RTL:    illegal_insn = 0 (rs2 ignored)     -> FAIL.

`timescale 1ns/1ps
module tb_cv32e40x_b_decoder_zexth_rs2;

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
    // zext.h-shaped instruction with rs2=5 (reserved-non-zero) -> 0x08504033
    instr_rdata = 32'h0850_4033;
    #1;
    if (decoder_ctrl.illegal_insn) begin
      $display("PASS: zext.h with rs2=5 flagged illegal_insn=1.");
      $finish;
    end else begin
      $display("FAIL: zext.h-shaped with rs2=5 accepted (illegal_insn=0).");
      $fatal(1, "buggy b_decoder did not check zext.h rs2 reserved bits");
    end
  end
endmodule
