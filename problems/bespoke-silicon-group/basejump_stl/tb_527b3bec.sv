// Focused unit test for bsg_fifo_1r1w_small_hardened bypass fix
// (commit 527b3be, 2026-01-09).
//
// Bug: when a read-write-same-address (RWSA) event happens (enque to an
// empty fifo), the design used a single-cycle pulse `read_write_same_addr_r`
// to select between the bypass register and the hardened sync memory.
// If the consumer waits more than one cycle before dequeueing, the
// selection mux flips back to `data_o_mem` even though the hardened mem
// either was not written or has been replaced by the next entry. The
// fix replaces the 1-cycle flop with a set/clear flop that stays high
// until the next deque, so `data_o` reads from the bypass register for
// the entire duration.
//
// Probe: enque one word into an empty fifo (RWSA event), wait 3 idle
// cycles, then deque and check that the dequeued value matches the
// originally enqueued word.
//
//   Fixed RTL:  data_o == 32'hDEADBEEF -> PASS.
//   Buggy RTL:  data_o is stale / 0 / X after the RWSA pulse drops.

`timescale 1ns/1ps
module tb_527b3bec;

  localparam int unsigned width_p = 32;
  localparam int unsigned els_p   = 4;

  logic               clk;
  logic               reset;
  logic               v_i;
  logic               ready_param_o;
  logic [width_p-1:0] data_i;
  logic               v_o;
  logic [width_p-1:0] data_o;
  logic               yumi_i;

  bsg_fifo_1r1w_small_hardened #(
    .width_p(width_p),
    .els_p(els_p),
    .ready_THEN_valid_p(0)
  ) dut (
    .clk_i(clk),
    .reset_i(reset),
    .v_i(v_i),
    .ready_param_o(ready_param_o),
    .data_i(data_i),
    .v_o(v_o),
    .data_o(data_o),
    .yumi_i(yumi_i)
  );

  // Clock generator
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Test driver
  initial begin
    // initial values
    reset  = 1'b1;
    v_i    = 1'b0;
    data_i = '0;
    yumi_i = 1'b0;

    // Hold reset for a few cycles
    @(posedge clk); @(posedge clk); @(posedge clk);
    @(negedge clk);
    reset = 1'b0;

    // Wait one cycle so internal state settles after reset
    @(posedge clk);

    // ------------------------------------------------------------------
    // RWSA enque: fifo is empty, enque a known value.
    // This is the read-write-same-address case (wptr==rptr==0).
    // ------------------------------------------------------------------
    @(negedge clk);
    v_i    = 1'b1;
    data_i = 32'hDEAD_BEEF;
    yumi_i = 1'b0;

    @(posedge clk); // enque takes effect
    @(negedge clk);
    v_i    = 1'b0;
    data_i = '0;

    // Wait several idle cycles WITHOUT dequeueing.
    // In the buggy version, `read_write_same_addr_r` was a single-cycle
    // delayed copy of `_n`, so after this many idle cycles it has dropped
    // back to 0 and data_o switches to data_o_mem (which is stale / X /
    // never-driven thanks to the `latch_last_read_p=1` dff_en_bypass).
    repeat (5) @(posedge clk);

    // Now check v_o and data_o just before dequeueing.
    @(negedge clk);
    if (!v_o) begin
      $display("FAIL: fifo reports empty after enque (v_o=%0b).", v_o);
      $fatal(1, "v_o low after enque");
    end
    if (data_o !== 32'hDEAD_BEEF) begin
      $display("FAIL: data_o=0x%08h, expected 0xDEADBEEF.", data_o);
      $fatal(1, "buggy bypass mux dropped data after RWSA window");
    end

    // Deque the entry to confirm normal completion.
    yumi_i = 1'b1;
    @(posedge clk);
    @(negedge clk);
    yumi_i = 1'b0;

    $display("PASS: bypass register held data across multi-cycle RWSA window.");
    $finish;
  end

  // Safety watchdog
  initial begin
    #5000;
    $display("FAIL: watchdog timeout.");
    $fatal(1, "watchdog");
  end

endmodule
