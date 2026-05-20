// Test dcsr.stepie (bit 11) is hard-wired to 0 on writes to DCSR (0x7b0).
// Targets fix commit d78e0d9a — at the parent commit a write of 1 to
// dcsr.stepie sticks; the fix forces it to 0 in the DCSR write block.
// We assert via debug_mode_i = 1 so the write to DCSR is legal.

`timescale 1ns/1ps

module tb_csr_dcsr_stepie;
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

    // Step 1: write DCSR (0x7b0) with bit 11 (stepie) = 1.
    // We also set prv=M (bits[1:0]=2'b11) to avoid the "force to M" path.
    @(posedge clk_i);
    csr_access_i = 1;
    csr_addr_i   = csr_num_e'(12'h7b0);
    csr_op_i     = CSR_OP_WRITE;
    csr_op_en_i  = 1;
    csr_wdata_i  = (1 << 11) | (2'b11); // stepie=1, prv=M
    @(posedge clk_i);
    csr_access_i = 0;
    csr_op_en_i  = 0;
    csr_wdata_i  = 0;

    repeat (2) @(posedge clk_i);

    // Step 2: read DCSR back. Bit 11 (stepie) must be 0 after the fix.
    @(posedge clk_i);
    csr_access_i = 1;
    csr_addr_i   = csr_num_e'(12'h7b0);
    csr_op_i     = CSR_OP_READ;
    csr_op_en_i  = 0;
    #1; rdata = csr_rdata_o; illegal = illegal_csr_insn_o;
    @(posedge clk_i);
    csr_access_i = 0;

    if (illegal) begin
      $display("FAIL DCSR illegal (debug_mode=1 should make legal)");
      $fatal(1, "Test failed");
    end
    if (rdata[11] !== 1'b0) begin
      $display("FAIL DCSR.stepie = %0b (expected 0). full=%h", rdata[11], rdata);
      $fatal(1, "Test failed");
    end
    $display("PASS DCSR.stepie hardwired to 0 (read %h)", rdata);
    $display("ALL TESTS PASSED");
    $finish(0);
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
