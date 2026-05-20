// Focused unit test for pulp-platform/riscv-dbg dmi_jtag_tap reset state.
// Fix commit d7b8670 -- "src: Fix wrong reset state for TAP after trst_ni"
//
// Bug: In dmi_jtag_tap.sv, after asynchronous trst_ni reset the TAP state
// register was reset to `RunTestIdle` instead of `TestLogicReset`. This
// violates the JTAG spec: a trst_ni assertion must put the TAP in the
// Test-Logic-Reset state.
//
// Observable symptom (used by this TB): the TAP module drives
// `dmi_clear_o = test_logic_reset` (combinational, asserted exactly when
// tap_state_q == TestLogicReset). Immediately after releasing trst_ni
// (with tms_i = 0):
//   - Fixed RTL: tap_state_q == TestLogicReset => dmi_clear_o == 1 -> PASS
//   - Buggy RTL: tap_state_q == RunTestIdle    => dmi_clear_o == 0 -> FAIL
//
// We also confirm that with tms_i held low, the next TCK posedge advances
// the FSM out of TestLogicReset and dmi_clear_o drops to 0 (so we cannot
// false-pass on a static signal -- the fix has a real one-cycle pulse).

`timescale 1ns/1ps
module tb_d7b86704;

  logic tck_i    = 1'b0;
  logic tms_i    = 1'b0;
  logic trst_ni  = 1'b0;  // active-low async reset
  logic td_i     = 1'b0;
  logic testmode_i = 1'b0;

  logic td_o, tdo_oe_o, tck_o, dmi_clear_o;
  logic update_o, capture_o, shift_o, tdi_o;
  logic dtmcs_select_o, dmi_select_o;

  // No real DMI/DTMCS responder needed for this test
  logic dtmcs_tdo_i = 1'b0;
  logic dmi_tdo_i  = 1'b0;

  // 20 ns TCK period (50 MHz) -- realistic for JTAG.
  always #10 tck_i = ~tck_i;

  dmi_jtag_tap #(
    .IrLength    (5),
    .IdcodeValue (32'h00000001)
  ) dut (
    .tck_i,
    .tms_i,
    .trst_ni,
    .td_i,
    .td_o,
    .tdo_oe_o,
    .testmode_i,
    .tck_o,
    .dmi_clear_o,
    .update_o,
    .capture_o,
    .shift_o,
    .tdi_o,
    .dtmcs_select_o,
    .dtmcs_tdo_i,
    .dmi_select_o,
    .dmi_tdo_i
  );

  initial begin
    // Drive trst_ni low (asserted) for a couple of TCK cycles.
    trst_ni = 1'b0;
    tms_i   = 1'b0;
    repeat (3) @(posedge tck_i);

    // Release trst_ni asynchronously well before the next TCK edge so the
    // reset value of tap_state_q is fully settled.
    @(negedge tck_i);
    trst_ni = 1'b1;

    // After trst_ni deassertion (and before any TCK edge), tap_state_q
    // must equal TestLogicReset, which drives dmi_clear_o = 1.
    #1;  // small delta to allow combinational outputs to settle
    if (dmi_clear_o !== 1'b1) begin
      $display("FAIL: after trst_ni release, dmi_clear_o=%0b (expected 1; TAP not in Test-Logic-Reset)",
               dmi_clear_o);
      $fatal(1, "TAP did not reset to Test-Logic-Reset");
    end

    // With tms_i still low, next TCK posedge moves FSM to RunTestIdle,
    // so dmi_clear_o should drop. Verifies we are not stuck high spuriously.
    tms_i = 1'b0;
    @(posedge tck_i);
    #1;
    if (dmi_clear_o !== 1'b0) begin
      $display("FAIL: after first TCK posedge with tms=0, dmi_clear_o=%0b (expected 0)",
               dmi_clear_o);
      $fatal(1, "FSM did not transition out of TestLogicReset on tms=0");
    end

    $display("PASS: TAP entered Test-Logic-Reset after trst_ni and transitioned correctly.");
    $finish;
  end

  // Watchdog
  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
