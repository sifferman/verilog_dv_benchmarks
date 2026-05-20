// Test CSR_MCOUNTEREN (0x306) is accessible when DbgTriggerEn=0.
// Targets fix commit 7071b04a which removed a stray `illegal_csr = ~DbgTriggerEn`
// from CSR_MCOUNTEREN — at the parent commit reading 0x306 is reported illegal.
// Compatible with Verilator --binary.

`timescale 1ns/1ps

module tb_csr_mcounteren;
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
    .DbgTriggerEn     (0),
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

  logic        illegal;
  logic [31:0] rdata;

  initial begin
    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;
    repeat (2) @(posedge clk_i);

    // CSR_MCOUNTEREN at 0x306 must be a legal access (it is RV32 priv spec
    // mandatory). Buggy RTL erroneously marks it illegal when DbgTriggerEn=0.
    @(posedge clk_i);
    csr_access_i = 1; csr_addr_i = csr_num_e'(12'h306);
    csr_op_i = CSR_OP_READ; csr_op_en_i = 0;
    #1; rdata = csr_rdata_o; illegal = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    if (illegal) begin
      $display("FAIL MCOUNTEREN@0x306 illegal: expected legal access (DbgTriggerEn=0)");
      $fatal(1, "Test failed");
    end else begin
      $display("PASS MCOUNTEREN@0x306 accessible with DbgTriggerEn=0");
      $display("ALL TESTS PASSED");
      $finish(0);
    end
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
