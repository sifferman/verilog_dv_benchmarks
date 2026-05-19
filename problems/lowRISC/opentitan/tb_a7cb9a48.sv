// Test prim_sha2_pad: digest_mode_flag_q must be set by hash_continue_i.
// Targets fix commit a7cb9a484e:
//   Buggy: digest_mode_flag_d ignores hash_continue_i, stays SHA2_None.
//   Fixed: hash_continue_i || hash_start_i sets digest_mode_flag_d.
//
// Consequence of the bug: after hash_continue_i the FSM enters StPad80/StPad00
// but tx_count never increments (requires digest_mode_flag_q != SHA2_None),
// txcnt_eq_1a0 is always 0, and the FSM is stuck forever — msg_feed_complete_o
// never asserts. The fixed RTL advances through the padding states and sets
// msg_feed_complete_o within ~25 cycles.
//
// Compatible with Verilator --timing.

module tb_prim_sha2_pad_continue;
  import prim_sha2_pkg::*;

  logic clk_i  = 0;
  logic rst_ni = 0;
  always #5 clk_i = ~clk_i;

  // DUT inputs
  logic          fifo_rvalid_i    = 0;
  sha_fifo64_t   fifo_rdata_i     = '0;
  logic          sha_en_i         = 0;
  logic          hash_start_i     = 0;
  logic          hash_continue_i  = 0;
  digest_mode_e  digest_mode_i    = SHA2_None;
  logic          hash_process_i   = 0;
  logic          hash_done_i      = 0;
  logic [127:0]  message_length_i = '0;
  logic          shaf_rready_i    = 0;

  // DUT outputs
  logic          fifo_rready_o;
  logic          shaf_rvalid_o;
  sha_word64_t   shaf_rdata_o;
  logic          msg_feed_complete_o;

  /* verilator lint_off PINMISSING */
  prim_sha2_pad #(.MultimodeEn(1)) dut (
    .clk_i,
    .rst_ni,
    .fifo_rvalid_i,
    .fifo_rdata_i,
    .fifo_rready_o,
    .shaf_rvalid_o,
    .shaf_rdata_o,
    .shaf_rready_i,
    .sha_en_i,
    .hash_start_i,
    .hash_continue_i,
    .digest_mode_i,
    .hash_process_i,
    .hash_done_i,
    .message_length_i,
    .msg_feed_complete_o
  );
  /* verilator lint_on PINMISSING */

  // Mirror the real ready/valid protocol: only accept data when the padding FSM
  // is actually producing it.  Asserting shaf_rready_i too early would fire
  // inc_txcount during StFifoReceive (before padding starts) and corrupt tx_count.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) shaf_rready_i <= 1'b0;
    else         shaf_rready_i <= shaf_rvalid_o;  // accept on the cycle after valid
  end

  initial begin
    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;

    // Trigger hash_continue with SHA2_256 mode, empty message.
    // This exercises the bug: on the buggy RTL, hash_continue_i does not
    // update digest_mode_flag_q, so it stays SHA2_None.  On the fixed RTL
    // it becomes SHA2_256, allowing the padding FSM to advance.
    @(posedge clk_i);
    sha_en_i         = 1;
    hash_continue_i  = 1;
    digest_mode_i    = SHA2_256;
    message_length_i = '0;

    @(posedge clk_i);
    hash_continue_i = 0;

    @(posedge clk_i);
    hash_process_i = 1;

    @(posedge clk_i);
    hash_process_i = 0;

    // Wait up to 60 cycles for msg_feed_complete_o.
    // Fixed:  advances through StPad80→StPad00(x13)→StLenHi→StLenLo→StIdle,
    //         msg_feed_complete_o asserts.
    // Buggy:  tx_count never increments, FSM stuck in StPad00 forever.
    fork
      begin : wait_pass
        wait (msg_feed_complete_o);
        $display("PASS: msg_feed_complete_o asserted — hash_continue_i set digest mode");
        $display("ALL TESTS PASSED");
        $finish(0);
      end
      begin : wait_fail
        repeat (60) @(posedge clk_i);
        disable wait_pass;
        $display("FAIL: msg_feed_complete_o never asserted after hash_continue_i");
        $display("      digest_mode_flag_q was not updated by hash_continue_i");
        $fatal(1, "Test failed");
      end
    join
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
