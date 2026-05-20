// Focused unit test for cv32e40s compressed_decoder c.sh reserved-bit fix
// (commit 31bf9a03, 2022-05-06). Repo-internal file name at this commit was
// rtl/cv32e40x_compressed_decoder.sv (pre-rename).
//
// Bug: The Zc c.sh encoding has instr[6] reserved (must be zero). The
// pre-fix decoder did not check this and silently produced a sh
// instruction whenever instr[15:13]=100 / instr[12:10]=011 in quadrant 00,
// regardless of the value of instr[6]. The fix adds
// `if (instr[6]) illegal_instr_o = 1'b1;` in the c.sh case.
//
// Probe: c.sh with rs1'=x9 ([9:7]=001), rs2'=x8 ([4:2]=000), instr[6]=1
// (reserved bit non-zero), instr[5]=0, opcode quadrant 00.
// Lower 16 bits: 1000 1100 1100 0000 = 0x8CC0.
//   Fixed RTL:   illegal_instr_o = 1'b1 -> PASS.
//   Buggy RTL:   illegal_instr_o = 1'b0 -> FAIL.

`timescale 1ns/1ps
module tb_cv32e40s_compressed_decoder_csh;

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
    instr_i.bus_resp.rdata = 32'h0000_8CC0; // c.sh, rs1'=x9, rs2'=x8, instr[6]=1 (reserved)
    instr_i.bus_resp.err   = 1'b0;
    instr_i.mpu_status     = MPU_OK;
    #1;
    if (!is_compressed_o) begin
      $display("FAIL: c.sh form (instr[1:0]=00) not flagged as compressed (is_compressed_o=%b).", is_compressed_o);
      $fatal(1, "compressed_decoder did not classify quadrant-00 op as compressed");
    end
    if (illegal_instr_o) begin
      $display("PASS: c.sh with reserved instr[6]=1 flagged illegal.");
      $finish;
    end else begin
      $display("FAIL: c.sh with reserved instr[6]=1 accepted (illegal_instr_o=%b).", illegal_instr_o);
      $fatal(1, "buggy compressed_decoder did not check c.sh reserved bit 6");
    end
  end
endmodule
