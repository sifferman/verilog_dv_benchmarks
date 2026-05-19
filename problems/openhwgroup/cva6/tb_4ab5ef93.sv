// Focused unit test for cva6 decoder DRET bug (fix 4ab5ef93).
//
// Bug: the DRET decode case set
//   illegal_instr = (!debug_mode_i) ? 1'b1 : 1'b0;
// In debug mode, this hard-overwrote `illegal_instr` to 0 even when the
// upfront `rs1 != 0 || rd != 0` check had already set it to 1 for an
// invalid encoding. The fix changes the else-branch to `illegal_instr`
// (preserve the prior value).
//
// Probe: drive DRET with rd=x1 (encoding 0x7B20_00F3), debug_mode_i=1.
//   Fixed RTL: instruction_o.ex.valid = 1 (illegal due to rd != 0) -> PASS.
//   Buggy RTL: instruction_o.ex.valid = 0 (overwritten in debug mode) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_dret;
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
  logic                    debug_mode      = 1'b1;          // <-- key: debug mode active
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
    // DRET with rd=x1: imm=0x7B2, rs1=0, funct3=000, rd=00001, opcode=0x73
    instruction_i  = 32'h7B20_00F3;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (instruction_o.ex.valid) begin
      $display("PASS: DRET with rd=x1 in debug_mode flagged illegal.");
      $finish;
    end else begin
      $display("FAIL: DRET with rd=x1 accepted in debug_mode (op=%0d).",
               instruction_o.op);
      $fatal(1, "buggy decoder clobbered illegal_instr in debug mode");
    end
  end
endmodule
