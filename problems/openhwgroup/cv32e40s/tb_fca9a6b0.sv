// Focused unit test for cv32e40s compressed_decoder cm.lbu legal-immediate fix
// (commit fca9a6b0, 2022-05-06). Repo-internal file name at this commit was
// rtl/cv32e40x_compressed_decoder.sv (pre-rename).
//
// Bug: The Zc cm.lbu encoding (C2 quadrant, instr[15:13]=001, instr[12]=0)
// uses a 2-bit uimm formed from {instr[10], instr[6]}. The pre-fix decoder
// checked the wrong bits when deciding which uimm values are illegal:
//   buggy:  if ({instr[11:10], instr[6]} == 3'b000) illegal_instr_o = 1'b1;
//   fixed:  if ({instr[10],     instr[6]} == 2'b00) illegal_instr_o = 1'b1;
// (instr[11] is part of the *register* field, not the immediate.) As a
// result, when instr[11]=1, instr[10]=0, instr[6]=0 the buggy check
// became 3'b100 (non-zero) and the instruction was accepted even though
// the actual immediate is zero — which is the reserved value.
//
// Probe: cm.lbu encoding with instr[15:13]=001, instr[12]=0,
// instr[11]=1, instr[10]=0, rs1'=x9 ([9:7]=001), instr[6]=0,
// instr[5]=0, rd'=x9 ([4:2]=001), opcode-quadrant 10.
// Lower 16 bits: 0010_1000_1000_0110 = 0x2886.
//   Fixed RTL:   illegal_instr_o = 1'b1 -> PASS.
//   Buggy RTL:   illegal_instr_o = 1'b0 -> FAIL.

`timescale 1ns/1ps
module tb_cv32e40s_compressed_decoder_cmlbu;

  import cv32e40x_pkg::*;

  inst_resp_t  instr_i;
  inst_resp_t  instr_o;
  logic        instr_is_ptr_i;
  logic        is_compressed_o;
  logic        illegal_instr_o;

  cv32e40x_compressed_decoder #(
      .ZC_EXT (1'b1),
      .M_EXT  (M)
  ) dut (
      .instr_i         (instr_i),
      .instr_is_ptr_i  (instr_is_ptr_i),
      .instr_o         (instr_o),
      .is_compressed_o (is_compressed_o),
      .illegal_instr_o (illegal_instr_o)
  );

  initial begin
    instr_is_ptr_i = 1'b0;
    // cm.lbu with imm=0 reserved encoding (instr[10]=0, instr[6]=0) but
    // instr[11]=1 set (register-field bit, not immediate).
    instr_i.bus_resp.rdata = 32'h0000_2886;
    instr_i.bus_resp.err   = 1'b0;
    instr_i.mpu_status     = MPU_OK;
    #1;
    if (illegal_instr_o) begin
      $display("PASS: cm.lbu with reserved imm value flagged illegal.");
      $finish;
    end else begin
      $display("FAIL: cm.lbu with reserved imm value accepted (illegal_instr_o=%b).",
               illegal_instr_o);
      $fatal(1, "buggy compressed_decoder checked instr[11] in cm.lbu uimm");
    end
  end
endmodule
