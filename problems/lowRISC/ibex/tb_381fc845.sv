// Test MISA.X (bit 23) is set when RV32B == RV32BBalanced.
// Targets fix commit 381fc845 which corrected RV32BExtra so that the MISA X
// (non-standard extensions) bit is asserted for every non-None RV32B config.
// At the parent commit, only RV32BOTEarlGrey/RV32BFull set MISA.X, so
// RV32BBalanced reads back with bit 23 == 0.

`timescale 1ns/1ps

module tb_csr_misa_x;
  import ibex_pkg::*;

  logic clk_i  = 0;
  logic rst_ni = 0;
  always #5 clk_i = ~clk_i;

  logic                csr_access_i = 0;
  csr_num_e            csr_addr_i   = csr_num_e'(0);
  logic [31:0]         csr_wdata_i  = 0;
  csr_op_e             csr_op_i     = CSR_OP_READ;
  logic                csr_op_en_i  = 0;
  logic [31:0]         csr_rdata_o;
  logic                illegal_csr_insn_o;
  logic [6:0]          csr_mcause_i = '0;

  /* verilator lint_off PINMISSING */
  ibex_cs_registers #(
    .PMPEnable        (0),
    .PMPNumRegions    (4),
    .PMPGranularity   (0),
    .MHPMCounterNum   (0),
    .MHPMCounterWidth (40),
    .RV32E            (0),
    .RV32M            (RV32MFast),
    .RV32B            (RV32BBalanced)
  ) dut (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .csr_access_i       (csr_access_i),
    .csr_addr_i         (csr_addr_i),
    .csr_wdata_i        (csr_wdata_i),
    .csr_op_i           (csr_op_i),
    .csr_op_en_i        (csr_op_en_i),
    .csr_rdata_o        (csr_rdata_o),
    .csr_mcause_i       (csr_mcause_i),
    .illegal_csr_insn_o (illegal_csr_insn_o)
  );
  /* verilator lint_on PINMISSING */

  logic        illegal;
  logic [31:0] rdata;

  initial begin
    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;
    repeat (2) @(posedge clk_i);

    // Read CSR_MISA (0x301).
    @(posedge clk_i);
    csr_access_i = 1; csr_addr_i = csr_num_e'(12'h301);
    csr_op_i = CSR_OP_READ; csr_op_en_i = 0;
    #1; rdata = csr_rdata_o; illegal = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    if (illegal) begin
      $display("FAIL CSR_MISA illegal");
      $fatal(1, "Test failed");
    end
    if (rdata[23] !== 1'b1) begin
      $display("FAIL MISA.X bit 23 = %0b (expected 1 for RV32BBalanced). full=%h", rdata[23], rdata);
      $fatal(1, "Test failed");
    end
    $display("PASS MISA.X=1 for RV32BBalanced (read %h)", rdata);
    $display("ALL TESTS PASSED");
    $finish(0);
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
