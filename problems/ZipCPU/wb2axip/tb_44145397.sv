// Focused unit test for the WB2AXIP AXI-Lite upsizer WSTRB shift fix
// (commit 4414539, 2024-12-27).
//
// Bug: axilupsz.v computed M_AXIL_WSTRB by shifting the slave wstrb left by
// `addr_slot * SDW` (bits), instead of `addr_slot * (SDW/8)` (bytes). With
// SDW=32 and MDW=64, a write whose address selects the upper 32-bit slot
// requires WSTRB to land in bits[7:4] (i.e. shift by 4). The buggy RTL
// shifts by 32 instead, which evaluates to zero (shift out the top), so
// the master WSTRB comes out 8'h00 — silently dropping the write.
//
// Probe sequence: drive a single AW + W beat to byte address 0x04
// (the upper 32-bit slot of a 64-bit word at row 0) with S_AXIL_WSTRB=4'hF
// and observe M_AXIL_WSTRB.
//   Fixed RTL  -> M_AXIL_WSTRB == 8'hF0   -> PASS
//   Buggy RTL  -> M_AXIL_WSTRB == 8'h00   -> FAIL (assertion fires)

`timescale 1ns/1ps
module tb_44145397;

  localparam SDW = 32;
  localparam MDW = 64;
  localparam AW  = 32;

  reg                clk = 1'b0;
  reg                aresetn = 1'b0;

  // Slave side (inputs to DUT)
  reg                s_awvalid = 1'b0;
  wire               s_awready;
  reg  [AW-1:0]      s_awaddr  = '0;
  reg  [2:0]         s_awprot  = '0;

  reg                s_wvalid  = 1'b0;
  wire               s_wready;
  reg  [SDW-1:0]     s_wdata   = '0;
  reg  [SDW/8-1:0]   s_wstrb   = '0;

  wire               s_bvalid;
  reg                s_bready  = 1'b1;
  wire [1:0]         s_bresp;

  reg                s_arvalid = 1'b0;
  wire               s_arready;
  reg  [AW-1:0]      s_araddr  = '0;
  reg  [2:0]         s_arprot  = '0;

  wire               s_rvalid;
  reg                s_rready  = 1'b1;
  wire [SDW-1:0]     s_rdata;
  wire [1:0]         s_rresp;

  // Master side (outputs from DUT)
  wire               m_awvalid;
  reg                m_awready = 1'b1;
  wire [AW-1:0]      m_awaddr;
  wire [2:0]         m_awprot;

  wire               m_wvalid;
  reg                m_wready = 1'b1;
  wire [MDW-1:0]     m_wdata;
  wire [MDW/8-1:0]   m_wstrb;

  reg                m_bvalid  = 1'b0;
  wire               m_bready;
  reg  [1:0]         m_bresp   = 2'b00;

  wire               m_arvalid;
  reg                m_arready = 1'b1;
  wire [AW-1:0]      m_araddr;
  wire [2:0]         m_arprot;

  reg                m_rvalid  = 1'b0;
  wire               m_rready;
  reg  [MDW-1:0]     m_rdata   = '0;
  reg  [1:0]         m_rresp   = 2'b00;

  axilupsz #(
      .C_S_AXIL_DATA_WIDTH (SDW),
      .C_M_AXIL_DATA_WIDTH (MDW),
      .C_AXIL_ADDR_WIDTH   (AW),
      .LGFIFO              (5),
      .OPT_LOWPOWER        (1'b0)
  ) dut (
      .S_AXI_ACLK    (clk),
      .S_AXI_ARESETN (aresetn),

      .S_AXIL_AWVALID(s_awvalid),
      .S_AXIL_AWREADY(s_awready),
      .S_AXIL_AWADDR (s_awaddr),
      .S_AXIL_AWPROT (s_awprot),

      .S_AXIL_WVALID (s_wvalid),
      .S_AXIL_WREADY (s_wready),
      .S_AXIL_WDATA  (s_wdata),
      .S_AXIL_WSTRB  (s_wstrb),

      .S_AXIL_BVALID (s_bvalid),
      .S_AXIL_BREADY (s_bready),
      .S_AXIL_BRESP  (s_bresp),

      .S_AXIL_ARVALID(s_arvalid),
      .S_AXIL_ARREADY(s_arready),
      .S_AXIL_ARADDR (s_araddr),
      .S_AXIL_ARPROT (s_arprot),

      .S_AXIL_RVALID (s_rvalid),
      .S_AXIL_RREADY (s_rready),
      .S_AXIL_RDATA  (s_rdata),
      .S_AXIL_RRESP  (s_rresp),

      .M_AXIL_AWVALID(m_awvalid),
      .M_AXIL_AWREADY(m_awready),
      .M_AXIL_AWADDR (m_awaddr),
      .M_AXIL_AWPROT (m_awprot),

      .M_AXIL_WVALID (m_wvalid),
      .M_AXIL_WREADY (m_wready),
      .M_AXIL_WDATA  (m_wdata),
      .M_AXIL_WSTRB  (m_wstrb),

      .M_AXIL_BVALID (m_bvalid),
      .M_AXIL_BREADY (m_bready),
      .M_AXIL_BRESP  (m_bresp),

      .M_AXIL_ARVALID(m_arvalid),
      .M_AXIL_ARREADY(m_arready),
      .M_AXIL_ARADDR (m_araddr),
      .M_AXIL_ARPROT (m_arprot),

      .M_AXIL_RVALID (m_rvalid),
      .M_AXIL_RREADY (m_rready),
      .M_AXIL_RDATA  (m_rdata),
      .M_AXIL_RRESP  (m_rresp)
  );

  always #5 clk = ~clk;

  initial begin
    // Reset
    aresetn = 1'b0;
    repeat (4) @(posedge clk);
    aresetn = 1'b1;
    @(posedge clk);

    // Drive AW at addr 0x04 (upper 32-bit slot of 64-bit master row 0),
    // W with strb=4'hF
    s_awvalid = 1'b1;
    s_awaddr  = 32'h0000_0004;
    s_awprot  = 3'b000;

    s_wvalid  = 1'b1;
    s_wdata   = 32'hDEAD_BEEF;
    s_wstrb   = 4'hF;

    // Wait until handshake completes on both AW and W
    while (!(s_awvalid && s_awready)) @(posedge clk);
    @(posedge clk);
    s_awvalid = 1'b0;
    s_wvalid  = 1'b0;

    // Wait one more cycle for the upsizer to drive M_AXIL_W*
    while (!m_wvalid) @(posedge clk);

    $display("INFO: M_AXIL_WSTRB = 0x%02h (expected 0xF0 for addr=0x04)", m_wstrb);
    if (m_wstrb !== 8'hF0) begin
      $display("FAIL: WSTRB shift wrong — got 0x%02h, expected 0xF0", m_wstrb);
      $fatal(1, "axilupsz WSTRB byte-shift bug observed");
    end

    $display("PASS: WSTRB correctly shifted to upper half (0xF0).");
    $finish;
  end

  // Watchdog
  initial begin
    #2000;
    $display("FAIL: testbench watchdog expired");
    $fatal(1, "timeout — DUT never produced M_AXIL_WVALID");
  end

endmodule
