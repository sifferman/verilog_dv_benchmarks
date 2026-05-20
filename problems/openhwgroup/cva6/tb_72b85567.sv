// Focused unit test for cva6 MCYCLE-while-inhibited fix (fix 72b85567).
//
// Bug: at era B (Nov-2023) the CSR_MSTATUS write path scrubbed wpri/xs/fs/vs
// but left mstatus.UBE writable. Per RISC-V the implementation may hard-wire
// UBE to its only supported value when only one endianness is supported.
// CVA6 is little-endian only, so UBE must read as 0 regardless of writes.
//
// Probe (cv32a6_imac_sv32: XLEN=32, CvxifEn=0, RVU=1):
//   1. Reset.
//   2. CSR_WRITE mstatus with bit 6 (UBE) = 1.
//   3. CSR_READ mstatus -> check bit 6 == 0.
//      Fixed RTL: rdata[6] = 0  -> PASS.
//      Buggy RTL: rdata[6] = 1  -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_csr_mcycle_inhibit;
  localparam config_pkg::cva6_cfg_t TBCfg = cva6_config_pkg::cva6_cfg;

  import ariane_pkg::*;

  logic                              clk            = 1'b0;
  logic                              rst_n          = 1'b0;
  logic                              time_irq       = 1'b0;
  logic                              flush_o;
  logic                              halt_csr_o;
  scoreboard_entry_t [TBCfg.NrCommitPorts-1:0] commit_instr;
  logic [TBCfg.NrCommitPorts-1:0]    commit_ack     = '0;
  logic [riscv::VLEN-1:0]            boot_addr      = '0;
  logic [riscv::XLEN-1:0]            hart_id        = '0;
  exception_t                        ex_in;
  fu_op                              csr_op_in;
  logic [11:0]                       csr_addr_in;
  logic [riscv::XLEN-1:0]            csr_wdata_in;
  logic [riscv::XLEN-1:0]            csr_rdata_o;
  logic                              dirty_fp_state = 1'b0;
  logic                              csr_write_fflags = 1'b0;
  logic                              dirty_v_state  = 1'b0;
  logic [riscv::VLEN-1:0]            pc             = '0;
  exception_t                        csr_exception_o;
  logic [riscv::VLEN-1:0]            epc_o;
  logic                              eret_o;
  logic [riscv::VLEN-1:0]            trap_vector_base_o;
  riscv::priv_lvl_t                  priv_lvl_o;
  logic [4:0]                        acc_fflags_ex = '0;
  logic                              acc_fflags_ex_valid = 1'b0;
  riscv::xs_t                        fs_o;
  logic [4:0]                        fflags_o;
  logic [2:0]                        frm_o;
  logic [6:0]                        fprec_o;
  riscv::xs_t                        vs_o;
  irq_ctrl_t                         irq_ctrl_o;
  logic                              en_translation_o;
  logic                              en_ld_st_translation_o;
  riscv::priv_lvl_t                  ld_st_priv_lvl_o;
  logic                              sum_o;
  logic                              mxr_o;
  logic [riscv::PPNW-1:0]            satp_ppn_o;
  logic [1-1:0]       asid_o;
  logic [1:0]                        irq_in         = 2'b00;
  logic                              ipi            = 1'b0;
  logic                              debug_req      = 1'b0;
  logic                              set_debug_pc_o;
  logic                              tvm_o;
  logic                              tw_o;
  logic                              tsr_o;
  logic                              debug_mode_o;
  logic                              single_step_o;
  logic                              icache_en_o;
  logic                              dcache_en_o;
  logic                              acc_cons_en_o;
  logic [11:0]                       perf_addr_o;
  logic [riscv::XLEN-1:0]            perf_data_o;
  logic [riscv::XLEN-1:0]            perf_data_in   = '0;
  logic                              perf_we_o;
  riscv::pmpcfg_t [15:0]             pmpcfg_o;
  logic [15:0][riscv::PLEN-3:0]      pmpaddr_o;
  logic [31:0]                       mcountinhibit_o;

  always #5 clk = ~clk;

  csr_regfile #(
      .CVA6Cfg        (TBCfg),
      .AsidWidth      (1),
      .MHPMCounterNum (ariane_pkg::MHPMCounterNum)
  ) dut (
      .clk_i(clk), .rst_ni(rst_n), .time_irq_i(time_irq),
      .flush_o(flush_o), .halt_csr_o(halt_csr_o),
      .commit_instr_i(commit_instr), .commit_ack_i(commit_ack),
      .boot_addr_i(boot_addr), .hart_id_i(hart_id),
      .ex_i(ex_in),
      .csr_op_i(csr_op_in), .csr_addr_i(csr_addr_in),
      .csr_wdata_i(csr_wdata_in), .csr_rdata_o(csr_rdata_o),
      .dirty_fp_state_i(dirty_fp_state),
      .csr_write_fflags_i(csr_write_fflags),
      .dirty_v_state_i(dirty_v_state), .pc_i(pc),
      .csr_exception_o(csr_exception_o),
      .epc_o(epc_o), .eret_o(eret_o),
      .trap_vector_base_o(trap_vector_base_o),
      .priv_lvl_o(priv_lvl_o),
      .acc_fflags_ex_i(acc_fflags_ex),
      .acc_fflags_ex_valid_i(acc_fflags_ex_valid),
      .fs_o(fs_o), .fflags_o(fflags_o), .frm_o(frm_o),
      .fprec_o(fprec_o), .vs_o(vs_o),
      .irq_ctrl_o(irq_ctrl_o),
      .en_translation_o(en_translation_o),
      .en_ld_st_translation_o(en_ld_st_translation_o),
      .ld_st_priv_lvl_o(ld_st_priv_lvl_o),
      .sum_o(sum_o), .mxr_o(mxr_o),
      .satp_ppn_o(satp_ppn_o), .asid_o(asid_o),
      .irq_i(irq_in), .ipi_i(ipi), .debug_req_i(debug_req),
      .set_debug_pc_o(set_debug_pc_o),
      .tvm_o(tvm_o), .tw_o(tw_o), .tsr_o(tsr_o),
      .debug_mode_o(debug_mode_o), .single_step_o(single_step_o),
      .icache_en_o(icache_en_o), .dcache_en_o(dcache_en_o),
      .acc_cons_en_o(acc_cons_en_o),
      .perf_addr_o(perf_addr_o), .perf_data_o(perf_data_o),
      .perf_data_i(perf_data_in), .perf_we_o(perf_we_o),
      .pmpcfg_o(pmpcfg_o), .pmpaddr_o(pmpaddr_o),
      .mcountinhibit_o(mcountinhibit_o)
  );

  initial begin
    commit_instr = '{default: '0};
    ex_in        = '0;
    csr_op_in    = ariane_pkg::ADD;
    csr_addr_in  = 12'h000;
    csr_wdata_in = '0;

    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // 1. Enable cycle inhibit: write MCOUNTINHIBIT bit 0 = 1.
    csr_op_in    = ariane_pkg::CSR_WRITE;
    csr_addr_in  = 12'h320;       // MCOUNTINHIBIT
    csr_wdata_in = 32'h0000_0001; // bit 0 = inhibit cycle
    @(posedge clk);

    // 2. Write MCYCLE to a known sentinel value.
    csr_op_in    = ariane_pkg::CSR_WRITE;
    csr_addr_in  = 12'hB00;       // MCYCLE
    csr_wdata_in = 32'hDEAD_BEEF;
    @(posedge clk);

    // 3. Let one cycle elapse with inhibit asserted and no commits.
    csr_op_in    = ariane_pkg::ADD;
    csr_addr_in  = 12'h000;
    csr_wdata_in = '0;
    @(posedge clk);
    @(posedge clk);

    // 4. Read MCYCLE back. Per spec, with cycle inhibited the counter must
    //    hold its value. Buggy RTL assigns cycle_d = instret (= 0 here).
    csr_op_in    = ariane_pkg::CSR_READ;
    csr_addr_in  = 12'hB00;
    @(posedge clk);

    if (csr_rdata_o == 32'hDEAD_BEEF) begin
      $display("PASS: MCYCLE retained 0x%h while inhibited.", csr_rdata_o);
      $finish;
    end else begin
      $display("FAIL: MCYCLE = 0x%h (expected 0xDEADBEEF, buggy clobber to instret).",
               csr_rdata_o);
      $fatal(1, "buggy csr_regfile clobbered MCYCLE with instret when inhibited");
    end
  end

  initial begin
    repeat (400) @(posedge clk);
    $fatal(1, "watchdog");
  end
endmodule
