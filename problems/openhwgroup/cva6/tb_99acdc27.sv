// Focused unit test for cva6 decoder ZEXT.H bug (fix 99acdc27).
//
// Bug: ZEXT.H (encoding {7'b000_0100, 3'b100}) was matched inside the
// non-Zbb (M-extension) section of the decoder, so it was decoded as a
// valid ZEXTH op even on cores built without the Zbb bitmanip extension.
// The fix moves the case into the Zbb-conditional block, so without Zbb
// the encoding correctly falls through to `illegal_instr_non_bm`.
//
// Probe: drive instruction_i = 0x0800_4033 (R-type, funct7=0000100,
// funct3=100, opcode=0x33 — i.e. the ZEXT.H encoding) on a core configured
// without Zbb (cv32a6_ima_sv32_fpga, CVA6ConfigBExtEn=0 -> BITMANIP=0).
//   Fixed RTL: instruction_o.ex.valid = 1, illegal_instr exception -> PASS.
//   Buggy RTL: instruction_o.ex.valid = 0 and op = ZEXTH -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_zexth;
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
  logic                    tvm             = 1'b0;
  logic                    tw              = 1'b0;
  logic                    tsr             = 1'b0;

  scoreboard_entry_t       instruction_o;
  logic                    is_ctrl_flow;

  decoder dut (
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
      .tvm_i                    (tvm),
      .tw_i                     (tw),
      .tsr_i                    (tsr),
      .instruction_o            (instruction_o),
      .is_control_flow_instr_o  (is_ctrl_flow)
  );

  initial begin
    // ZEXT.H encoding: funct7=0000100, rs2=00000, rs1=00000, funct3=100,
    // rd=00000, opcode=0110011 -> 0x0800_4033.
    instruction_i  = 32'h0800_4033;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (instruction_o.ex.valid) begin
      $display("PASS: ZEXT.H flagged illegal without Zbb.");
      $finish;
    end else begin
      $display("FAIL: ZEXT.H accepted as op=%0d without Zbb.",
               instruction_o.op);
      $fatal(1, "buggy decoder accepted ZEXT.H without Zbb");
    end
  end
endmodule
