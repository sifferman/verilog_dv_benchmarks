// Focused unit test for cva6 RV32 BCLRI bit-25 fix (664c515b).
//
// Bug: in RV32, the BCLRI/BINVI/BSETI/BEXTI/RORI decoders matched
//   instr[31:26] == 6'b010010 (a 6-bit funct check), which silently
//   accepts encodings with bit 25 set. Per Zbb spec the RV32 form has
//   funct7 = 0100100 (a 7-bit field where bit 25 must be 0); only the
//   RV64 form uses 6-bit funct6 because bit 25 is part of shamt[5].
// The fix splits the check: RV64 keeps the 6-bit comparison, RV32 uses
//   instr[31:25] == 7'b0100100 (bit 25 must be 0).
//
// Probe: drive BCLRI shamt=0, rs1=0, rd=0, BUT with bit 25 = 1
// (encoding 0x4A00_1013) on cv32a6_imac_sv32 (RV32, RVB=1, CvxifEn=0).
//   Fixed RTL: bit 25 != 0 -> illegal -> instruction_o.ex.valid = 1 -> PASS.
//   Buggy RTL: matches the 6-bit pattern -> decoded as BCLRI, ex.valid=0 -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_bclri_bit25;
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
    // BCLRI shamt=0, rs1=0, rd=0, but bit 25 = 1:
    // [31:25]=0100101, [24:20]=00000, [19:15]=00000, [14:12]=001,
    // [11:7]=00000, [6:0]=0010011 -> 0x4A00_1013.
    instruction_i  = 32'h4A00_1013;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (instruction_o.ex.valid) begin
      $display("PASS: BCLRI with bit 25=1 flagged illegal in RV32.");
      $finish;
    end else begin
      $display("FAIL: BCLRI with bit 25=1 accepted in RV32 (op=%0d).",
               instruction_o.op);
      $fatal(1, "buggy decoder accepted BCLRI with reserved bit 25 set");
    end
  end
endmodule
