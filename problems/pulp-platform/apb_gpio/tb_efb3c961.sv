// Focused unit test for pulp-platform/apb_gpio padoutclr polarity fix
// "change polarity of padoutclr content. A 1'b1 at index i will clear the
// gpio i output" (commit efb3c96, 2019-08-22).
//
// Bug: PADOUTCLR was assigning `s_gpio_out[i] = r_gpio_out[i] & PWDATA[i]`.
// That logic only KEEPS bits where the PWDATA mask is 1 -- i.e. it clears
// everything except the masked bits, the OPPOSITE of what PADOUTCLR is
// supposed to do. The fix inverts the mask: `r_gpio_out[i] & ~PWDATA[i]`,
// so a 1 in PWDATA clears the corresponding output bit.
//
// Test:
//   1) Write PADOUT = 0xFFFFFFFF (all outputs driven high).
//   2) Write PADOUTCLR = 0x0000000F (clear lower 4 bits).
//   3) Read PADOUT.
//      Fixed RTL  -> 0xFFFFFFF0 (only bits [3:0] cleared)
//      Buggy RTL  -> 0x0000000F (only bits [3:0] kept, all others cleared)
//   We require the upper bits to remain set.

`timescale 1ns/1ps

module tb_efb3c961;

  localparam int APB_ADDR_WIDTH = 12;
  localparam int PAD_NUM        = 32;

  logic                      HCLK    = 1'b0;
  logic                      HRESETn = 1'b0;
  logic                      dft_cg_enable_i = 1'b0;

  logic [APB_ADDR_WIDTH-1:0] PADDR   = '0;
  logic [31:0]               PWDATA  = '0;
  logic                      PWRITE  = 1'b0;
  logic                      PSEL    = 1'b0;
  logic                      PENABLE = 1'b0;
  logic [31:0]               PRDATA;
  logic                      PREADY;
  logic                      PSLVERR;

  logic [PAD_NUM-1:0]       gpio_in = '0;
  logic [PAD_NUM-1:0]       gpio_in_sync;
  logic [PAD_NUM-1:0]       gpio_out;
  logic [PAD_NUM-1:0]       gpio_dir;
  logic [PAD_NUM-1:0][3:0]  gpio_padcfg;
  logic                     interrupt;

  always #5 HCLK = ~HCLK;

  apb_gpio #(
      .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
      .PAD_NUM       (PAD_NUM)
  ) dut (
      .HCLK            (HCLK),
      .HRESETn         (HRESETn),
      .dft_cg_enable_i (dft_cg_enable_i),
      .PADDR           (PADDR),
      .PWDATA          (PWDATA),
      .PWRITE          (PWRITE),
      .PSEL            (PSEL),
      .PENABLE         (PENABLE),
      .PRDATA          (PRDATA),
      .PREADY          (PREADY),
      .PSLVERR         (PSLVERR),
      .gpio_in         (gpio_in),
      .gpio_in_sync    (gpio_in_sync),
      .gpio_out        (gpio_out),
      .gpio_dir        (gpio_dir),
      .gpio_padcfg     (gpio_padcfg),
      .interrupt       (interrupt)
  );

  // PADDR[6:2] selects register; pass register index pre-shifted by 2.
  task automatic apb_write(input [4:0] reg_idx, input [31:0] data);
    @(negedge HCLK);
    PADDR   = {5'b0, reg_idx, 2'b00};
    PWDATA  = data;
    PWRITE  = 1'b1;
    PSEL    = 1'b1;
    PENABLE = 1'b0;
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

    // 1) drive all outputs high
    //    REG_PADOUT_00_31 = 5'b00011 (= 3)
    apb_write(5'd3, 32'hFFFF_FFFF);
    @(posedge HCLK);
    #1;

    if (gpio_out !== 32'hFFFF_FFFF) begin
      $display("FAIL: after PADOUT write, gpio_out=%h expected FFFFFFFF",
               gpio_out);
      $fatal(1, "PADOUT write did not take effect");
    end

    // 2) clear only the low 4 bits via PADOUTCLR
    //    REG_PADOUTCLR_00_31 = 5'b00101 (= 5)
    apb_write(5'd5, 32'h0000_000F);
    @(posedge HCLK);
    #1;

    $display("INFO: gpio_out after PADOUTCLR=0x0F -> %h (expected FFFFFFF0)",
             gpio_out);

    if (gpio_out !== 32'hFFFF_FFF0) begin
      $display("FAIL: PADOUTCLR polarity bug -- gpio_out=%h, expected FFFFFFF0",
               gpio_out);
      $fatal(1, "PADOUTCLR inverted polarity bug present");
    end

    $display("PASS: PADOUTCLR correctly clears bits where mask is 1.");
    $finish;
  end

  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
