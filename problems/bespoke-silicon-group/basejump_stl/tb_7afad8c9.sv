// Focused unit test for bsg_counter_clear_up_multi rollover fix
// (commit 7afad8c, 2025-12-22).
//
// Bug: ptr_width_lp was computed as BSG_SAFE_CLOG2(max_val_p+1). When
// max_val_p == 32'hFFFFFFFF, max_val_p+1 wraps to 0 and BSG_SAFE_CLOG2(0)
// returns 1. This collapses the counter to a single bit even though the
// caller asked for a 32-bit-wide counter. The fix uses BSG_WIDTH(max_val_p)
// which evaluates clog2 in 33-bit arithmetic and correctly returns 32.
//
// Probe: instantiate the counter with max_val_p=32'hFFFFFFFF, clear with
// up_i=2 (popcount=1), then increment 4 more times (each up_i=1, popcount=1).
// Final value should be 5 in the fixed RTL. In the buggy RTL, the counter
// is 1 bit wide, so by reading `count_r_o` we see a single bit that flips
// each cycle; checking that the upper bits hold the expected value
// distinguishes fix from buggy.
//
//   Fixed RTL:  count_r_o == 32'd5  -> PASS.
//   Buggy RTL:  port width is 1 bit, the wider TB wire reads garbage/X.

`timescale 1ns/1ps
module tb_7afad8c9;

  localparam int unsigned ELS_P = 4;
  localparam logic [31:0] MAX_VAL_P = 32'hFFFF_FFFF;

  logic              clk;
  logic              reset;
  logic              clear_i;
  logic [ELS_P-1:0]  up_i;
  // We deliberately declare the count wire wider than the DUT might drive.
  // A narrower port driver is zero-extended; with the buggy 1-bit counter
  // the upper bits stay 0 and the value can never reach 5.
  logic [31:0]       count_r_o;

  bsg_counter_clear_up_multi #(
    .max_val_p(MAX_VAL_P),
    .init_val_p(32'd0),
    .els_p(ELS_P)
  ) dut (
    .clk_i(clk),
    .reset_i(reset),
    .clear_i(clear_i),
    .up_i(up_i),
    .count_r_o(count_r_o)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    reset   = 1'b1;
    clear_i = 1'b0;
    up_i    = '0;

    @(posedge clk); @(posedge clk); @(posedge clk);
    @(negedge clk);
    reset = 1'b0;

    @(posedge clk);

    // Clear with up_i bit 0 set -> popcount=1 -> counter loaded with 1.
    @(negedge clk);
    clear_i = 1'b1;
    up_i    = 4'b0001;
    @(posedge clk);

    @(negedge clk);
    clear_i = 1'b0;
    up_i    = 4'b0001;
    @(posedge clk);   // count <- 1 + 1 = 2

    @(negedge clk);
    @(posedge clk);   // count <- 2 + 1 = 3

    @(negedge clk);
    @(posedge clk);   // count <- 3 + 1 = 4

    @(negedge clk);
    @(posedge clk);   // count <- 4 + 1 = 5

    @(negedge clk);
    up_i = '0;

    if (count_r_o !== 32'd5) begin
      $display("FAIL: expected count_r_o=32'd5, got 0x%08h (%0d).",
               count_r_o, count_r_o);
      $fatal(1, "counter rolled over because ptr_width_lp collapsed to 1 bit");
    end

    $display("PASS: counter incremented to 5 with max_val_p=0xFFFFFFFF.");
    $finish;
  end

  initial begin
    #5000;
    $display("FAIL: watchdog timeout.");
    $fatal(1, "watchdog");
  end

endmodule
