// Focused unit test for cva6 decoder FENCE fix (0b4ff9e4).
//
// Bug: the System opcode decode had an upfront blanket check
//   if (instr.stype.rs1 != '0 || instr.stype.imm0 != '0 || instr.instr[31:28] != '0)
//       illegal_instr = 1'b1;
// that rejected any FENCE/FENCE.I with non-zero rs1, rd, or fm. Per the
// RISC-V spec, implementations must IGNORE the values of fm/pred/succ/rs1/rd
// for FENCE and treat all such fields as zero — never raise illegal.
// The fix removes the upfront check.
//
// Probe: drive a FENCE with rs1=x1, rd=0, pred=0, succ=0, fm=0
// (encoding 0x0000_800F).
//   Fixed RTL: instruction_o.ex.valid = 0, op = FENCE -> PASS.
//   Buggy RTL: instruction_o.ex.valid = 1 (rejected due to rs1 != 0) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_fence;
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
    // FENCE rd=0, rs1=x1, pred=0, succ=0, fm=0:
    // bits[31:28]=0000 fm, [27:24]=0000 pred, [23:20]=0000 succ,
    // [19:15]=00001 rs1, [14:12]=000 funct3, [11:7]=00000 rd,
    // [6:0]=0001111 opcode -> 0x0000_800F.
    // Per spec this must be legal even with non-zero rs1.
    instruction_i  = 32'h0000_800F;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (!instruction_o.ex.valid && instruction_o.op == ariane_pkg::FENCE) begin
      $display("PASS: FENCE rs1=x1 accepted (op=FENCE).");
      $finish;
    end else begin
      $display("FAIL: FENCE rs1=x1 ex.valid=%b op=%0d.",
               instruction_o.ex.valid, instruction_o.op);
      $fatal(1, "buggy decoder rejected legal FENCE");
    end
  end
endmodule
