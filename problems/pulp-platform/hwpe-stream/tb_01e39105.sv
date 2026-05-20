// Focused unit test for pulp-platform/hwpe-stream hwpe_stream_fifo_passthrough
// "Fix passthrough FIFO behavior" (commit 01e3910, 2025-11-30).
//
// Bug: The original passthrough computation conflated two distinct
// passthrough conditions:
//   * passthrough_rd: when push_i.valid arrives on an empty FIFO, the
//                     pop side should see it on the same cycle (read
//                     passthrough). Condition: push_i.valid & empty.
//   * passthrough_wr: when push_i.valid arrives on an empty FIFO AND
//                     pop_o.ready is asserted, the data should bypass
//                     the FIFO entirely (write passthrough). Condition:
//                     push_i.valid & pop_o.ready & empty.
//
// With the buggy code (single `passthrough = push_i.valid & flags_o.empty`)
// the module gated push.valid to the internal FIFO on `~passthrough`. So
// when push_i.valid=1, FIFO empty, and pop_o.ready=0, the internal FIFO
// never sees a write -- push.valid is 0 -- and push_i.ready is forced to
// pop_o.ready=0 too. The handshake stalls on the upstream side, even
// though the FIFO has space and could have accepted the beat.
//
// Fixed RTL: push.valid = push_i.valid & ~passthrough_wr. When pop_o.ready=0
// passthrough_wr=0, so the FIFO is allowed to accept the write and the
// upstream sees push_i.ready=1.
//
// Test: drive push_i.valid=1 with pop_o.ready=0 against an empty FIFO and
// assert that push_i.ready is 1. Buggy RTL returns 0 -> FAIL.

`timescale 1ns/1ps

module tb_01e39105;

  import hwpe_stream_package::*;

  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned FIFO_DEPTH = 4;

  logic clk_i  = 1'b0;
  logic rst_ni = 1'b0;
  logic clear_i = 1'b0;

  flags_fifo_t flags;

  always #5 clk_i = ~clk_i;

  hwpe_stream_intf_stream #(.DATA_WIDTH(DATA_WIDTH))
    push_if (.clk(clk_i));
  hwpe_stream_intf_stream #(.DATA_WIDTH(DATA_WIDTH))
    pop_if  (.clk(clk_i));

  hwpe_stream_fifo_passthrough #(
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

    // Drive push_i.valid=1 with pop_o.ready=0 against an empty FIFO. With
    // the fix the internal FIFO accepts the write and push_i.ready=1.
    @(negedge clk_i);
    push_valid = 1'b1;
    push_data  = 32'hCAFEBABE;
    push_strb  = '1;
    pop_ready  = 1'b0;
    #1;

    $display("INFO: empty=%0b push_ready=%0b pop_valid=%0b",
             flags.empty, push_if.ready, pop_if.valid);

    if (push_if.ready !== 1'b1) begin
      $display("FAIL: push_if.ready=%0b with empty FIFO and pop not ready (expected 1)",
               push_if.ready);
      $fatal(1, "passthrough FIFO blocks upstream when sink not ready -- bug present");
    end

    // Sanity: the data should also be visible at pop_o (read passthrough still works)
    if (pop_if.valid !== 1'b1) begin
      $display("FAIL: pop_if.valid=%0b on initial push to empty FIFO (expected 1)",
               pop_if.valid);
      $fatal(1, "passthrough FIFO does not forward push to pop on empty");
    end

    $display("PASS: passthrough FIFO accepts write into internal FIFO even when pop not ready.");
    $finish;
  end

  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
