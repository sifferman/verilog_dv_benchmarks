// Focused unit test for pulp-platform/hwpe-stream hwpe_stream_fifo
// "Fix incorrect behavior of hwpe_stream_fifo" (commit 3bc9694, 2024-09-27).
//
// Bug: In the EMPTY->MIDDLE transition, push_pointer_d was incremented as
// `push_pointer_q + 1'b1` with no wrap, while the MIDDLE state path has
// an explicit wrap when push_pointer_q == FIFO_DEPTH-1. When FIFO_DEPTH
// is NOT a power of 2 (e.g. 3), the EMPTY-state increment can take
// push_pointer past FIFO_DEPTH-1 without wrapping, leading to writes at
// an out-of-range index and stale/incorrect data on subsequent pops.
//
// The fix adds the explicit wrap:
//     if (push_pointer_q == FIFO_DEPTH-1) push_pointer_d = '0;
//     else                                push_pointer_d = push_pointer_q+1;
//
// Test approach (FIFO_DEPTH=3, non-power-of-2):
//   Repeatedly push one entry, pop one entry, so the FIFO oscillates
//   through EMPTY -> MIDDLE -> EMPTY with the pointers advancing each
//   round. After three rounds both pointers reach FIFO_DEPTH-1=2 and
//   the FIFO is EMPTY. The next push uses the EMPTY-state path and
//   must wrap push_pointer to 0; the data is written to slot 0. The
//   following pop must return that data unchanged.
//
//   Buggy RTL: push_pointer becomes 3 (out of range), data is written
//   to an out-of-range slot, the next pop returns stale/garbage data
//   from slot 2.
//   Fixed  RTL: push_pointer wraps to 0; pop returns the new data.

`timescale 1ns/1ps

module tb_3bc96947;

  import hwpe_stream_package::*;

  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned FIFO_DEPTH = 3;

  logic clk_i  = 1'b0;
  logic rst_ni = 1'b0;
  logic clear_i = 1'b0;

  flags_fifo_t flags;

  always #5 clk_i = ~clk_i;

  hwpe_stream_intf_stream #(.DATA_WIDTH(DATA_WIDTH))
    push_if (.clk(clk_i));
  hwpe_stream_intf_stream #(.DATA_WIDTH(DATA_WIDTH))
    pop_if  (.clk(clk_i));

  hwpe_stream_fifo #(
    .DATA_WIDTH (DATA_WIDTH),
    .FIFO_DEPTH (FIFO_DEPTH)
  ) dut (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .clear_i(clear_i),
    .flags_o(flags),
    .push_i (push_if),
    .pop_o  (pop_if)
  );

  logic                  push_valid;
  logic [DATA_WIDTH-1:0] push_data;
  logic [DATA_WIDTH/8-1:0] push_strb;
  logic                  pop_ready;
  assign push_if.valid = push_valid;
  assign push_if.data  = push_data;
  assign push_if.strb  = push_strb;
  assign pop_if.ready  = pop_ready;

  // Drive a single-cycle push of `data`, with no pop.
  task push_one(input logic [DATA_WIDTH-1:0] data);
    @(negedge clk_i);
    push_valid = 1'b1;
    push_data  = data;
    push_strb  = '1;
    pop_ready  = 1'b0;
    @(posedge clk_i);
    @(negedge clk_i);
    push_valid = 1'b0;
    push_data  = '0;
  endtask

  // Drive a single-cycle pop with no push. Capture popped data.
  task pop_one(output logic [DATA_WIDTH-1:0] data);
    @(negedge clk_i);
    push_valid = 1'b0;
    pop_ready  = 1'b1;
    if (pop_if.valid !== 1'b1)
      $fatal(1, "pop_one: pop_if.valid not asserted (FIFO unexpectedly empty)");
    data = pop_if.data;
    @(posedge clk_i);
    @(negedge clk_i);
    pop_ready  = 1'b0;
  endtask

  logic [DATA_WIDTH-1:0] got;

  initial begin
    push_valid = 1'b0;
    push_data  = '0;
    push_strb  = '1;
    pop_ready  = 1'b0;
    rst_ni = 1'b0;
    @(posedge clk_i);
    @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);

    // Round 1: push, pop -> push_ptr=1, pop_ptr=1 (EMPTY)
    push_one(32'hAAAA_0001);
    pop_one(got);
    if (got !== 32'hAAAA_0001)
      $fatal(1, "Round 1 pop=%h, expected AAAA_0001", got);

    // Round 2: push, pop -> push_ptr=2, pop_ptr=2 (EMPTY)
    push_one(32'hAAAA_0002);
    pop_one(got);
    if (got !== 32'hAAAA_0002)
      $fatal(1, "Round 2 pop=%h, expected AAAA_0002", got);

    // Round 3: Now both pointers are at FIFO_DEPTH-1=2.
    // This push exercises the EMPTY->MIDDLE wrap that the fix addresses.
    // The data is still written through push_pointer_q (=2 here) so the
    // same data is popped back regardless of the bug. The bug manifests on
    // the NEXT round once push_pointer has been advanced incorrectly.
    push_one(32'hDEAD_BEEF);
    pop_one(got);
    $display("INFO: round3 popped=%h", got);
    if (got !== 32'hDEAD_BEEF)
      $fatal(1, "Round 3 pop=%h, expected DEAD_BEEF", got);

    // Round 4: This is the round where the EMPTY-state wrap bug shows
    // up. In the fixed RTL push_pointer wrapped to 0 after Round 3, so
    // the write of CAFE_F00D goes into fifo_registers[0], and the next
    // pop returns CAFE_F00D. In the buggy RTL push_pointer became 3 (in
    // its 2-bit register: binary 11). Round 4's write therefore targets
    // fifo_registers[3] (out of range; Verilator silently masks the
    // write) and the pop reads fifo_registers[0], which was zeroed at
    // reset.
    push_one(32'hCAFE_F00D);
    pop_one(got);
    $display("INFO: round4 popped=%h", got);
    if (got !== 32'hCAFE_F00D) begin
      $display("FAIL: round 4 pop=%h (expected CAFE_F00D)", got);
      $fatal(1, "hwpe_stream_fifo EMPTY-state push_pointer wrap bug");
    end

    $display("PASS: FIFO push_pointer wraps correctly from EMPTY state.");
    $finish;
  end

  initial begin
    #10000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
