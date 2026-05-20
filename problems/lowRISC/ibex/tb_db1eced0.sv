// Test PMP CSRs are illegal when PMPEnable=0.
// Targets fix commit db1eced0 — at the parent commit the PMP CSRs are silently
// readable (returning '0') even when PMPEnable=0; the fix flags them illegal
// to match Spike.

`timescale 1ns/1ps

module tb_csr_pmp_disabled_illegal;
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
    .illegal_csr_insn_o (illegal_csr_insn_o)
  );
  /* verilator lint_on PINMISSING */

  logic illegal_pmpcfg0, illegal_pmpaddr0;

  initial begin
    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;
    repeat (2) @(posedge clk_i);

    // Read CSR_PMPCFG0 (0x3A0) — must be illegal when PMPEnable=0.
    @(posedge clk_i);
    csr_access_i = 1; csr_addr_i = csr_num_e'(12'h3A0);
    csr_op_i = CSR_OP_READ; csr_op_en_i = 0;
    #1; illegal_pmpcfg0 = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    repeat (2) @(posedge clk_i);

    // Read CSR_PMPADDR0 (0x3B0) — also illegal.
    @(posedge clk_i);
    csr_access_i = 1; csr_addr_i = csr_num_e'(12'h3B0);
    csr_op_i = CSR_OP_READ; csr_op_en_i = 0;
    #1; illegal_pmpaddr0 = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    if (!illegal_pmpcfg0) begin
      $display("FAIL PMPCFG0 should be illegal when PMPEnable=0 (got legal)");
      $fatal(1, "Test failed");
    end
    if (!illegal_pmpaddr0) begin
      $display("FAIL PMPADDR0 should be illegal when PMPEnable=0 (got legal)");
      $fatal(1, "Test failed");
    end
    $display("PASS PMP CSRs are illegal when PMPEnable=0");
    $display("ALL TESTS PASSED");
    $finish(0);
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
