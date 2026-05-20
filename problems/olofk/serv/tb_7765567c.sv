// Focused unit test for serv_rf_if "missing gate on mem_rd with CSR
// disabled" fix (7765567, 2021-12-29).
//
// Bug: When instantiated with WITH_CSR=0, the WITH_CSR=0 generate branch
// computed the regfile write-data bit as:
//   rd = i_ctrl_rd | (i_alu_rd & i_rd_alu_en) | i_mem_rd;
// I.e. i_mem_rd was OR'd in unconditionally — even when the current
// instruction is NOT a load (i_rd_mem_en = 0).  The mem-unit can keep its
// last-load bit asserted across cycles, so any later non-load instruction
// would see that residue OR'd into its writeback, corrupting rd.
//
// Fix: gate with i_rd_mem_en:
//   rd = i_ctrl_rd | (i_alu_rd & i_rd_alu_en) | (i_mem_rd & i_rd_mem_en);
//
// Probe: drive i_rd_mem_en=0, i_mem_rd=1, all other write-data bits 0,
// and read o_wdata0.
//   Fixed RTL:  o_wdata0 = 0  -> PASS.
//   Buggy RTL:  o_wdata0 = 1  -> FAIL.

`timescale 1ns/1ps
module tb_serv_rf_if_mem_rd_gate;

  // Drives
  reg        cnt_en      = 1'b0;
  reg        trap        = 1'b0;
  reg        mret        = 1'b0;
  reg        mepc        = 1'b0;
  reg        mtval_pc    = 1'b0;
  reg        bufreg_q    = 1'b0;
  reg        bad_pc      = 1'b0;
  reg        csr_en      = 1'b0;
  reg [1:0]  csr_addr    = 2'b00;
  reg        csr        = 1'b0;
  reg        rd_wen      = 1'b1;       // any nonzero rd
  reg [4:0]  rd_waddr    = 5'd5;       // nonzero so rd_wen passes through
  reg        ctrl_rd     = 1'b0;
  reg        alu_rd      = 1'b0;
  reg        rd_alu_en   = 1'b0;
  reg        csr_rd      = 1'b0;
  reg        rd_csr_en   = 1'b0;
  reg        mem_rd      = 1'b1;       // residue from a prior load
  reg        rd_mem_en   = 1'b0;       // current instruction is NOT a load
  reg [4:0]  rs1_raddr   = 5'd0;
  reg [4:0]  rs2_raddr   = 5'd0;
  reg        rdata0      = 1'b0;
  reg        rdata1      = 1'b0;

  // Outputs (5 bits because WITH_CSR=0 makes the wreg/rreg ports 5-bit)
  wire [4:0] wreg0, wreg1, rreg0, rreg1;
  wire       wen0, wen1, wdata0, wdata1;
  wire       o_csr_pc, o_csr;
  wire       o_rs1, o_rs2;

  serv_rf_if #(.WITH_CSR(0)) dut (
    .i_cnt_en    (cnt_en),
    .o_wreg0     (wreg0),
    .o_wreg1     (wreg1),
    .o_wen0      (wen0),
    .o_wen1      (wen1),
    .o_wdata0    (wdata0),
    .o_wdata1    (wdata1),
    .o_rreg0     (rreg0),
    .o_rreg1     (rreg1),
    .i_rdata0    (rdata0),
    .i_rdata1    (rdata1),
    .i_trap      (trap),
    .i_mret      (mret),
    .i_mepc      (mepc),
    .i_mtval_pc  (mtval_pc),
    .i_bufreg_q  (bufreg_q),
    .i_bad_pc    (bad_pc),
    .o_csr_pc    (o_csr_pc),
    .i_csr_en    (csr_en),
    .i_csr_addr  (csr_addr),
    .i_csr       (csr),
    .o_csr       (o_csr),
    .i_rd_wen    (rd_wen),
    .i_rd_waddr  (rd_waddr),
    .i_ctrl_rd   (ctrl_rd),
    .i_alu_rd    (alu_rd),
    .i_rd_alu_en (rd_alu_en),
    .i_csr_rd    (csr_rd),
    .i_rd_csr_en (rd_csr_en),
    .i_mem_rd    (mem_rd),
    .i_rd_mem_en (rd_mem_en),
    .i_rs1_raddr (rs1_raddr),
    .o_rs1       (o_rs1),
    .i_rs2_raddr (rs2_raddr),
    .o_rs2       (o_rs2)
  );

  initial begin
    // All inputs settled at time 0 (purely combinational module).
    #1;
    if (wdata0 === 1'b0) begin
      $display("PASS: o_wdata0 = 0 (mem_rd correctly gated when rd_mem_en=0).");
      $finish;
    end else begin
      $display("FAIL: o_wdata0 = %0b (expected 0; mem_rd residue leaked into rd).",
               wdata0);
      $fatal(1, "buggy serv_rf_if forwards mem_rd without rd_mem_en gating");
    end
  end

  initial begin
    #1000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
