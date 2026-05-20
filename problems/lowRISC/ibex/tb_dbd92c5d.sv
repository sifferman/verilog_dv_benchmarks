// Test dcsr.cause [8:6] is read-only to software (writes ignored).
// Targets fix commit dbd92c5d which assigned dcsr_d.cause = dcsr_q.cause
// in the DCSR write block. At the parent commit, a software write of
// cause=7 propagates into dcsr_q.cause and reads back as 7.

`timescale 1ns/1ps

module tb_csr_dcsr_cause_ro;
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

  // Debug mode must be asserted to make DCSR access legal.
  logic                debug_mode_i = 1;

  /* verilator lint_off PINMISSING */
  ibex_cs_registers #(
    .DbgTriggerEn     (1),
    .PMPEnable        (0),
    .PMPNumRegions    (4),
    .PMPGranularity   (0),
    .MHPMCounterNum   (0),
    .MHPMCounterWidth (40),
    .RV32E            (0),
    .RV32M            (RV32MFast),
    .RV32B            (RV32BNone)
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
    .debug_mode_i       (debug_mode_i),
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

    // Write DCSR (0x7b0) with cause = 3'b111 (bits[8:6]=0x1C0) and prv=M.
    @(posedge clk_i);
    csr_access_i = 1;
    csr_addr_i   = csr_num_e'(12'h7b0);
    csr_op_i     = CSR_OP_WRITE;
    csr_op_en_i  = 1;
    csr_wdata_i  = (3'b111 << 6) | (2'b11); // cause=7, prv=M
    @(posedge clk_i);
    csr_access_i = 0;
    csr_op_en_i  = 0;
    csr_wdata_i  = 0;

    repeat (2) @(posedge clk_i);

    // Read DCSR back. cause must remain 0 (RO to SW) after the fix.
    @(posedge clk_i);
    csr_access_i = 1;
    csr_addr_i   = csr_num_e'(12'h7b0);
    csr_op_i     = CSR_OP_READ;
    csr_op_en_i  = 0;
    #1; rdata = csr_rdata_o; illegal = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    if (illegal) begin
      $display("FAIL DCSR illegal access");
      $fatal(1, "Test failed");
    end
    if (rdata[8:6] !== 3'b000) begin
      $display("FAIL DCSR.cause = %0d (expected 0, RO to SW). full=%h", rdata[8:6], rdata);
      $fatal(1, "Test failed");
    end
    $display("PASS DCSR.cause stays 0 on SW write (read %h)", rdata);
    $display("ALL TESTS PASSED");
    $finish(0);
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
