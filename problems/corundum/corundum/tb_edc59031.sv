// SPDX-License-Identifier: BSD-2-Clause-Views
// Focused testbench for corundum commit edc59031:
//   "fpga/common: Fix FIFO status connections"
// rx_fifo (and tx_fifo) had buggy per-port generate that connected the
// 1-bit `.status_overflow / .status_bad_frame / .status_good_frame` ports
// to the *whole* PORTS-wide status bus instead of bit `n`.
// Effect: only bit 0 carries any signal and is multi-driver-contested;
// bits [PORTS-1:1] are stuck at 0 regardless of which port saw a frame.
//
// Strategy: instantiate rx_fifo with PORTS=2 and a single short frame
// targeted at the SECOND port (n=1). On the fixed RTL the n=1 fifo asserts
// `status_good_frame[1]` for one cycle. On the buggy RTL bit 1 stays 0.

`timescale 1ns / 1ps
`default_nettype none

module tb_edc59031;

    localparam PORTS = 2;
    localparam S_DATA_WIDTH = 8;
    localparam S_KEEP_WIDTH = (S_DATA_WIDTH/8);
    localparam M_DATA_WIDTH = 8*PORTS;
    localparam M_KEEP_WIDTH = (M_DATA_WIDTH/8);
    localparam USER_WIDTH = 1;
    localparam S_ID_WIDTH = 1;
    localparam DEST_WIDTH = 8;
    localparam FIFO_DEPTH = 4096;
    localparam FIFO_DEPTH_WIDTH = $clog2(FIFO_DEPTH)+1;
    localparam M_ID_WIDTH = $clog2(PORTS);

    reg clk = 0;
    reg rst = 1;

    always #5 clk = ~clk;  // 100MHz

    // Per-port AXIS in
    reg  [PORTS*S_DATA_WIDTH-1:0] s_axis_tdata = 0;
    reg  [PORTS*S_KEEP_WIDTH-1:0] s_axis_tkeep = {(PORTS*S_KEEP_WIDTH){1'b1}};
    reg  [PORTS-1:0]              s_axis_tvalid = 0;
    wire [PORTS-1:0]              s_axis_tready;
    reg  [PORTS-1:0]              s_axis_tlast = 0;
    reg  [PORTS*S_ID_WIDTH-1:0]   s_axis_tid = 0;
    reg  [PORTS*DEST_WIDTH-1:0]   s_axis_tdest = 0;
    reg  [PORTS*USER_WIDTH-1:0]   s_axis_tuser = 0;  // 0 = good frame

    // Aggregated AXIS out
    wire [M_DATA_WIDTH-1:0]       m_axis_tdata;
    wire [M_KEEP_WIDTH-1:0]       m_axis_tkeep;
    wire                          m_axis_tvalid;
    reg                           m_axis_tready = 1'b1;
    wire                          m_axis_tlast;
    wire [M_ID_WIDTH-1:0]         m_axis_tid;
    wire [DEST_WIDTH-1:0]         m_axis_tdest;
    wire [USER_WIDTH-1:0]         m_axis_tuser;

    wire [PORTS-1:0]                  status_overflow;
    wire [PORTS-1:0]                  status_bad_frame;
    wire [PORTS-1:0]                  status_good_frame;

    rx_fifo #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .PORTS(PORTS),
        .S_DATA_WIDTH(S_DATA_WIDTH),
        .S_KEEP_ENABLE(1),
        .S_KEEP_WIDTH(S_KEEP_WIDTH),
        .M_DATA_WIDTH(M_DATA_WIDTH),
        .M_KEEP_ENABLE(1),
        .M_KEEP_WIDTH(M_KEEP_WIDTH),
        .ID_ENABLE(1),
        .S_ID_WIDTH(S_ID_WIDTH),
        .M_ID_WIDTH(M_ID_WIDTH),
        .DEST_ENABLE(0),
        .DEST_WIDTH(DEST_WIDTH),
        .USER_ENABLE(1),
        .USER_WIDTH(USER_WIDTH),
        .RAM_PIPELINE(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tid(s_axis_tid),
        .s_axis_tdest(s_axis_tdest),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tid(m_axis_tid),
        .m_axis_tdest(m_axis_tdest),
        .m_axis_tuser(m_axis_tuser),
        .status_overflow(status_overflow),
        .status_bad_frame(status_bad_frame),
        .status_good_frame(status_good_frame)
    );

    // Latch which bit(s) of status_good_frame fire during the test
    reg [PORTS-1:0] sgf_seen = 0;
    always @(posedge clk) begin
        if (rst)
            sgf_seen <= 0;
        else
            sgf_seen <= sgf_seen | status_good_frame;
    end

    integer i;
    integer cycles;
    initial begin
        // Reset
        #20 rst = 1'b1;
        #100 rst = 1'b0;
        @(posedge clk);

        // Send a single 4-byte frame on port 1 (the upper port)
        @(posedge clk);
        for (i = 0; i < 4; i = i + 1) begin
            s_axis_tdata[1*S_DATA_WIDTH +: S_DATA_WIDTH] = 8'hA0 + i[7:0];
            s_axis_tkeep[1*S_KEEP_WIDTH +: S_KEEP_WIDTH] = {S_KEEP_WIDTH{1'b1}};
            s_axis_tvalid[1] = 1'b1;
            s_axis_tlast[1]  = (i == 3);
            s_axis_tuser[1]  = 1'b0; // good frame
            @(posedge clk);
            while (!s_axis_tready[1]) @(posedge clk);
        end
        s_axis_tvalid[1] = 1'b0;
        s_axis_tlast[1]  = 1'b0;

        // Wait for the frame to drain through and good_frame pulse to land
        for (cycles = 0; cycles < 1500; cycles = cycles + 1) @(posedge clk);

        // After fix: sgf_seen[1] should be 1 (port 1 saw a good frame).
        // Buggy: sgf_seen[1] stays 0 because rx_fifo connects the 1-bit
        // per-instance output to the entire PORTS-wide bus (only bit 0
        // is driven; high bits padded with zero by iverilog).
        $display("sgf_seen = %b", sgf_seen);

        if (sgf_seen[1] !== 1'b1) begin
            $display("FAIL: status_good_frame[1] never asserted -- rx_fifo bug present");
            $fatal(1);
        end

        $display("PASS: status_good_frame[1] asserted as expected");
        $finish;
    end

    // global watchdog
    initial begin
        #200000;
        $display("FAIL: watchdog timeout");
        $fatal(1);
    end

endmodule
