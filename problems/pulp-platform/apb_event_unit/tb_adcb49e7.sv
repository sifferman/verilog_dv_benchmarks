// Focused unit test for pulp-platform/apb_event_unit "Addressing bug fixed"
// (commit adcb49e, 2015-10-22).
//
// Among other things, this fix flips the default PREADY in the output mux
// when no slave is being selected. The buggy code held PREADY = 1'b0 when
// PSEL is deasserted, which violates the APB spec: an APB slave is supposed
// to keep PREADY high in its idle state so that any spurious transaction
// (e.g. the master holding PSEL=0) is acknowledged without stalling.
// The fix sets `PREADY = 1'b1` in the no-select branch.
//
// Test: tie PSEL=0 in steady state and observe PREADY.
//   Fixed RTL  -> PREADY = 1
//   Buggy RTL  -> PREADY = 0
//
// This test does not exercise the apb_event_unit internals: it only checks
// the top-level output-mux default which is what the fix changes.

`timescale 1ns/1ps

module tb_adcb49e7;

  localparam int APB_ADDR_WIDTH = 12;

  logic                      HCLK    = 1'b0;
  logic                      HRESETn = 1'b0;
  logic [APB_ADDR_WIDTH-1:0] PADDR   = '0;
  logic [31:0]               PWDATA  = '0;
  logic                      PWRITE  = 1'b0;
  logic                      PSEL    = 1'b0;
  logic                      PENABLE = 1'b0;
  logic [31:0]               PRDATA;
  logic                      PREADY;
  logic                      PSLVERR;

  logic [31:0] irq_i   = '0;
  logic [31:0] event_i = '0;
  logic [31:0] irq_o;

  logic        fetch_enable_o;
  logic        clk_gate_core_o;
  logic        core_busy_i = 1'b1; // keep RUN state

  always #5 HCLK = ~HCLK;

  apb_event_unit #(
    .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
  ) dut (
    .HCLK            (HCLK),
    .HRESETn         (HRESETn),
    .PADDR           (PADDR),
    .PWDATA          (PWDATA),
    .PWRITE          (PWRITE),
    .PSEL            (PSEL),
    .PENABLE         (PENABLE),
    .PRDATA          (PRDATA),
    .PREADY          (PREADY),
    .PSLVERR         (PSLVERR),
    .irq_i           (irq_i),
    .event_i         (event_i),
    .irq_o           (irq_o),
    .fetch_enable_o  (fetch_enable_o),
    .clk_gate_core_o (clk_gate_core_o),
    .core_busy_i     (core_busy_i)
  );

  initial begin
    HRESETn = 1'b0;
    @(posedge HCLK);
    @(posedge HCLK);
    HRESETn = 1'b1;
    @(posedge HCLK);
    @(posedge HCLK);
    #1;

    // PSEL is held low: slave is idle. APB spec says PREADY must be high.
    $display("INFO: PSEL=%0b PENABLE=%0b -> PREADY=%0b PRDATA=%h",
             PSEL, PENABLE, PREADY, PRDATA);

    if (PREADY !== 1'b1) begin
      $display("FAIL: PREADY=%0b expected 1 when PSEL is low (idle default bug)",
               PREADY);
      $fatal(1, "PREADY idle default still 0 -- bug present");
    end

    $display("PASS: PREADY correctly defaults to 1 when no slave is selected.");
    $finish;
  end

  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
