// Focused unit test for cv32e40s m_decoder div/rem-with-no-divider fix
// (commit 145c622b, 2022-01-21). Repo-internal file name at this commit was
// rtl/cv32e40x_m_decoder.sv (pre-rename).
//
// Bug: When M_EXT is configured for ZMMUL (multiplier present but no
// divider), the m_decoder's div/divu/rem/remu cases evaluated their
// `if (M_EXT == M)` guard and, when false, fell through with no
// assignment. Because the default `decoder_ctrl_o.illegal_insn = 1'b0`
// stayed set (the per-OP common signals also write rf_we/rf_re), the
// decoded instruction was accepted as legal even though the divider is
// not configured. The fix adds the missing
// `else: decoder_ctrl_o = DECODER_CTRL_ILLEGAL_INSN;` arm in each of
// the four div/divu/rem/remu cases.
//
// Probe: div x0, x0, x0 (funct7=0000001, funct3=100, opcode OP=0x33).
// Instruction word = 32'h0200_4033, with the DUT parameterized as
// M_EXT=ZMMUL so the divider is deconfigured.
//   Fixed RTL:   decoder_ctrl.illegal_insn == 1'b1 -> PASS.
//   Buggy RTL:   decoder_ctrl.illegal_insn == 1'b0 -> FAIL.

`timescale 1ns/1ps
module tb_cv32e40s_m_decoder_div_zmmul;

  import cv32e40x_pkg::*;

  logic [31:0]    instr_rdata;
  decoder_ctrl_t  decoder_ctrl;

  cv32e40x_m_decoder #(
      .M_EXT (ZMMUL)
  ) dut (
      .instr_rdata_i (instr_rdata),
      .decoder_ctrl_o(decoder_ctrl)
  );

  initial begin
    // div x0, x0, x0 -> 0x02004033
    instr_rdata = 32'h0200_4033;
    #1;
    if (decoder_ctrl.illegal_insn) begin
      $display("PASS: div with M_EXT=ZMMUL flagged illegal.");
      $finish;
    end else begin
      $display("FAIL: div accepted with M_EXT=ZMMUL (illegal_insn=%b, div_en=%b).",
               decoder_ctrl.illegal_insn, decoder_ctrl.div_en);
      $fatal(1, "buggy m_decoder does not gate div on M_EXT");
    end
  end
endmodule
