// Focused unit test for cv32e40s a_decoder lsu_size fix
// (commit 242887b, 2023-02-10). Repo-internal file name at this commit was
// rtl/cv32e40x_a_decoder.sv (pre-rename).
//
// Bug: AMO instructions are all word-sized (funct3=010 only). The a_decoder
// hard-coded `decoder_ctrl_o.lsu_size = 2'b00` (byte). The encoding for
// lsu_size in e40x is taken directly from funct3 (00=Byte, 01=Half, 10=Word).
// Old code from cv32e40p used a different lsu_size encoding so 2'b00 happened
// to be "Word" there. On e40x this drives the LSU to a byte access. The fix
// changes it to `lsu_size = 2'b10` (Word).
//
// Probe: lr.w x0, (x0). funct5=00010, aq=0, rl=0, rs2=00000, rs1=00000,
// funct3=010, rd=00000, opcode=OPCODE_AMO(7'h2F). -> 32'h1000202F.
//   Fixed RTL:   decoder_ctrl.lsu_size == 2'b10 -> PASS.
//   Buggy RTL:   decoder_ctrl.lsu_size == 2'b00 -> FAIL.

`timescale 1ns/1ps
module tb_cv32e40s_a_decoder_lsusize;

  import cv32e40x_pkg::*;

  logic [31:0]    instr_rdata;
  decoder_ctrl_t  decoder_ctrl;

  cv32e40x_a_decoder dut (
      .instr_rdata_i (instr_rdata),
      .decoder_ctrl_o(decoder_ctrl)
  );

  initial begin
    // lr.w x0, (x0) -> 0x1000202F
    instr_rdata = 32'h1000_202F;
    #1;
    if (decoder_ctrl.illegal_insn) begin
      $display("FAIL: lr.w flagged illegal (decoder said illegal_insn=1).");
      $fatal(1, "decoder rejected legal AMO");
    end
    if (decoder_ctrl.lsu_size === 2'b10) begin
      $display("PASS: AMO decoded with lsu_size=2'b10 (Word).");
      $finish;
    end else begin
      $display("FAIL: AMO decoded with lsu_size=%b (expected 2'b10 Word).",
               decoder_ctrl.lsu_size);
      $fatal(1, "buggy a_decoder still uses cv32e40p lsu_size encoding");
    end
  end
endmodule
