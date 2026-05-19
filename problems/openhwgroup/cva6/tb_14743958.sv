// Focused unit test for cva6 SFENCE.VMA RVS=0 fix (14743958).
//
// Bug: at era B the SFENCE.VMA decode case computed
//   illegal_instr = (((RVS && S) || ((!RVS && !RVU) || M)) && rd==0) ? 0 : 1
// which incorrectly accepted SFENCE.VMA in M-mode on cores with RVS=0
// (S-mode not supported). The fix simplifies the check to
//   illegal_instr = (RVS && (M||S) && rd==0) ? 0 : 1
// so SFENCE.VMA is always illegal when RVS=0.
//
// Probe: drive SFENCE.VMA rd=0 (encoding 0x1200_0073) with priv_lvl_i=M
// on cv32a6_embedded (CVA6Cfg.RVS=0). cv32a6_embedded has CvxifEn=1 so we
// observe the decoder's internal `illegal_instr` signal directly via a
// cross-module reference rather than the gated `instruction_o.ex.valid`.
//   Fixed RTL: dut.illegal_instr = 1 -> PASS.
//   Buggy RTL: dut.illegal_instr = 0 (accepted in M-mode w/o RVS) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_sfencevma_rvs0;
  import ariane_pkg::*;

  logic                    debug_req       = 1'b0;
  logic [riscv::VLEN-1:0]  pc              = '0;
  logic                    is_compressed   = 1'b0;
  logic [15:0]             compressed_instr = '0;
  logic                    is_illegal      = 1'b0;
  logic [31:0]             instruction_i;
  branchpredict_sbe_t      branch_predict;
  exception_t              ex_in;
  logic [1:0]              irq_i           = '0;
  irq_ctrl_t               irq_ctrl;
  riscv::priv_lvl_t        priv_lvl        = riscv::PRIV_LVL_M;
  logic                    debug_mode      = 1'b0;
  riscv::xs_t              fs              = riscv::Off;
  logic [2:0]              frm             = 3'b000;
  riscv::xs_t              vs              = riscv::Off;
  logic                    tvm             = 1'b0;
  logic                    tw              = 1'b0;
  logic                    tsr             = 1'b0;

  scoreboard_entry_t       instruction_o;
  logic [31:0]             orig_instr_o;
  logic                    is_ctrl_flow;

  decoder #(
      .CVA6Cfg (cva6_config_pkg::cva6_cfg)
  ) dut (
      .debug_req_i              (debug_req),
      .pc_i                     (pc),
      .is_compressed_i          (is_compressed),
      .compressed_instr_i       (compressed_instr),
      .is_illegal_i             (is_illegal),
      .instruction_i            (instruction_i),
      .branch_predict_i         (branch_predict),
      .ex_i                     (ex_in),
      .irq_i                    (irq_i),
      .irq_ctrl_i               (irq_ctrl),
      .priv_lvl_i               (priv_lvl),
      .debug_mode_i             (debug_mode),
      .fs_i                     (fs),
      .frm_i                    (frm),
      .vs_i                     (vs),
      .tvm_i                    (tvm),
      .tw_i                     (tw),
      .tsr_i                    (tsr),
      .instruction_o            (instruction_o),
      .orig_instr_o             (orig_instr_o),
      .is_control_flow_instr_o  (is_ctrl_flow)
  );

  initial begin
    instruction_i  = 32'h1200_0073;  // SFENCE.VMA rd=0
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (dut.illegal_instr) begin
      $display("PASS: SFENCE.VMA flagged illegal on RVS=0 core (illegal_instr=%b).",
               dut.illegal_instr);
      $finish;
    end else begin
      $display("FAIL: SFENCE.VMA accepted in M-mode without S-mode (illegal_instr=%b op=%0d).",
               dut.illegal_instr, instruction_o.op);
      $fatal(1, "buggy decoder accepted SFENCE.VMA without RVS");
    end
  end
endmodule
