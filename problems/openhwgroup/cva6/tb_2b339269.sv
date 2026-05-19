// Focused unit test for cva6 misaligned-branch fix (2b339269).
//
// Bug: with RVC disabled, branch_unit only flagged inst-addr-misaligned for
// target_address[0]==1, missing the case where target_address[1:0]==2'b10
// (2-byte aligned but not 4-byte aligned). The fix adds
// `|| (!CVA6Cfg.RVC && target_address[1])` to the exception condition.
//
// Probe: drive a JALR with operand_a=0, imm=6 so target=6 (binary 110,
// bit[1]=1). Use cv32a6_ima_sv32_fpga (RVC=0). With RVC off, a target
// landing at offset 6 is misaligned and must raise an exception.
//   Fixed RTL: branch_exception_o.valid = 1 -> PASS.
//   Buggy RTL: branch_exception_o.valid = 0 -> FAIL.
//
// Era B (pre-2024): cva6_config_pkg::cva6_cfg IS already a cva6_cfg_t,
// no build_config_pkg shim needed.
//
// `timescale 1ns/1ps
module tb_cva6_branch_misaligned;
  import ariane_pkg::*;

  logic                        clk            = 1'b0;
  logic                        rst_n          = 1'b1;
  logic                        debug_mode     = 1'b0;
  fu_data_t                    fu_data;
  logic [riscv::VLEN-1:0]      pc             = '0;
  logic                        is_compressed  = 1'b0;
  logic                        fu_valid       = 1'b1;
  logic                        branch_valid   = 1'b1;
  logic                        branch_comp    = 1'b0;
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
    fu_data.operation  = ariane_pkg::JALR;
    fu_data.operand_a  = '0;
    fu_data.imm        = 'd6;     // target = 0 + 6 = 0x6 (misaligned w/o RVC)
    branch_predict     = '0;
    #1;

    if (branch_exception.valid) begin
      $display("PASS: misaligned JALR target=0x6 raised inst-addr-misaligned.");
      $finish;
    end else begin
      $display("FAIL: misaligned JALR target=0x6 missed (exception.valid=0).");
      $fatal(1, "buggy branch_unit accepted misaligned target without RVC");
    end
  end
endmodule
