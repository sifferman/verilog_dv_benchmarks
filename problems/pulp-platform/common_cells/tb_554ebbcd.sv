// Focused unit test for pulp-platform/common_cells delta_counter
// "Fix inverted reset" (commit 554ebbc, 2024-10-09).
//
// Bug: In the STICKY_OVERFLOW=1 branch of delta_counter, the reset clause
// is inverted:
//     if(rst_ni)  overflow_q <= 1'b0;
//     else        overflow_q <= overflow_d;
// Active-low reset is asserted when rst_ni=0, so this loads overflow_d
// while in reset and clears overflow_q every cycle out of reset. With the
// fix it correctly clears in reset and latches overflow_d out of reset.
//
// Observable symptom: with the bug, overflow_o never sticks to 1 once
// reset is released, because every clock edge re-clears overflow_q to 0.
//
//   Fixed RTL:  overflow_o becomes 1 after the up-counter wraps -> PASS.
//   Buggy RTL:  overflow_o stays 0 because reset clause is inverted -> FAIL.

`timescale 1ns/1ps
module tb_554ebbcd;

  localparam int unsigned WIDTH = 4;

  logic             clk_i  = 1'b0;
  logic             rst_ni = 1'b0;
  logic             clear_i = 1'b0;
  logic             en_i    = 1'b0;
  logic             load_i  = 1'b0;
  logic             down_i  = 1'b0;
  logic [WIDTH-1:0] delta_i = '0;
  logic [WIDTH-1:0] d_i     = '0;
  logic [WIDTH-1:0] q_o;
  logic             overflow_o;

  // 10 ns clock
  always #5 clk_i = ~clk_i;

  delta_counter #(
      .WIDTH           (WIDTH),
      .STICKY_OVERFLOW (1'b1)
  ) dut (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .clear_i    (clear_i),
      .en_i       (en_i),
      .load_i     (load_i),
      .down_i     (down_i),
      .delta_i    (delta_i),
      .d_i        (d_i),
      .q_o        (q_o),
      .overflow_o (overflow_o)
  );

  initial begin
    // Hold reset asserted (active-low) for a couple cycles.
    rst_ni = 1'b0;
    en_i   = 1'b0;
    delta_i = 4'd1;
    d_i     = 4'd0;
    @(posedge clk_i);
    @(posedge clk_i);
    // Release reset.
    @(negedge clk_i);
    rst_ni = 1'b1;

    // Now run up-counts until we definitely wrap WIDTH=4 (max 15) and overflow.
    // delta=5 ensures we cross the wrap quickly (0,5,10,15->overflow).
    delta_i = 4'd5;
    en_i    = 1'b1;
    repeat (8) @(posedge clk_i);

    // Stop counting; check that the sticky overflow remained asserted.
    en_i = 1'b0;
    repeat (4) @(posedge clk_i);

    if (overflow_o === 1'b1) begin
      $display("PASS: sticky overflow_o latched after wrap (q_o=%0d).", q_o);
      $finish;
    end else begin
      $display("FAIL: overflow_o=%0b (expected 1; sticky overflow lost).",
               overflow_o);
      $fatal(1, "delta_counter sticky overflow not retained -- inverted reset bug");
    end
  end

  // Watchdog
  initial begin
    #2000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
