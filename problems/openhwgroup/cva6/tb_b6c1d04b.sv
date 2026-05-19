// Focused unit test for cva6 decoder SFENCE.VMA / rd-field bug (fix b6c1d04b).
//
// Bug: at the start of the OpcodeSystem decode case, the parent checked
//   if (instr.itype.rs1 != '0 || instr.itype.rd != '0) illegal_instr = 1;
// which flagged SFENCE.VMA-with-rs1!=0 as illegal. Per the RISC-V Privileged
// spec, SFENCE.VMA legitimately uses rs1 as the vaddr operand (rs1 != 0 is
// the whole point of the instruction). The fix removes the upfront check
// and moves the rd != 0 check into the SFENCE.VMA case only.
//
// Probe: drive SFENCE.VMA with rs1=x1, rd=0 (encoding 0x1200_8073),
// priv_lvl = M. This is a legal SFENCE.VMA per the spec.
//   Fixed RTL: instruction_o.ex.valid = 0 (accepted as SFENCE_VMA) -> PASS.
//   Buggy RTL: instruction_o.ex.valid = 1 (rejected due to rs1 != 0) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_sfencevma;
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
    // SFENCE.VMA with rs1=x1, rd=0: funct7=0001001, rs2=0, rs1=00001,
    // funct3=000, rd=00000, opcode=1110011 -> 0x1200_8073.
    instruction_i  = 32'h1200_8073;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (!instruction_o.ex.valid && instruction_o.op == ariane_pkg::SFENCE_VMA) begin
      $display("PASS: SFENCE.VMA with rs1=x1 accepted (op=SFENCE_VMA).");
      $finish;
    end else begin
      $display("FAIL: SFENCE.VMA with rs1=x1 ex.valid=%b op=%0d.",
               instruction_o.ex.valid, instruction_o.op);
      $fatal(1, "buggy decoder rejected legal SFENCE.VMA");
    end
  end
endmodule
