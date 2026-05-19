// Minimal testbench for misa.B extension bit (ca31ca43).
// Tests that misa bit[1] (B extension) is set when RV32B=Full.
// Compatible with Verilator --timing. Exits 0 on pass.

`timescale 1ns/1ps

module tb_csr_misa;
  import ibex_pkg::*;

  logic        clk_i  = 0;
  logic        rst_ni = 0;
  always #5 clk_i = ~clk_i;

  logic                csr_access_i     = 0;
  csr_num_e            csr_addr_i       = csr_num_e'(0);
  logic [31:0]         csr_wdata_i      = 0;
  csr_op_e             csr_op_i         = CSR_OP_READ;
  logic                csr_op_en_i      = 0;
  logic [31:0]         csr_rdata_o;
  logic                illegal_csr_insn_o;

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
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .csr_access_i  (csr_access_i),
    .csr_addr_i    (csr_addr_i),
    .csr_wdata_i   (csr_wdata_i),
    .csr_op_i      (csr_op_i),
    .csr_op_en_i   (csr_op_en_i),
    .csr_rdata_o   (csr_rdata_o),
    .illegal_csr_insn_o (illegal_csr_insn_o)
  );
  /* verilator lint_on PINMISSING */

  logic [31:0] rdata;
  logic        illegal;

  initial begin
    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;
    repeat (2) @(posedge clk_i);

    @(posedge clk_i);
    csr_access_i = 1;
    csr_addr_i   = CSR_MISA;
    csr_op_i     = CSR_OP_READ;
    csr_op_en_i  = 0;
    #1;
    rdata   = csr_rdata_o;
    illegal = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    if (rdata[1] !== 1'b1) begin
      $display("FAIL misa.B: expected 1, got %b (misa=0x%08x)", rdata[1], rdata);
      $fatal(1, "Test failed");
    end else begin
      $display("PASS misa.B extension bit set");
      $display("ALL TESTS PASSED");
      $finish(0);
    end
  end

  initial begin
    #100000;
    $fatal(1, "TIMEOUT");
  end

endmodule
