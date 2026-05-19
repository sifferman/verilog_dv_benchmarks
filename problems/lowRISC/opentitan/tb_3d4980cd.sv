// Test prim_fifo_sync full_o behaviour when Depth == 0.
// Targets fix commit 3d4980cdcf:
//   Buggy:  assign full_o = rready_i;  (wrong: full only when consumer is ready)
//   Fixed:  assign full_o = 1'b1;      (correct: passthrough FIFO is always full)
// Compatible with Verilator --timing.

module tb_prim_fifo_sync_depth0;

  logic clk_i  = 0;
  logic rst_ni = 0;
  always #5 clk_i = ~clk_i;

  logic       wvalid_i = 0;
  logic       wready_o;
  logic [7:0] wdata_i  = 0;
  logic       rvalid_o;
  logic       rready_i = 0;
  logic [7:0] rdata_o;
  logic       full_o;
  logic [0:0] depth_o;
  logic       err_o;
  logic       clr_i    = 0;

  /* verilator lint_off PINMISSING */
  prim_fifo_sync #(
    .Width(8),
    .Depth(0),
    .Pass (1'b1)
  ) dut (
    .clk_i,
    .rst_ni,
    .clr_i,
    .wvalid_i,
    .wready_o,
    .wdata_i,
    .rvalid_o,
    .rready_i,
    .rdata_o,
    .full_o,
    .depth_o,
    .err_o
  );
  /* verilator lint_on PINMISSING */

  initial begin
    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;
    repeat (2) @(posedge clk_i);

    // With rready_i=0: fixed → full_o=1, buggy → full_o=0 (follows rready_i).
    // This is the discriminating case.
    rready_i = 0;
    @(posedge clk_i);
    #1;
    if (full_o !== 1'b1) begin
      $display("FAIL: full_o=%0b when rready_i=0, expected 1 (Depth==0 FIFO is always full)",
               full_o);
      $fatal(1, "Test failed");
    end

    // With rready_i=1: both buggy and fixed give full_o=1; confirm it still holds.
    rready_i = 1;
    @(posedge clk_i);
    #1;
    if (full_o !== 1'b1) begin
      $display("FAIL: full_o=%0b when rready_i=1, expected 1", full_o);
      $fatal(1, "Test failed");
    end

    $display("PASS: prim_fifo_sync Depth==0 full_o is always 1");
    $display("ALL TESTS PASSED");
    $finish(0);
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
