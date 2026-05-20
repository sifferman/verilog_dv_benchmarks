// Focused unit test for serv_immdec signedness-on-immediates bug (b10a871,
// 2021-08-26).
//
// Bug: signbit was latched using `i_wb_rdt[31] & !i_csr_imm_en` *at the same
// clock edge* that loaded the new instruction.  Because o_csr_imm_en is
// registered by serv_decode (gen_post_register), at that clock edge
// i_csr_imm_en still reflects the *previous* instruction.  If the previous
// instruction was a CSRI (csr_imm_en=1) and the new instruction is non-CSR
// (its actual csr_imm_en should be 0) with bit-31 = 1, the buggy RTL latches
// signbit = 0 even though the new immediate is negative.
//
// The fix latches imm31 = i_wb_rdt[31] unconditionally and computes signbit
// combinationally as `imm31 & !i_csr_imm_en`, so it tracks the *current*
// (latched) csr_imm_en.
//
// Probe: clock 1: i_wb_en=1, i_csr_imm_en=1 (residue from previous CSRI),
// i_wb_rdt[31]=1.  Then drop i_csr_imm_en to 0 (representing the now-latched
// non-CSR instruction).  Assert i_cnt_done and observe o_imm: should be 1
// (sign-extended) in the fix, 0 in the buggy RTL.

`timescale 1ns/1ps
module tb_serv_immdec_signbit;

  reg         clk = 1'b0;
  always #5 clk = ~clk;

  reg         cnt_en     = 1'b0;
  reg         cnt_done   = 1'b0;
  reg [3:0]   immdec_en  = 4'b0000;
  reg         csr_imm_en = 1'b0;
  reg [3:0]   ctrl       = 4'b0000;
  reg         wb_en      = 1'b0;
  reg [31:7]  wb_rdt     = 25'h0;

  wire [4:0]  rd_addr, rs1_addr, rs2_addr;
  wire        csr_imm;
  wire        imm;

  serv_immdec #(.SHARED_RFADDR_IMM_REGS(1)) dut (
    .i_clk         (clk),
    .i_cnt_en      (cnt_en),
    .i_cnt_done    (cnt_done),
    .i_immdec_en   (immdec_en),
    .i_csr_imm_en  (csr_imm_en),
    .i_ctrl        (ctrl),
    .o_rd_addr     (rd_addr),
    .o_rs1_addr    (rs1_addr),
    .o_rs2_addr    (rs2_addr),
    .o_csr_imm     (csr_imm),
    .o_imm         (imm),
    .i_wb_en       (wb_en),
    .i_wb_rdt      (wb_rdt)
  );

  initial begin
    // Initial setup: assume the previous decoded instruction was a CSRI, so
    // the registered csr_imm_en (coming from serv_decode) is currently 1.
    csr_imm_en = 1'b1;
    wb_en      = 1'b0;
    wb_rdt     = 25'h0;
    cnt_done   = 1'b0;

    // Wait for clock to settle
    @(negedge clk);

    // Now latch a NEW instruction whose top bit is 1 (so a negative
    // immediate when sign-extended).  At this clock edge, csr_imm_en still
    // reflects the *previous* CSRI instruction (=1), because serv_decode
    // registers csr_imm_en at this same edge.
    //
    // Buggy serv_immdec: signbit <= i_wb_rdt[31] & !i_csr_imm_en
    //                          = 1 & !1 = 0 (WRONG)
    // Fixed serv_immdec: imm31 <= 1; signbit = imm31 & !i_csr_imm_en
    //   which becomes 1 once csr_imm_en drops to 0 (its real value for the
    //   new non-CSR instruction).
    wb_en  = 1'b1;
    wb_rdt = {1'b1, 24'h000000};  // bit-31 = 1, rest don't care

    @(posedge clk);   // The instruction is latched here
    #1;
    wb_en  = 1'b0;

    // Drop csr_imm_en — simulating that the new (just-latched) instruction is
    // not a CSRI.  In the fixed RTL, signbit (combinational) now equals
    // imm31 & !0 = 1.  In the buggy RTL, the latched signbit is still 0.
    csr_imm_en = 1'b0;

    @(negedge clk);

    // Now ask immdec to emit signbit through o_imm by asserting cnt_done.
    cnt_done = 1'b1;
    #1;

    if (imm === 1'b1) begin
      $display("PASS: o_imm at cnt_done = 1 (sign-extension preserved).");
      $finish;
    end else begin
      $display("FAIL: o_imm at cnt_done = %0b (expected 1; signbit lost).",
               imm);
      $fatal(1, "buggy serv_immdec dropped signbit when latching after CSRI");
    end
  end

  // Watchdog
  initial begin
    #1000;
    $display("FAIL: testbench watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
