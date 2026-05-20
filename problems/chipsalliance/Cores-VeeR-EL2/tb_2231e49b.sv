// Focused unit test for VeeR EL2 PMPCFG WARL fix (commit 2231e49, 2024-05-23).
//
// Bug: el2_dec_pmp_ctl.sv accepted writes to PMPCFG with reserved R=0, W=1
// (RW=2'b10) combination. RISC-V spec says this encoding is reserved and
// pmpcfg fields are WARL, so writes of WR=10 must be coerced. The fix masks
// out the W bit when R is cleared (raw_wdata[0]==0).
//
// Probe: write 8'b00000010 (R=0, W=1, X=0, MODE=OFF, L=0) to pmpcfg0.write
//   Fixed RTL:  pmp_pmpcfg[0].write = 0 (W masked off)  -> PASS.
//   Buggy RTL:  pmp_pmpcfg[0].write = 1 (W accepted)    -> FAIL.

`timescale 1ns/1ps
module tb_2231e49b
  import el2_pkg::*;
#(
`include "el2_param.vh"
);

  logic clk = 0;
  logic free_l2clk;
  logic csr_wr_clk;
  logic rst_l = 0;
  logic        dec_csr_wen_r_mod = 0;
  logic [11:0] dec_csr_wraddr_r  = '0;
  logic [31:0] dec_csr_wrdata_r  = '0;
  logic [11:0] dec_csr_rdaddr_d  = '0;

  logic csr_pmpcfg   = 0;
  logic csr_pmpaddr0 = 0, csr_pmpaddr16 = 0, csr_pmpaddr32 = 0, csr_pmpaddr48 = 0;

  logic dec_pause_state          = 0;
  logic dec_tlu_pmu_fw_halted    = 0;
  logic internal_dbg_halt_timers = 0;

  logic [31:0] dec_pmp_rddata_d;
  logic        dec_pmp_read_d;

  el2_pmp_cfg_pkt_t pmp_pmpcfg  [pt.PMP_ENTRIES];
  logic [31:0]      pmp_pmpaddr [pt.PMP_ENTRIES];

  logic scan_mode = 0;

  assign free_l2clk = clk;
  assign csr_wr_clk = clk;

  always #5 clk = ~clk;

  el2_dec_pmp_ctl dut (
    .clk                        (clk),
    .free_l2clk                 (free_l2clk),
    .csr_wr_clk                 (csr_wr_clk),
    .rst_l                      (rst_l),
    .dec_csr_wen_r_mod          (dec_csr_wen_r_mod),
    .dec_csr_wraddr_r           (dec_csr_wraddr_r),
    .dec_csr_wrdata_r           (dec_csr_wrdata_r),
    .dec_csr_rdaddr_d           (dec_csr_rdaddr_d),
    .csr_pmpcfg                 (csr_pmpcfg),
    .csr_pmpaddr0               (csr_pmpaddr0),
    .csr_pmpaddr16              (csr_pmpaddr16),
    .csr_pmpaddr32              (csr_pmpaddr32),
    .csr_pmpaddr48              (csr_pmpaddr48),
    .dec_pause_state            (dec_pause_state),
    .dec_tlu_pmu_fw_halted      (dec_tlu_pmu_fw_halted),
    .internal_dbg_halt_timers   (internal_dbg_halt_timers),
    .dec_pmp_rddata_d           (dec_pmp_rddata_d),
    .dec_pmp_read_d             (dec_pmp_read_d),
    .pmp_pmpcfg                 (pmp_pmpcfg),
    .pmp_pmpaddr                (pmp_pmpaddr),
    .scan_mode                  (scan_mode)
  );

  initial begin
    // Reset
    rst_l = 0;
    @(posedge clk); @(posedge clk);
    rst_l = 1;
    @(posedge clk);

    // Drive a write to pmpcfg0 (CSR addr 0x3a0) with raw_wdata[7:0] = 8'h02
    // (R=0, W=1) in entry_idx==0 slot of dec_csr_wrdata_r.
    dec_csr_wraddr_r  = 12'h3a0;
    dec_csr_wrdata_r  = 32'h0000_0002; // entry_idx 0: R=0 W=1 X=0
    dec_csr_wen_r_mod = 1'b1;
    @(posedge clk);
    dec_csr_wen_r_mod = 1'b0;
    @(posedge clk);
    @(posedge clk);

    // Observe pmp_pmpcfg[0]
    if (pmp_pmpcfg[0].write == 1'b0) begin
      $display("PASS: pmpcfg[0].write masked to 0 when R=0 (raw_wdata=8'h02).");
      $finish;
    end else begin
      $display("FAIL: pmpcfg[0].write=%0b, full byte=%h (expected write=0).",
               pmp_pmpcfg[0].write, pmp_pmpcfg[0]);
      $fatal(1, "buggy pmp_ctl accepted reserved RW=10 combination");
    end
  end

  initial begin
    #1000;
    $display("TIMEOUT");
    $fatal(1, "timeout");
  end

endmodule
