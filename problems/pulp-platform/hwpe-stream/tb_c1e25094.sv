// Focused unit test for pulp-platform/hwpe-stream hwpe_stream_fifo
// "Correctly assign almost full signal" (commit c1e2509, 2025-07-03).
//
// Bug: almost_full was assigned using the same expression as almost_empty,
// so they always carry the same value. The fix swaps push/pop in the
// almost_full expression so it correctly indicates one-from-full.
//
//   Buggy line (before fix):
//     assign flags_o.almost_full = (cs == MIDDLE) &&
//         ((pop_pointer_q == push_pointer_q-1) ||
//          ((pop_pointer_q == FIFO_DEPTH-1) && (push_pointer_q == 0)));
//
//   Fixed line:
//     assign flags_o.almost_full = (cs == MIDDLE) &&
//         ((push_pointer_q == pop_pointer_q-1) ||
//          ((push_pointer_q == FIFO_DEPTH-1) && (pop_pointer_q == 0)));
//
// Test approach (FIFO_DEPTH=4):
//   1) Push 3 transactions without popping. After these pushes the FIFO
//      holds 3 of 4 entries and is exactly one-from-full:
//         push_pointer = 3, pop_pointer = 0  (state = MIDDLE)
//   2) Sample almost_full. Fixed RTL: 1. Buggy RTL: 0.

`timescale 1ns/1ps

module tb_c1e25094;

  import hwpe_stream_package::*;

  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned FIFO_DEPTH = 4;

  logic clk_i  = 1'b0;
  logic rst_ni = 1'b0;
  logic clear_i = 1'b0;

  flags_fifo_t flags;

  // 10ns clock
  always #5 clk_i = ~clk_i;

  hwpe_stream_intf_stream #(.DATA_WIDTH(DATA_WIDTH))
    push_i (.clk(clk_i));
  hwpe_stream_intf_stream #(.DATA_WIDTH(DATA_WIDTH))
    pop_o  (.clk(clk_i));

  hwpe_stream_fifo #(
    .DATA_WIDTH (DATA_WIDTH),
    .FIFO_DEPTH (FIFO_DEPTH)
  ) dut (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .clear_i(clear_i),
    .flags_o(flags),
    .push_i (push_i),
    .pop_o  (pop_o)
  );

  // Drive push from this testbench
  logic                  push_valid;
  logic [DATA_WIDTH-1:0] push_data;
  logic [DATA_WIDTH/8-1:0] push_strb;
  assign push_i.valid = push_valid;
  assign push_i.data  = push_data;
  assign push_i.strb  = push_strb;
  // Hold pop ready=0 so nothing is consumed
  assign pop_o.ready  = 1'b0;

  initial begin
    push_valid = 1'b0;
    push_data  = '0;
    push_strb  = '1;
    rst_ni = 1'b0;
    @(posedge clk_i);
    @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    // Push 3 entries (no pops). After these completed pushes:
    //   push_pointer should be 3, pop_pointer should be 0, state=MIDDLE
    // The FIFO holds 3 of 4 entries -> one-from-full -> almost_full=1
    for (int i = 0; i < 3; i++) begin
      push_valid = 1'b1;
      push_data  = i;
      @(posedge clk_i);
    end
    push_valid = 1'b0;
    // settle one cycle for outputs to reflect the new state
    @(posedge clk_i);
    #1;

    $display("INFO: empty=%0b full=%0b almost_empty=%0b almost_full=%0b push_ptr=%0d pop_ptr=%0d",
             flags.empty, flags.full, flags.almost_empty, flags.almost_full,
             flags.push_pointer, flags.pop_pointer);

    // Sanity: not full yet (only 3 of 4)
    if (flags.full !== 1'b0) begin
      $display("FAIL: unexpected full=1 before fourth push");
      $fatal(1, "fifo went FULL with only 3 pushes");
    end

    if (flags.almost_full !== 1'b1) begin
      $display("FAIL: almost_full=%0b, expected 1 (FIFO is one-from-full)",
               flags.almost_full);
      $fatal(1, "almost_full assigned incorrectly -- bug present");
    end

    $display("PASS: almost_full asserted correctly when FIFO is one-from-full.");
    $finish;
  end

  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
