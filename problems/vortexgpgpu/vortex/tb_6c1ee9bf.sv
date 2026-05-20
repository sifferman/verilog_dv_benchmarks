// Focused unit test for vortexgpgpu/vortex VX_cyclic_arbiter fix
// (commit 6c1ee9bf, 2024-08-12, "arbiter fixes").
//
// Bug: VX_cyclic_arbiter previously asserted grant_valid only when the
// current rotation index pointed at a pending request bit:
//     assign grant_valid = requests[grant_index_r];
// This meant a pending request not aligned with the current rotation index
// would be ignored until the index naturally rotated to it -- potentially
// stalling many cycles or even forever if the rotation didn't advance.
//
// The fix replaced the gating with a priority-encoder fallback so that an
// out-of-rotation pending request is granted in the same cycle, and the
// rotation index advances from the granted index.
//
// This TB instantiates the arbiter with NUM_REQS=4 and asserts a single
// non-rotation-aligned request (requests=4'b0010) immediately after reset
// (grant_index_r=0). The fixed RTL should grant_valid=1 with
// grant_index=1; the buggy RTL would report grant_valid=0.

`timescale 1ns/1ps
module tb_6c1ee9bf;

  logic        clk = 1'b0;
  logic        reset = 1'b1;
  logic [3:0]  requests;
  logic [1:0]  grant_index;
  logic [3:0]  grant_onehot;
  logic        grant_valid;
  logic        grant_ready;

  always #5 clk = ~clk;

  VX_cyclic_arbiter #(
      .NUM_REQS(4)
  ) dut (
      .clk         (clk),
      .reset       (reset),
      .requests    (requests),
      .grant_index (grant_index),
      .grant_onehot(grant_onehot),
      .grant_valid (grant_valid),
      .grant_ready (grant_ready)
  );

  initial begin
    requests    = 4'b0000;
    grant_ready = 1'b0;
    @(posedge clk);
    @(posedge clk);
    reset = 1'b0;
    @(posedge clk);
    // After reset, grant_index_r is 0. Set a non-aligned request.
    requests    = 4'b0010;
    grant_ready = 1'b1;
    #1;  // combinational settle
    if (!grant_valid) begin
      $display("FAIL: requests=4'b0010 immediately after reset yielded grant_valid=0");
      $fatal(1, "cyclic arbiter ignored out-of-rotation request");
    end
    if (grant_index !== 2'd1) begin
      $display("FAIL: grant_index=%0d expected 1", grant_index);
      $fatal(1, "cyclic arbiter granted wrong index");
    end
    $display("PASS: VX_cyclic_arbiter granted out-of-rotation request in same cycle.");
    $finish;
  end

  initial begin
    #1000;
    $display("FAIL: timeout");
    $fatal(1, "tb timeout");
  end
endmodule
