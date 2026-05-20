// Focused unit test for pulp-platform/apb_spi_master spi_master_apb_if
// "Fix to fifo_tx in spi master APB version" (commit 4fce41f, 2015-01-30).
//
// Bug: spi_data_tx (a top-level output of spi_master_apb_if) was never
// assigned. The fix adds:
//   assign spi_data_tx = PWDATA;
// so APB writes to REG_TXFIFO forward the write-data onto the spi_data_tx
// output. Without this, any consumer of spi_data_tx (the SPI shifter)
// receives 0 instead of the requested transmit word.
//
// Test:
//   1) Issue an APB write to REG_TXFIFO (offset 0x18 -> PADDR[4:2]=3'b110)
//      with PWDATA = 0xCAFEBABE.
//   2) Sample spi_data_tx during the ACCESS phase.
//      Fixed RTL: spi_data_tx == 0xCAFEBABE.
//      Buggy RTL: spi_data_tx == 0 (output never assigned).

`timescale 1ns/1ps

module tb_4fce41f5;

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

  logic [7:0]                spi_clk_div;
  logic                      spi_clk_div_valid;
  logic [31:0]               spi_status = '0;
  logic [31:0]               spi_addr;
  logic [5:0]                spi_addr_len;
  logic [31:0]               spi_cmd;
  logic [5:0]                spi_cmd_len;
  logic [3:0]                spi_csreg;
  logic [15:0]               spi_data_len;
  logic [15:0]               spi_dummy_rd;
  logic [15:0]               spi_dummy_wr;
  logic                      spi_swrst;
  logic                      spi_rd;
  logic                      spi_wr;
  logic                      spi_qrd;
  logic                      spi_qwr;
  logic [31:0]               spi_data_tx;
  logic                      spi_data_tx_valid;
  logic                      spi_data_tx_ready = 1'b1; // always accept
  logic [31:0]               spi_data_rx       = '0;
  logic                      spi_data_rx_valid = 1'b0;
  logic                      spi_data_rx_ready;

  always #5 HCLK = ~HCLK;

  spi_master_apb_if #(
    .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
  ) dut (
    .HCLK(HCLK), .HRESETn(HRESETn),
    .PADDR(PADDR), .PWDATA(PWDATA), .PWRITE(PWRITE),
    .PSEL(PSEL), .PENABLE(PENABLE),
    .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
    .spi_clk_div(spi_clk_div),
    .spi_clk_div_valid(spi_clk_div_valid),
    .spi_status(spi_status),
    .spi_addr(spi_addr),
    .spi_addr_len(spi_addr_len),
    .spi_cmd(spi_cmd),
    .spi_cmd_len(spi_cmd_len),
    .spi_csreg(spi_csreg),
    .spi_data_len(spi_data_len),
    .spi_dummy_rd(spi_dummy_rd),
    .spi_dummy_wr(spi_dummy_wr),
    .spi_swrst(spi_swrst),
    .spi_rd(spi_rd), .spi_wr(spi_wr),
    .spi_qrd(spi_qrd), .spi_qwr(spi_qwr),
    .spi_data_tx(spi_data_tx),
    .spi_data_tx_valid(spi_data_tx_valid),
    .spi_data_tx_ready(spi_data_tx_ready),
    .spi_data_rx(spi_data_rx),
    .spi_data_rx_valid(spi_data_rx_valid),
    .spi_data_rx_ready(spi_data_rx_ready)
  );

  initial begin
    HRESETn = 1'b0;
    @(posedge HCLK);
    @(posedge HCLK);
    HRESETn = 1'b1;
    @(posedge HCLK);

    // APB write to REG_TXFIFO (PADDR[4:2] = 3'b110 -> offset 0x18)
    @(negedge HCLK);
    PADDR   = 12'h018;
    PWDATA  = 32'hCAFE_BABE;
    PWRITE  = 1'b1;
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    @(negedge HCLK);
    PENABLE = 1'b1;        // ACCESS phase
    #1;

    $display("INFO: during APB ACCESS phase spi_data_tx=%h spi_data_tx_valid=%b",
             spi_data_tx, spi_data_tx_valid);

    if (spi_data_tx_valid !== 1'b1) begin
      $display("FAIL: spi_data_tx_valid not asserted during ACCESS phase");
      $fatal(1, "spi_data_tx_valid not asserted");
    end

    if (spi_data_tx !== 32'hCAFE_BABE) begin
      $display("FAIL: spi_data_tx=%h expected CAFEBABE -- output never assigned",
               spi_data_tx);
      $fatal(1, "spi_data_tx not driven from PWDATA -- bug present");
    end

    @(negedge HCLK);
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    PWRITE  = 1'b0;

    $display("PASS: spi_data_tx forwarded from PWDATA on REG_TXFIFO write.");
    $finish;
  end

  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
