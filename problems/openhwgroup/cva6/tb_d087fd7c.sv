// Focused unit test for cva6 SRET RVS=0 fix (d087fd7c).
//
// Bug: the SRET decode case at era B was wrapped in
//   if (CVA6Cfg.RVS) begin ... end
// with no else. On a core with RVS=0, the SRET encoding therefore left
// `illegal_instr` at its initial value (0) — SRET silently decoded as a
// no-op rather than raising illegal-instr.
// The fix adds an else branch that sets illegal_instr = 1 (and op = ADD
// so the priv-level isn't accidentally bumped).
//
// Probe: drive SRET (encoding 0x1020_0073) at priv_lvl_i = M on
// cv32a6_embedded (CVA6Cfg.RVS=0). cv32a6_embedded has CvxifEn=1 so we
// observe `dut.illegal_instr` directly rather than the gated ex.valid.
//   Fixed RTL: dut.illegal_instr = 1 -> PASS.
//   Buggy RTL: dut.illegal_instr = 0 (SRET silently accepted w/o S-mode) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_sret_rvs0;
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
      .is_control_flow_instr_o  (is_ctrl_flow)
  );

  initial begin
    // SRET: funct12=000100000010, rs1=0, funct3=000, rd=0, opcode=1110011
    //   = 0001_0000_0010_0000_0000_0000_0111_0011 = 0x1020_0073.
    instruction_i  = 32'h1020_0073;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (dut.illegal_instr) begin
      $display("PASS: SRET flagged illegal on RVS=0 core.");
      $finish;
    end else begin
      $display("FAIL: SRET accepted on RVS=0 core (op=%0d).",
               instruction_o.op);
      $fatal(1, "buggy decoder accepted SRET without RVS");
    end
  end
endmodule
