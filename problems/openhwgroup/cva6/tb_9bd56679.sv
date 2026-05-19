// Focused unit test for cva6 ZEXT.H rs2-check fix (9bd56679).
//
// Bug: at era C the BITMANIP RV32 ZEXT.H decode case
//   {7'b000_0100, 3'b100} : instruction_o.op = ariane_pkg::ZEXTH;
// accepted ANY rs2 field, but per Zbb spec ZEXT.H is the alias
//   pack rd, rs1, x0
// so rs2 MUST be 0. The fix adds `if (!IS_XLEN64 && rs2 == 0) ZEXTH else
// illegal_instr_bm = 1` so rs2 != 0 is correctly flagged.
//
// Probe: drive a "ZEXT.H" with rs2=x1, rs1=0, rd=0 (encoding 0x0810_4033)
// on cv32a65x (RV32, RVB=1; the only RV32 config with RVB=1 in this era).
// cv32a65x has CvxifEn=1 so we observe `dut.illegal_instr` directly.
//   Fixed RTL: dut.illegal_instr = 1 -> PASS.
//   Buggy RTL: dut.illegal_instr = 0, op = ZEXTH -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_zexth_rs2;
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
  logic                        v_mode          = 1'b0;
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
    // ZEXT.H encoding with rs2=x1: funct7=0000100, rs2=00001, rs1=00000,
    // funct3=100, rd=00000, opcode=0110011 -> 0x0810_4033.
    instruction_i  = 32'h0810_4033;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (dut.illegal_instr) begin
      $display("PASS: ZEXT.H with rs2=x1 flagged illegal.");
      $finish;
    end else begin
      $display("FAIL: ZEXT.H with rs2=x1 accepted (op=%0d).",
               instruction_o.op);
      $fatal(1, "buggy decoder accepted ZEXT.H with non-zero rs2");
    end
  end
endmodule
