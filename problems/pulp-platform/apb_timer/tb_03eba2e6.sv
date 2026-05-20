// Focused unit test for pulp-platform/apb_timer timer.sv
// "apb_timer.sv: Fix prescaler behavior" (commit 03eba2e, 2025-10-30).
//
// Bug: The prescaler cycle counter was compared against the entire
// REG_TIMER_CTRL value instead of just the prescaler field (bits [5:3]):
//
//     if (cycle_counter_q >= regs_q[`REG_TIMER_CTRL])
//         cycle_counter_n = 32'b0;
//
// REG_TIMER_CTRL also holds the enable bit (bit 0), so a write like
// `(prescaler<<3) | 1` makes the buggy code only reset cycle_counter
// after `(prescaler<<3) | 1` cycles instead of `prescaler` cycles, which
// dramatically slows the timer when the prescaler is small.
//
// Test setup: enable timer with prescaler field=2 (smallest non-zero
// prescaler value). REG_TIMER_CTRL = (2<<3)|1 = 0x11 = 17 decimal.
//   Fixed RTL: REG_TIMER increments every 3 cycles (one tick every
//     prescaler_int+1 cycles, since the increment occurs on the cycle
//     when cycle_counter == prescaler_int).
//   Buggy RTL: REG_TIMER increments roughly every 18 cycles because the
//     prescaler counter only resets after 17 cycles.
//
// After 30 cycles the fixed version's REG_TIMER should be around 10 and
// the buggy version's should still be <=2. We sample after 30 cycles
// and require REG_TIMER >= 5 to pass.

`timescale 1ns/1ps

module tb_03eba2e6;

  logic HCLK   = 1'b0;
  logic HRESETn = 1'b0;
  logic [11:0] PADDR  = '0;
  logic [31:0] PWDATA = '0;
  logic        PWRITE = 1'b0;
  logic        PSEL   = 1'b0;
  logic        PENABLE = 1'b0;
  logic [31:0] PRDATA;
  logic        PREADY;
  logic        PSLVERR;
  logic [1:0]  irq_o;

  always #5 HCLK = ~HCLK;

  timer dut (
    .HCLK   (HCLK),
    .HRESETn(HRESETn),
    .PADDR  (PADDR),
    .PWDATA (PWDATA),
    .PWRITE (PWRITE),
    .PSEL   (PSEL),
    .PENABLE(PENABLE),
    .PRDATA (PRDATA),
    .PREADY (PREADY),
    .PSLVERR(PSLVERR),
    .irq_o  (irq_o)
  );

  // Two-phase APB write: SETUP + ACCESS.
  task apb_write(input [11:0] addr, input [31:0] data);
    @(negedge HCLK);
    PADDR  = addr;
    PWDATA = data;
    PWRITE = 1'b1;
    PSEL   = 1'b1;
    PENABLE= 1'b0;
    @(negedge HCLK);
    PENABLE = 1'b1;
    @(negedge HCLK);
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    PWRITE  = 1'b0;
  endtask

  initial begin
    HRESETn = 1'b0;
    @(posedge HCLK);
    @(posedge HCLK);
    HRESETn = 1'b1;
    @(posedge HCLK);

    // Enable timer with prescaler field = 3'b010 (=2). REG_TIMER_CTRL value
    // is (2<<3) | 1 = 17.
    apb_write(12'h4 /* REG_TIMER_CTRL */, 32'h11);

    // Let the timer run for 30 clock cycles after enabling.
    repeat (30) @(posedge HCLK);
    #1;

    $display("INFO: REG_TIMER = %0d (cycle_counter_q=%0d, prescaler_int=%0d)",
             dut.regs_q[0], dut.cycle_counter_q, dut.prescaler_int);

    // With the fix REG_TIMER should be >= 5 after 30 cycles (~10 expected).
    // With the bug it stays at 0 or 1 because the prescaler counter only
    // wraps after 17 cycles.
    if (dut.regs_q[0] < 32'd5) begin
      $display("FAIL: REG_TIMER=%0d, expected >=5 (prescaler reset bug present)",
               dut.regs_q[0]);
      $fatal(1, "apb_timer prescaler bug -- counts too slowly when prescaler is small");
    end

    $display("PASS: prescaler reset using prescaler field, not full REG_TIMER_CTRL.");
    $finish;
  end

  initial begin
    #10000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
