// Focused unit test for pulp-platform/per2axi per2axi_req_channel handshake fix
// (commit 9226058 -- "per2axi_req_channel: Fix handshake on `per_slave` port").
//
// Bug: per_slave_gnt_o was driven by:
//     assign per_slave_gnt_o = axi_master_aw_ready_i && axi_master_ar_ready_i;
// On a write transaction this asserted the slave grant whenever the AW and
// AR channels were ready, regardless of whether the W channel was ready.
// If W was not yet ready, the peripheral interconnect could see the grant
// and complete the transaction handshake on its side while the W beat was
// silently dropped -- a transaction-loss bug.
//
// The fix ANDs `axi_master_w_ready_i` into the grant expression so the
// grant is only asserted when all three channels are ready.
//
// Test:
//   Drive per_slave_req_i=1, per_slave_we_i=0 (write), per_slave_be_i=4'b1111,
//   and AW=READY, AR=READY, W=NOT_READY. Then:
//     - Fixed RTL: per_slave_gnt_o must be 0 (W not ready)
//     - Buggy RTL: per_slave_gnt_o = AW & AR = 1 (lost transaction)
//
//   As a sanity-PASS pair we also verify that when all three channels are
//   ready, the grant is asserted under both versions (so the test cannot be
//   trivially satisfied by tying gnt to 0).

`timescale 1ns/1ps
module tb_92260580;

  // Use module defaults for parameters.
  logic                      per_slave_req_i = 1'b0;
  logic [31:0]               per_slave_add_i = '0;
  logic                      per_slave_we_i  = 1'b0;
  logic [31:0]               per_slave_wdata_i = '0;
  logic [3:0]                per_slave_be_i  = 4'b1111;
  logic [4:0]                per_slave_id_i  = '0;
  logic                      per_slave_gnt_o;

  // AXI master AW
  logic axi_master_aw_valid_o;
  logic [31:0] axi_master_aw_addr_o;
  logic [2:0]  axi_master_aw_prot_o;
  logic [3:0]  axi_master_aw_region_o;
  logic [7:0]  axi_master_aw_len_o;
  logic [2:0]  axi_master_aw_size_o;
  logic [1:0]  axi_master_aw_burst_o;
  logic        axi_master_aw_lock_o;
  logic [3:0]  axi_master_aw_cache_o;
  logic [3:0]  axi_master_aw_qos_o;
  logic [2:0]  axi_master_aw_id_o;
  logic [5:0]  axi_master_aw_user_o;
  logic        axi_master_aw_ready_i = 1'b0;

  // AXI master AR
  logic        axi_master_ar_valid_o;
  logic [31:0] axi_master_ar_addr_o;
  logic [2:0]  axi_master_ar_prot_o;
  logic [3:0]  axi_master_ar_region_o;
  logic [7:0]  axi_master_ar_len_o;
  logic [2:0]  axi_master_ar_size_o;
  logic [1:0]  axi_master_ar_burst_o;
  logic        axi_master_ar_lock_o;
  logic [3:0]  axi_master_ar_cache_o;
  logic [3:0]  axi_master_ar_qos_o;
  logic [2:0]  axi_master_ar_id_o;
  logic [5:0]  axi_master_ar_user_o;
  logic        axi_master_ar_ready_i = 1'b0;

  // AXI master W
  logic        axi_master_w_valid_o;
  logic [63:0] axi_master_w_data_o;
  logic [7:0]  axi_master_w_strb_o;
  logic [5:0]  axi_master_w_user_o;
  logic        axi_master_w_last_o;
  logic        axi_master_w_ready_i = 1'b0;

  // Control
  logic        trans_req_o;
  logic [2:0]  trans_id_o;
  logic [31:0] trans_add_o;

  per2axi_req_channel dut (
    .per_slave_req_i      (per_slave_req_i),
    .per_slave_add_i      (per_slave_add_i),
    .per_slave_we_i       (per_slave_we_i),
    .per_slave_wdata_i    (per_slave_wdata_i),
    .per_slave_be_i       (per_slave_be_i),
    .per_slave_id_i       (per_slave_id_i),
    .per_slave_gnt_o      (per_slave_gnt_o),
    .axi_master_aw_valid_o (axi_master_aw_valid_o),
    .axi_master_aw_addr_o  (axi_master_aw_addr_o),
    .axi_master_aw_prot_o  (axi_master_aw_prot_o),
    .axi_master_aw_region_o(axi_master_aw_region_o),
    .axi_master_aw_len_o   (axi_master_aw_len_o),
    .axi_master_aw_size_o  (axi_master_aw_size_o),
    .axi_master_aw_burst_o (axi_master_aw_burst_o),
    .axi_master_aw_lock_o  (axi_master_aw_lock_o),
    .axi_master_aw_cache_o (axi_master_aw_cache_o),
    .axi_master_aw_qos_o   (axi_master_aw_qos_o),
    .axi_master_aw_id_o    (axi_master_aw_id_o),
    .axi_master_aw_user_o  (axi_master_aw_user_o),
    .axi_master_aw_ready_i (axi_master_aw_ready_i),
    .axi_master_ar_valid_o (axi_master_ar_valid_o),
    .axi_master_ar_addr_o  (axi_master_ar_addr_o),
    .axi_master_ar_prot_o  (axi_master_ar_prot_o),
    .axi_master_ar_region_o(axi_master_ar_region_o),
    .axi_master_ar_len_o   (axi_master_ar_len_o),
    .axi_master_ar_size_o  (axi_master_ar_size_o),
    .axi_master_ar_burst_o (axi_master_ar_burst_o),
    .axi_master_ar_lock_o  (axi_master_ar_lock_o),
    .axi_master_ar_cache_o (axi_master_ar_cache_o),
    .axi_master_ar_qos_o   (axi_master_ar_qos_o),
    .axi_master_ar_id_o    (axi_master_ar_id_o),
    .axi_master_ar_user_o  (axi_master_ar_user_o),
    .axi_master_ar_ready_i (axi_master_ar_ready_i),
    .axi_master_w_valid_o  (axi_master_w_valid_o),
    .axi_master_w_data_o   (axi_master_w_data_o),
    .axi_master_w_strb_o   (axi_master_w_strb_o),
    .axi_master_w_user_o   (axi_master_w_user_o),
    .axi_master_w_last_o   (axi_master_w_last_o),
    .axi_master_w_ready_i  (axi_master_w_ready_i),
    .trans_req_o           (trans_req_o),
    .trans_id_o            (trans_id_o),
    .trans_add_o           (trans_add_o)
  );

  initial begin
    // Stimulus: peripheral wants to issue a write; AW and AR ready, but W not.
    per_slave_req_i       = 1'b1;
    per_slave_we_i        = 1'b0;        // 0 means write in this DUT
    per_slave_be_i        = 4'b1111;
    axi_master_aw_ready_i = 1'b1;
    axi_master_ar_ready_i = 1'b1;
    axi_master_w_ready_i  = 1'b0;        // <-- W stalled
    #5;

    if (per_slave_gnt_o !== 1'b0) begin
      $display("FAIL: per_slave_gnt_o=%0b with W not ready (expected 0; transaction loss bug)",
               per_slave_gnt_o);
      $fatal(1, "per2axi_req_channel granted slave with W channel not ready -- handshake bug");
    end

    // Sanity: when all three are ready, grant must assert.
    axi_master_w_ready_i = 1'b1;
    #5;
    if (per_slave_gnt_o !== 1'b1) begin
      $display("FAIL: per_slave_gnt_o=%0b with all AXI ready (expected 1)",
               per_slave_gnt_o);
      $fatal(1, "per_slave_gnt_o did not assert when all AXI channels ready");
    end

    $display("PASS: per_slave_gnt_o handshake honors all three AXI channel readies.");
    $finish;
  end

  // Watchdog
  initial begin
    #5000;
    $display("FAIL: watchdog timeout");
    $fatal(1, "watchdog");
  end

endmodule
