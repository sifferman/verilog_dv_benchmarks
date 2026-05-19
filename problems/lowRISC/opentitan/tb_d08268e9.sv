// Test prim_subreg RC access corner case.
// Targets fix commit d08268e96afbb793f99fa164a39864ff4d981bea:
//   Buggy: assign qs = q  (always returns registered value)
//   Fixed: assign qs = de && we ? d : q  (during RC+HW collision, returns HW's d)
//
// When HW writes d simultaneously with SW RC read (we=1), qs should reflect
// the incoming HW value d, not the stale registered value q.
//
// Compatible with Verilator --timing.

`timescale 1ns/1ps
module tb_prim_subreg_rc;
  import prim_subreg_pkg::*;

  logic clk_i  = 0;
  logic rst_ni = 0;
  always #5 clk_i = ~clk_i;

  // DUT: 8-bit RC register
  logic       we, de;
  logic [7:0] wd, d;
  logic       qe;
  logic [7:0] q, ds, qs;

  prim_subreg #(
    .DW      (8),
    .SwAccess(SwAccessRC),
    .RESVAL  (8'h0)
  ) dut (
    .clk_i,
    .rst_ni,
    .we,
    .wd,
    .de,
    .d,
    .qe,
    .q,
    .ds,
    .qs
  );

  // qs is combinational — check it before the posedge updates q.
  // Procedure:
  //   1. Initialize q to 0xAA via a HW write (de=1, d=0xAA, we=0).
  //   2. Apply collision inputs: de=1, d=0xBB, we=1 (HW write + SW RC read).
  //   3. Check qs BEFORE the next posedge (q still holds 0xAA):
  //        Fixed: qs = d = 0xBB (SW sees the incoming HW value)
  //        Buggy: qs = q = 0xAA (SW sees the old registered value)
  //   4. After posedge, register should be 0 (cleared by RC + HW collision).

  initial begin
    we = 0; wd = '0; de = 0; d = '0;

    rst_ni = 0;
    repeat (4) @(posedge clk_i);
    rst_ni = 1;

    // Step 1: HW-write 0xAA so q becomes 0xAA.
    @(posedge clk_i);
    de = 1; d = 8'hAA; we = 0;
    @(posedge clk_i);  // q = 0xAA after this edge
    de = 0;

    // Step 2: Let q settle for one idle cycle.
    @(posedge clk_i);

    // Step 3: Apply collision — check qs BEFORE the posedge (q is still 0xAA).
    de = 1; d = 8'hBB; we = 1;
    #1;  // combinational settle; clk still at 1 (between posedge and negedge)

    if (qs !== 8'hBB) begin
      $display("FAIL: qs = 0x%02x, expected 0xBB during RC+HW collision", qs);
      $display("      prim_subreg assigns qs = q (stale value), not d (incoming HW value)");
      $fatal(1, "Test failed");
    end

    // Step 4: Advance clock — register must be cleared to 0 (RC semantics + HW write).
    @(posedge clk_i);
    de = 0; we = 0;
    @(posedge clk_i);

    if (q !== 8'h00) begin
      $display("FAIL: q = 0x%02x after RC, expected 0x00", q);
      $fatal(1, "Test failed");
    end

    $display("PASS: qs = 0xBB during RC+HW collision — prim_subreg RC fix correct");
    $display("ALL TESTS PASSED");
    $finish(0);
  end

  initial begin #100000; $fatal(1, "TIMEOUT"); end
endmodule
