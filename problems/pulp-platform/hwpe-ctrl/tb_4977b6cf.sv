// Focused unit test for pulp-platform/hwpe-ctrl hwpe_ctrl_regfile_ff
// 1-cycle read latency fix (commit 4977b6c).
//
// Bug: The regfile previously had a purely combinational read path:
//      assign ReadData_o = (ReadEnable_i && (ReadAddr_i <= NumWords))
//                          ? data_q[ReadAddr_i] : '0;
// so the value of data_q[ReadAddr_i] propagated to ReadData_o in the same
// cycle the read was issued (zero latency).
//
// The fix registers the read output through r_data_q, so ReadData_o
// reflects the read with 1 cycle of latency.
//
// TB protocol (uses ReadEnable strobed for exactly one cycle on a known
// address):
//
//   Cycle 0 (after reset): write WriteData=V to addr 1, ReadEnable=0
//   Cycle 1 : data_q[1] = V is now visible. Drive ReadEnable=1, ReadAddr=1.
//             - Buggy RTL (combinational read): ReadData_o == V already.
//             - Fixed RTL (registered read):   ReadData_o still 0.
//   Cycle 2 : drop ReadEnable=0; read latched into r_data_q
//             - Buggy RTL: ReadData_o drops back to 0 (combinational gate
//                          drops because ReadEnable_i=0).
//             - Fixed RTL: ReadData_o == V (r_data_q just latched V).
//
// PASS condition (test of the FIXED behavior):
//   * On cycle 1 (read issued), ReadData_o == 0
//   * On cycle 2 (one cycle later), ReadData_o == V
// FAIL otherwise.

`timescale 1ns/1ps
module tb_4977b6cf;

  localparam int unsigned AddrWidth = 4;
  localparam int unsigned DataWidth = 32;
  localparam int unsigned NumByte   = DataWidth/8;
  localparam int unsigned NumWords  = 1 << AddrWidth;

  logic                 clk_i  = 1'b0;
  logic                 rst_ni = 1'b0;
  logic                 clear_i = 1'b0;
  logic                 ReadEnable_i = 1'b0;
  logic [AddrWidth-1:0] ReadAddr_i = '0;
  logic [DataWidth-1:0] ReadData_o;
  logic                 WriteEnable_i = 1'b0;
  logic [AddrWidth-1:0] WriteAddr_i = '0;
  logic [DataWidth-1:0] WriteData_i = '0;
  logic [NumByte-1:0]   WriteBE_i = '0;
  logic [NumWords-1:0][DataWidth-1:0] MemContent_o;

  // 10 ns clock
  always #5 clk_i = ~clk_i;

  hwpe_ctrl_regfile_ff #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth)
  ) dut (
    .clk_i,
    .rst_ni,
    .clear_i,
    .ReadEnable_i,
    .ReadAddr_i,
    .ReadData_o,
    .WriteEnable_i,
    .WriteAddr_i,
    .WriteData_i,
    .WriteBE_i,
    .MemContent_o
  );

  localparam logic [DataWidth-1:0] V = 32'hDEAD_BEEF;

  initial begin
    rst_ni = 1'b0;
    @(posedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
    @(negedge clk_i);

    // ---- Cycle 0 : write V to addr 1, ReadEnable=0 ----
    WriteEnable_i = 1'b1;
    WriteAddr_i   = 4'd1;
    WriteData_i   = V;
    WriteBE_i     = 4'b1111;
    ReadEnable_i  = 1'b0;
    ReadAddr_i    = 4'd1;

    @(posedge clk_i);
    // data_q[1] should now hold V (latched on this edge).
    @(negedge clk_i);
    WriteEnable_i = 1'b0;

    // ---- Cycle 1 : issue read of addr 1 ----
    ReadEnable_i = 1'b1;
    ReadAddr_i   = 4'd1;
    #1;
    // Sample combinational ReadData_o BEFORE the next clock edge.
    if (ReadData_o !== '0) begin
      $display("FAIL: cycle 1 combinational ReadData_o=%h (expected 0; read latency must be 1 cycle)",
               ReadData_o);
      $fatal(1, "regfile read is combinational (zero latency) -- buggy RTL");
    end

    @(posedge clk_i);
    @(negedge clk_i);
    ReadEnable_i = 1'b0;
    ReadAddr_i   = 4'd0;

    // ---- Cycle 2 : verify registered value emerges ----
    #1;
    if (ReadData_o !== V) begin
      $display("FAIL: cycle 2 ReadData_o=%h (expected %h; registered read did not emit value)",
               ReadData_o, V);
      $fatal(1, "regfile registered read did not latch expected value");
    end

    $display("PASS: regfile 1-cycle latency read returned %h", ReadData_o);
    $finish;
  end

  // Watchdog
  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
