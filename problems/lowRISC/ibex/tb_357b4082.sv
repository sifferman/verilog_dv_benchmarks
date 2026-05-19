// Test MSECCFGH CSR is accessible at address 0x391 (ePMP draft address).
// Targets fix commit 357b4082 which added the MSECCFGH CSR.
// At the prev commit the CSR didn't exist, so access is illegal.
// Compatible with Verilator --timing.

`timescale 1ns/1ps

module tb_csr_mseccfgh;
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
    .PMPEnable        (1),
    .PMPNumRegions    (4),
    .PMPGranularity   (0),
    .MHPMCounterNum   (8),
    .MHPMCounterWidth (40),
    .RV32E            (0),
    .RV32M            (RV32MFast),
    .RV32B            (RV32BFull)
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

    // MSECCFGH was added at address 0x391 by this fix commit.
    // At the prev commit it did not exist, so access should be illegal there.
    @(posedge clk_i);
    csr_access_i = 1; csr_addr_i = csr_num_e'(12'h391);
    csr_op_i = CSR_OP_READ; csr_op_en_i = 0;
    #1; rdata = csr_rdata_o; illegal = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    if (illegal) begin
      $display("FAIL MSECCFGH@0x391 illegal: expected legal access");
      $fatal(1, "Test failed");
    end else begin
      $display("PASS MSECCFGH@0x391 accessible");
      $display("ALL TESTS PASSED");
      $finish(0);
    end
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
