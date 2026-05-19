// Focused unit test for cva6 branch_unit not-taken misalign fix (283177c2).
//
// Bug: branch_unit raised inst-addr-misaligned for ANY branch with
// target_address[0]!=0, even on conditional branches that are NOT taken.
// Per the spec the exception is observed only on a taken branch / jump.
// The fix adds a `jump_taken` guard combining the unconditional-jump and
// taken-conditional-branch cases.
//
// Probe: drive a BEQ-like branch (op=EQ) with pc=0, imm=1, so target=1
// (bit 0 set, misaligned), branch_valid=1, branch_comp_res=0 (NOT taken).
// Era B branch_unit (CVA6Cfg, no parametric types).
//   Fixed RTL: branch_exception.valid = 0 (no spurious exception) -> PASS.
//   Buggy RTL: branch_exception.valid = 1 (false positive on not-taken) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_branch_not_taken_misalign;
  import ariane_pkg::*;

  logic                        clk            = 1'b0;
  logic                        rst_n          = 1'b1;
  logic                        debug_mode     = 1'b0;
  fu_data_t                    fu_data;
  logic [riscv::VLEN-1:0]      pc             = '0;
  logic                        is_compressed  = 1'b0;
  logic                        fu_valid       = 1'b1;
  logic                        branch_valid   = 1'b1;
  logic                        branch_comp    = 1'b0;  // <-- NOT taken
  branchpredict_sbe_t          branch_predict;
  logic [riscv::VLEN-1:0]      branch_result;
  bp_resolve_t                 resolved_branch;
  logic                        resolve_branch;
  exception_t                  branch_exception;

  branch_unit #(
      .CVA6Cfg(cva6_config_pkg::cva6_cfg)
  ) dut (
      .clk_i                  (clk),
      .rst_ni                 (rst_n),
      .debug_mode_i           (debug_mode),
      .fu_data_i              (fu_data),
      .pc_i                   (pc),
      .is_compressed_instr_i  (is_compressed),
      .fu_valid_i             (fu_valid),
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
    fu_data.operation  = ariane_pkg::EQ;  // conditional branch
    fu_data.operand_a  = '0;
    fu_data.imm        = 'd1;  // target = 0 + 1 = 1 (bit 0 set)
    branch_predict     = '0;
    #1;

    if (!branch_exception.valid) begin
      $display("PASS: not-taken misaligned branch did NOT raise exception.");
      $finish;
    end else begin
      $display("FAIL: not-taken branch raised spurious inst-addr-misaligned.");
      $fatal(1, "buggy branch_unit fires exception on not-taken conditional");
    end
  end
endmodule
