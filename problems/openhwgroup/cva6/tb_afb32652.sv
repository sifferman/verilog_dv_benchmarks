// Focused unit test for cva6 MCOUNTEREN read must raise exception on RVU=0 (fix afb32652).
//
// Bug: at era C the csr_regfile sanitises mstatus writes by clearing the
// fields that aren't supported by the current config. When CVA6Cfg.RVU=0
// it cleared `mstatus.mprv` but forgot `mstatus.tw`. Per spec, mstatus.tw
// is WARL and must be 0 when U-mode is not implemented.
//
// Probe: cv32a6_embedded has CVA6Cfg.RVU = 0 (and CvxifEn=1, but tw_o is
// a top-level module output so CvxifEn doesn't gate it). Reset, then drive
// csr_op_i = CSR_WRITE with mstatus address and bit 21 (tw) set.
//   Fixed RTL: dut.tw_o = 0 after one clock (the scrubbing fix kicks in).
//   Buggy RTL: dut.tw_o = 1 (write retained because tw scrub missing).
//
// `timescale 1ns/1ps
module tb_cva6_csr_mcounteren_rvu0;
  localparam config_pkg::cva6_cfg_t TBCfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  import ariane_pkg::*;
  `include "cva6_eraC_decoder_types.svh"
  `include "cva6_eraC_csr_types.svh"

  logic                              clk            = 1'b0;
  logic                              rst_n          = 1'b0;
  logic                              time_irq       = 1'b0;
  logic                              flush_o;
  logic                              halt_csr_o;
  scoreboard_entry_t [TBCfg.NrCommitPorts-1:0] commit_instr;
  logic [TBCfg.NrCommitPorts-1:0]    commit_ack     = '0;
  logic [TBCfg.VLEN-1:0]             boot_addr      = '0;
  logic [TBCfg.XLEN-1:0]             hart_id        = '0;
  exception_t                        ex_in;
  fu_op                              csr_op_in;
  logic [11:0]                       csr_addr_in;
  logic [TBCfg.XLEN-1:0]             csr_wdata_in;
  logic [TBCfg.XLEN-1:0]             csr_rdata_o;
  logic                              dirty_fp_state = 1'b0;
  logic                              csr_write_fflags = 1'b0;
  logic                              dirty_v_state  = 1'b0;
  logic [TBCfg.VLEN-1:0]             pc             = '0;
  exception_t                        csr_exception_o;
  logic [TBCfg.VLEN-1:0]             epc_o;
  logic                              eret_o;
  logic [TBCfg.VLEN-1:0]             trap_vector_base_o;
  riscv::priv_lvl_t                  priv_lvl_o;
  logic                              v_o;
  logic [4:0]                        acc_fflags_ex = '0;
  logic                              acc_fflags_ex_valid = 1'b0;
  riscv::xs_t                        fs_o;
  riscv::xs_t                        vfs_o;
  logic [4:0]                        fflags_o;
  logic [2:0]                        frm_o;
  logic [6:0]                        fprec_o;
  riscv::xs_t                        vs_o;
  irq_ctrl_t                         irq_ctrl_o;
  logic                              en_translation_o;
  logic                              en_g_translation_o;
  logic                              en_ld_st_translation_o;
  logic                              en_ld_st_g_translation_o;
  riscv::priv_lvl_t                  ld_st_priv_lvl_o;
  logic                              ld_st_v_o;
  logic                              csr_hs_ld_st_inst = 1'b0;
  logic                              sum_o;
  logic                              vs_sum_o;
  logic                              mxr_o;
  logic                              vmxr_o;
  logic [TBCfg.PPNW-1:0]             satp_ppn_o;
  logic [TBCfg.ASID_WIDTH-1:0]       asid_o;
  logic [TBCfg.PPNW-1:0]             vsatp_ppn_o;
  logic [TBCfg.ASID_WIDTH-1:0]       vs_asid_o;
  logic [TBCfg.PPNW-1:0]             hgatp_ppn_o;
  logic [TBCfg.VMID_WIDTH-1:0]       vmid_o;
  logic [1:0]                        irq_in         = 2'b00;
  logic                              ipi            = 1'b0;
  logic                              debug_req      = 1'b0;
  logic                              set_debug_pc_o;
  logic                              tvm_o;
  logic                              tw_o;
  logic                              vtw_o;
  logic                              tsr_o;
  logic                              hu_o;
  logic                              debug_mode_o;
  logic                              single_step_o;
  logic                              icache_en_o;
  logic                              dcache_en_o;
  logic                              acc_cons_en_o;
  logic [11:0]                       perf_addr_o;
  logic [TBCfg.XLEN-1:0]             perf_data_o;
  logic [TBCfg.XLEN-1:0]             perf_data_in   = '0;
  logic                              perf_we_o;
  riscv::pmpcfg_t [15:0]             pmpcfg_o;
  logic [15:0][TBCfg.PLEN-3:0]       pmpaddr_o;
  logic [31:0]                       mcountinhibit_o;
  rvfi_probes_csr_t                  rvfi_csr_o;

  always #5 clk = ~clk;

  csr_regfile #(
      .CVA6Cfg            (TBCfg),
      .exception_t        (exception_t),
      .irq_ctrl_t         (irq_ctrl_t),
      .scoreboard_entry_t (scoreboard_entry_t),
      .rvfi_probes_csr_t  (rvfi_probes_csr_t),
      .MHPMCounterNum     (ariane_pkg::MHPMCounterNum)
  ) dut (
      .clk_i                    (clk),
      .rst_ni                   (rst_n),
      .time_irq_i               (time_irq),
      .flush_o                  (flush_o),
      .halt_csr_o               (halt_csr_o),
      .commit_instr_i           (commit_instr),
      .commit_ack_i             (commit_ack),
      .boot_addr_i              (boot_addr),
      .hart_id_i                (hart_id),
      .ex_i                     (ex_in),
      .csr_op_i                 (csr_op_in),
      .csr_addr_i               (csr_addr_in),
      .csr_wdata_i              (csr_wdata_in),
      .csr_rdata_o              (csr_rdata_o),
      .dirty_fp_state_i         (dirty_fp_state),
      .csr_write_fflags_i       (csr_write_fflags),
      .dirty_v_state_i          (dirty_v_state),
      .pc_i                     (pc),
      .csr_exception_o          (csr_exception_o),
      .epc_o                    (epc_o),
      .eret_o                   (eret_o),
      .trap_vector_base_o       (trap_vector_base_o),
      .priv_lvl_o               (priv_lvl_o),
      .v_o                      (v_o),
      .acc_fflags_ex_i          (acc_fflags_ex),
      .acc_fflags_ex_valid_i    (acc_fflags_ex_valid),
      .fs_o                     (fs_o),
      .vfs_o                    (vfs_o),
      .fflags_o                 (fflags_o),
      .frm_o                    (frm_o),
      .fprec_o                  (fprec_o),
      .vs_o                     (vs_o),
      .irq_ctrl_o               (irq_ctrl_o),
      .en_translation_o         (en_translation_o),
      .en_g_translation_o       (en_g_translation_o),
      .en_ld_st_translation_o   (en_ld_st_translation_o),
      .en_ld_st_g_translation_o (en_ld_st_g_translation_o),
      .ld_st_priv_lvl_o         (ld_st_priv_lvl_o),
      .ld_st_v_o                (ld_st_v_o),
      .csr_hs_ld_st_inst_i      (csr_hs_ld_st_inst),
      .sum_o                    (sum_o),
      .vs_sum_o                 (vs_sum_o),
      .mxr_o                    (mxr_o),
      .vmxr_o                   (vmxr_o),
      .satp_ppn_o               (satp_ppn_o),
      .asid_o                   (asid_o),
      .vsatp_ppn_o              (vsatp_ppn_o),
      .vs_asid_o                (vs_asid_o),
      .hgatp_ppn_o              (hgatp_ppn_o),
      .vmid_o                   (vmid_o),
      .irq_i                    (irq_in),
      .ipi_i                    (ipi),
      .debug_req_i              (debug_req),
      .set_debug_pc_o           (set_debug_pc_o),
      .tvm_o                    (tvm_o),
      .tw_o                     (tw_o),
      .vtw_o                    (vtw_o),
      .tsr_o                    (tsr_o),
      .hu_o                     (hu_o),
      .debug_mode_o             (debug_mode_o),
      .single_step_o            (single_step_o),
      .icache_en_o              (icache_en_o),
      .dcache_en_o              (dcache_en_o),
      .acc_cons_en_o            (acc_cons_en_o),
      .perf_addr_o              (perf_addr_o),
      .perf_data_o              (perf_data_o),
      .perf_data_i              (perf_data_in),
      .perf_we_o                (perf_we_o),
      .pmpcfg_o                 (pmpcfg_o),
      .pmpaddr_o                (pmpaddr_o),
      .mcountinhibit_o          (mcountinhibit_o),
      .rvfi_csr_o               (rvfi_csr_o)
  );

  initial begin
    commit_instr     = '{default: '0};
    ex_in            = '0;
    csr_op_in        = ariane_pkg::ADD;
    csr_addr_in      = 12'h300;
    csr_wdata_in     = '0;

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // Read MCOUNTEREN (CSR 0x306). Per spec, mcounteren only exists when
    // U-mode is implemented; on a core with RVU=0 reading it must raise an
    // illegal-instruction access exception. Buggy RTL returns mcounteren_q
    // (=0) with no exception.
    csr_op_in    = ariane_pkg::CSR_READ;
    csr_addr_in  = 12'h306;
    csr_wdata_in = '0;
    @(posedge clk);

    if (csr_exception_o.valid) begin
      $display("PASS: MCOUNTEREN read raised exception on RVU=0 core (cause=0x%h).",
               csr_exception_o.cause);
      $finish;
    end else begin
      $display("FAIL: MCOUNTEREN read accepted on RVU=0 core (rdata=0x%h).",
               csr_rdata_o);
      $fatal(1, "buggy csr_regfile accepted MCOUNTEREN read without U-mode");
    end
  end

  initial begin
    repeat (200) @(posedge clk);
    $fatal(1, "watchdog");
  end
endmodule
