// Focused unit test for cva6 decoder SFENCE.VMA bug (fix 01c89b76).
//
// Bug: the SFENCE.VMA decode case set
//   illegal_instr = (priv_lvl_i in {M, S}) ? 1'b0 : 1'b1;
// In M/S mode this hard-overwrote `illegal_instr` to 0, clobbering the
// upfront `rs1!=0 || rd!=0` check. So an SFENCE.VMA with rd=x1 (reserved
// per spec) was silently accepted in M/S mode. The fix changes the
// else-branch to `illegal_instr` (preserve the prior set-by-upfront
// value).
//
// Note: this is the *first* sfence.vma decoder fix (commit 01c89b76,
// 2022-07-08). A second pass (commit b6c1d04b, 2022-07-20) later moved
// the rd-check into the case itself and removed the upfront rs1 check —
// see tb_b6c1d04b.sv for that one.
//
// Probe: SFENCE.VMA with rd=x1, priv_lvl=M (encoding 0x1200_00F3).
//   Fixed RTL: instruction_o.ex.valid = 1 -> PASS.
//   Buggy RTL: instruction_o.ex.valid = 0 (clobbered to 0 in M mode) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_sfencevma_rd;
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
    // SFENCE.VMA rd=x1, rs1=0: funct7=0001001, rs2=0, rs1=0, funct3=000,
    // rd=00001, opcode=1110011 -> 0x1200_00F3.
    instruction_i  = 32'h1200_00F3;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (instruction_o.ex.valid) begin
      $display("PASS: SFENCE.VMA rd=x1 flagged illegal in M mode.");
      $finish;
    end else begin
      $display("FAIL: SFENCE.VMA rd=x1 accepted in M mode (op=%0d).",
               instruction_o.op);
      $fatal(1, "buggy decoder clobbered illegal_instr in M/S mode");
    end
  end
endmodule
