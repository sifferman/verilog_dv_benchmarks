// Focused unit test for cva6 HFENCE.VVMA rd-check fix (ff1d7998).
//
// Bug: at era C the HFENCE.VVMA / HFENCE.GVMA decode cases set
//   illegal_instr = (priv_lvl_i in {M, S}) ? 1'b0 : 1'b1;
// with no check on the `rd` field. Per the Hypervisor spec rd must be 0
// or the encoding is illegal. The fix ANDs in `instr.itype.rd == '0`.
//
// Probe: drive HFENCE.VVMA with rd=x1 (funct7=0010001, rs2=0, rs1=0,
// funct3=000, rd=00001, opcode=1110011 -> 0x2200_00F3) at priv_lvl_i=M
// on cv64a6_imafdch_sv39 (RV64, RVH=1, CvxifEn=1). TB peeks
// `dut.illegal_instr` so CvxifEn=1 doesn't mask the decoder's verdict.
//   Fixed RTL: dut.illegal_instr = 1 -> PASS.
//   Buggy RTL: dut.illegal_instr = 0 (accepted with rd != 0) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_hfence_rd;
  localparam config_pkg::cva6_cfg_t TBCfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  import ariane_pkg::*;
  `include "cva6_eraC_decoder_types.svh"

  logic                        debug_req       = 1'b0;
  logic [TBCfg.VLEN-1:0]       pc              = '0;
  logic                        is_compressed   = 1'b0;
  logic [15:0]                 compressed_instr = '0;
  logic                        is_macro_instr  = 1'b0;
  logic                        is_last_macro_instr = 1'b0;
  logic                        is_double_rd_macro_instr = 1'b0;
  logic                        is_illegal      = 1'b0;
  logic [31:0]                 instruction_i;
  branchpredict_sbe_t          branch_predict;
  exception_t                  ex_in;
  logic [1:0]                  irq_i           = '0;
  irq_ctrl_t                   irq_ctrl;
  riscv::priv_lvl_t            priv_lvl        = riscv::PRIV_LVL_M;
  logic                        v_mode          = 1'b0;  // <-- key: not in V-mode
  logic                        debug_mode      = 1'b0;
  riscv::xs_t                  fs              = riscv::Off;
  riscv::xs_t                  vfs             = riscv::Off;
  logic [2:0]                  frm             = 3'b000;
  riscv::xs_t                  vs              = riscv::Off;
  logic                        tvm             = 1'b0;
  logic                        tw              = 1'b0;
  logic                        vtw             = 1'b0;
  logic                        tsr             = 1'b0;
  logic                        hu              = 1'b0;

  scoreboard_entry_t           instruction_o;
  logic [31:0]                 orig_instr_o;
  logic                        is_ctrl_flow;

  decoder #(
      .CVA6Cfg              (TBCfg),
      .branchpredict_sbe_t  (branchpredict_sbe_t),
      .exception_t          (exception_t),
      .irq_ctrl_t           (irq_ctrl_t),
      .scoreboard_entry_t   (scoreboard_entry_t),
      .interrupts_t         (interrupts_t),
      .INTERRUPTS           (INTERRUPTS)
  ) dut (
      .debug_req_i               (debug_req),
      .pc_i                      (pc),
      .is_compressed_i           (is_compressed),
      .compressed_instr_i        (compressed_instr),
      .is_macro_instr_i          (is_macro_instr),
      .is_last_macro_instr_i     (is_last_macro_instr),
      .is_double_rd_macro_instr_i(is_double_rd_macro_instr),
      .is_illegal_i              (is_illegal),
      .instruction_i             (instruction_i),
      .branch_predict_i          (branch_predict),
      .ex_i                      (ex_in),
      .irq_i                     (irq_i),
      .irq_ctrl_i                (irq_ctrl),
      .priv_lvl_i                (priv_lvl),
      .v_i                       (v_mode),
      .debug_mode_i              (debug_mode),
      .fs_i                      (fs),
      .vfs_i                     (vfs),
      .frm_i                     (frm),
      .vs_i                      (vs),
      .tvm_i                     (tvm),
      .tw_i                      (tw),
      .vtw_i                     (vtw),
      .tsr_i                     (tsr),
      .hu_i                      (hu),
      .instruction_o             (instruction_o),
      .orig_instr_o              (orig_instr_o),
      .is_control_flow_instr_o   (is_ctrl_flow)
  );

  initial begin
    instruction_i  = 32'h2200_00F3;  // HFENCE.VVMA rd=x1
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (dut.illegal_instr) begin
      $display("PASS: HFENCE.VVMA with rd=x1 flagged illegal.");
      $finish;
    end else begin
      $display("FAIL: HFENCE.VVMA with rd=x1 accepted (op=%0d).",
               instruction_o.op);
      $fatal(1, "buggy decoder accepted HFENCE.VVMA with rd != 0");
    end
  end
endmodule
