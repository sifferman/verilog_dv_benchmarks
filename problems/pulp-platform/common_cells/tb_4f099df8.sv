// Focused unit test for pulp-platform/common_cells fifo_v3 fall-through bug
// (commit 4f099df, 2019-03-05):
//   "fifo_v3: Fix data output when pushing into empty fall-through FIFO".
//
// Bug: in FALL_THROUGH=1 mode, when the FIFO is empty and the producer
// asserts push_i (without pop_i), data_o should immediately reflect data_i
// (because empty_o is forced low and the stream contract says data is valid).
// In the buggy RTL data_o is only updated when both push_i AND pop_i are
// high. Without pop_i, data_o stays at stale mem_q[read_pointer_q] (=='0
// after reset), while empty_o=0 — the stream contract is violated.
//
//   Fixed RTL:  data_o follows data_i during push-without-pop -> PASS.
//   Buggy RTL:  data_o == 0 even though empty_o == 0          -> FAIL.

`timescale 1ns/1ps
module tb_4f099df8;

  localparam int unsigned DW = 8;
  localparam int unsigned DEPTH = 4;

  logic               clk_i  = 1'b0;
  logic               rst_ni = 1'b0;
  logic               flush_i = 1'b0;
  logic               testmode_i = 1'b0;
  logic               full_o, empty_o;
  logic [$clog2(DEPTH)-1:0] usage_o;
  logic [DW-1:0]      data_i = '0;
  logic               push_i = 1'b0;
  logic [DW-1:0]      data_o;
  logic               pop_i  = 1'b0;

  always #5 clk_i = ~clk_i;

  fifo_v3 #(
      .FALL_THROUGH (1'b1),
      .DATA_WIDTH   (DW),
      .DEPTH        (DEPTH)
  ) dut (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),
      .flush_i     (flush_i),
      .testmode_i  (testmode_i),
      .full_o      (full_o),
      .empty_o     (empty_o),
      .usage_o     (usage_o),
      .data_i      (data_i),
      .push_i      (push_i),
      .data_o      (data_o),
      .pop_i       (pop_i)
  );

  initial begin
    // Reset for a few cycles.
    rst_ni = 1'b0;
    repeat (3) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // FIFO is empty. Apply push_i with a distinctive payload, pop_i=0.
    data_i = 8'hA5;
    push_i = 1'b1;
    pop_i  = 1'b0;

    // settle combinational outputs
    #1;

    // empty_o should be deasserted (fall-through unblocks empty),
    // and data_o should reflect data_i in fall-through mode.
    if (empty_o !== 1'b0) begin
      $display("FAIL: empty_o=%0b expected 0 in fall-through push", empty_o);
      $fatal(1, "empty_o");
    end
    if (data_o === data_i) begin
      $display("PASS: data_o=%02h reflects data_i without pop (empty_o=%0b).",
               data_o, empty_o);
      $finish;
    end else begin
      $display("FAIL: data_o=%02h expected %02h (fall-through bug, no pop_i).",
               data_o, data_i);
      $fatal(1, "fall-through data not propagated without pop");
    end
  end

  // Watchdog
  initial begin
    #2000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
