// Focused unit test for cva6 DRET DebugEn=0 fix (3fcb7b9c).
//
// Bug: the DRET decode case unconditionally executed
//   illegal_instr = (!debug_mode_i) ? 1'b1 : illegal_instr;
// On a core with CVA6Cfg.DebugEn=0, DRET should always be illegal, but
// when debug_mode_i happened to be high the buggy code preserved the
// prior (default 0) value of illegal_instr -- DRET silently accepted.
// The fix wraps the check in `if (CVA6Cfg.DebugEn) ... else illegal=1`.
//
// Probe: drive DRET (encoding 0x7B20_0073) with debug_mode_i = 1 on
// cv32a6_embedded (CVA6Cfg.DebugEn=0). cv32a6_embedded has CvxifEn=1 so
// we observe `dut.illegal_instr` directly.
//   Fixed RTL: dut.illegal_instr = 1 -> PASS.
//   Buggy RTL: dut.illegal_instr = 0 -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_decoder_dret_debugen0;
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
  logic                    debug_mode      = 1'b1;  // <-- key: in debug mode
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
    // DRET: funct12=011110110010, rs1=0, funct3=000, rd=0, opcode=1110011
    //   = 0x7B20_0073.
    instruction_i  = 32'h7B20_0073;
    branch_predict = '0;
    ex_in          = '0;
    irq_ctrl       = '0;
    #1;

    if (dut.illegal_instr) begin
      $display("PASS: DRET flagged illegal on DebugEn=0 core.");
      $finish;
    end else begin
      $display("FAIL: DRET accepted on DebugEn=0 core (op=%0d).",
               instruction_o.op);
      $fatal(1, "buggy decoder accepted DRET without DebugEn");
    end
  end
endmodule
