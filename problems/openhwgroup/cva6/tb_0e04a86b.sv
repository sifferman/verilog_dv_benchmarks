// Focused unit test for cva6 branch_unit tval reporting (fix 0e04a86b).
//
// Bug: on a misaligned-jump exception, branch_unit reported `tval = pc_i`
// (the PC of the jumping instruction). Per RISC-V spec, tval for an
// instruction-address-misaligned exception must be the *target* address.
// The fix replaces pc_i with target_address in the tval assignment.
//
// Probe: instantiate branch_unit with cv32a6_ima_sv32_fpga (RVC=0). Drive
// an unconditional JALR with operand_a=0, imm=0x6 so target_address = 0x6
// (misaligned: [1:0] = 2'b10). Source pc_i = 0.
//   Fixed RTL: branch_exception_o.valid = 1 AND tval == 6 -> PASS.
//   Buggy RTL: branch_exception_o.valid = 1 AND tval == 0 -> FAIL.
//
// Era 2026: branch_unit takes parametric types. We declare the struct
// types locally here (mirroring core/cva6.sv's localparam type decls) so
// the unit-test build doesn't pull in the entire cva6 surroundings.
//
// `timescale 1ns/1ps
module tb_cva6_branch_tval
  import ariane_pkg::*;
;
  // ----- Config ----------------------------------------------------------------
  localparam config_pkg::cva6_cfg_t TBCfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  // ----- Parametric struct types (copies from core/cva6.sv) -------------------
  typedef struct packed {
    cf_t                     cf;
    logic [TBCfg.VLEN-1:0]   predict_address;
  } branchpredict_sbe_t;

  typedef struct packed {
    logic [TBCfg.XLEN-1:0]   cause;
    logic [TBCfg.XLEN-1:0]   tval;
    logic [TBCfg.GPLEN-1:0]  tval2;
    logic [31:0]             tinst;
    logic                    gva;
    logic                    valid;
  } exception_t;

  typedef struct packed {
    logic                                valid;
    logic [TBCfg.VLEN-1:0]               pc;
    logic [TBCfg.VLEN-1:0]               target_address;
    logic                                is_mispredict;
    logic                                is_taken;
    cf_t                                 cf_type;
  } bp_resolve_t;

  typedef struct packed {
    fu_t                                 fu;
    fu_op                                operation;
    logic [TBCfg.XLEN-1:0]               operand_a;
    logic [TBCfg.XLEN-1:0]               operand_b;
    logic [TBCfg.XLEN-1:0]               imm;
    logic [TBCfg.TRANS_ID_BITS-1:0]      trans_id;
  } fu_data_t;

  // ----- Signals --------------------------------------------------------------
  logic                        clk            = 1'b0;
  logic                        rst_n          = 1'b1;
  logic                        v_mode         = 1'b0;
  logic                        debug_mode     = 1'b0;
  fu_data_t                    fu_data;
  logic [TBCfg.VLEN-1:0]       pc             = '0;
  logic                        is_zcmt        = 1'b0;
  logic                        is_compressed  = 1'b0;
  logic                        branch_valid   = 1'b1;
  logic                        branch_comp    = 1'b0;
  branchpredict_sbe_t          branch_predict;
  logic [TBCfg.VLEN-1:0]       branch_result;
  bp_resolve_t                 resolved_branch;
  logic                        resolve_branch;
  exception_t                  branch_exception;

  branch_unit #(
      .CVA6Cfg              (TBCfg),
      .bp_resolve_t         (bp_resolve_t),
      .branchpredict_sbe_t  (branchpredict_sbe_t),
      .exception_t          (exception_t),
      .fu_data_t            (fu_data_t)
  ) dut (
      .clk_i                  (clk),
      .rst_ni                 (rst_n),
      .v_i                    (v_mode),
      .debug_mode_i           (debug_mode),
      .fu_data_i              (fu_data),
      .pc_i                   (pc),
      .is_zcmt_i              (is_zcmt),
      .is_compressed_instr_i  (is_compressed),
      .branch_valid_i         (branch_valid),
      .branch_comp_res_i      (branch_comp),
      .branch_result_o        (branch_result),
      .branch_predict_i       (branch_predict),
      .resolved_branch_o      (resolved_branch),
      .resolve_branch_o       (resolve_branch),
      .branch_exception_o     (branch_exception)
  );

  initial begin
    fu_data            = '0;
    fu_data.operation  = ariane_pkg::JALR;
    fu_data.operand_a  = '0;
    fu_data.imm        = 'd6;     // target = 6 (misaligned w/o RVC)
    branch_predict     = '0;
    #1;

    if (!branch_exception.valid) begin
      $display("FAIL: misaligned-jump exception not raised.");
      $fatal(1, "no exception");
    end

    if (branch_exception.tval == 'd6) begin
      $display("PASS: tval == 0x6 (target address).");
      $finish;
    end else begin
      $display("FAIL: tval = 0x%0h, expected 0x6.", branch_exception.tval);
      $fatal(1, "buggy branch_unit reported wrong tval");
    end
  end
endmodule
