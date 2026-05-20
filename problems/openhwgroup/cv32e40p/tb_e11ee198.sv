// Focused unit test for cv32e40p decoder SIMD imm6 illegal-instruction fix
// (commit e11ee19, 2024-04-18).
//
// Bug: PULP SIMD opcode space (cv.srl/cv.sra/cv.sll/cv.shuffle etc.) under
// OPCODE_CUSTOM_2 has Imm6 fields with reserved-zero bits that were not
// checked. The fix adds the `instr_rdata_i[14:12]==3'b110 && [24:23]!='0`
// (and analogous funct3=3'b111 + [24:22]!='0) checks so reserved-bit
// non-zero encodings raise `illegal_insn_o`.
//
// Probe: cv.srl with funct6=6'b010000, funct3=3'b110, [25]=0, [24:23]=2'b01
// (non-zero -> illegal), rs1=0, rd=0, opcode=OPCODE_CUSTOM_3(0x7B).
// -> instruction encoding 0x4080607B.
//   Fixed RTL:  illegal_insn_o = 1 -> PASS.
//   Buggy RTL:  illegal_insn_o = 0 -> FAIL.

`timescale 1ns/1ps
module tb_cv32e40p_decoder_simd_imm6;

  import cv32e40p_pkg::*;
  import cv32e40p_apu_core_pkg::*;
  import cv32e40p_fpu_pkg::*;

  // Inputs (drive)
  logic            deassert_we = 1'b0;
  logic [31:0]     instr_rdata;
  logic            illegal_c_insn = 1'b0;
  logic            fs_off = 1'b0;
  logic [C_RM-1:0] frm = '0;
  PrivLvl_t        current_priv_lvl = PRIV_LVL_M;
  logic            debug_mode = 1'b0;
  logic            debug_wfi_no_sleep = 1'b0;
  logic [31:0]     mcounteren = '0;

  // Outputs (let Verilator drive these from inside the DUT)
  logic            illegal_insn;
  logic            ebrk_insn;
  logic            mret_insn, uret_insn, dret_insn;
  logic            mret_dec, uret_dec, dret_dec;
  logic            ecall_insn, wfi;
  logic            fencei_insn;
  logic            rega_used, regb_used, regc_used;
  logic            reg_fp_a, reg_fp_b, reg_fp_c, reg_fp_d;
  logic [0:0]      bmask_a_mux;
  logic [1:0]      bmask_b_mux;
  logic            alu_bmask_a_mux_sel, alu_bmask_b_mux_sel;
  logic            alu_en;
  alu_opcode_e     alu_operator;
  logic [2:0]      alu_op_a_mux_sel, alu_op_b_mux_sel;
  logic [1:0]      alu_op_c_mux_sel;
  logic            alu_vec;
  logic [1:0]      alu_vec_mode;
  logic            scalar_replication, scalar_replication_c;
  logic [0:0]      imm_a_mux_sel;
  logic [3:0]      imm_b_mux_sel;
  logic [1:0]      regc_mux;
  logic            is_clpx, is_subrot;
  mul_opcode_e     mult_operator;
  logic            mult_int_en, mult_dot_en;
  logic [0:0]      mult_imm_mux;
  logic            mult_sel_subword;
  logic [1:0]      mult_signed_mode, mult_dot_signed;
  logic [cv32e40p_fpu_pkg::FP_FORMAT_BITS-1:0]  fpu_dst_fmt, fpu_src_fmt;
  logic [cv32e40p_fpu_pkg::INT_FORMAT_BITS-1:0] fpu_int_fmt;
  logic            apu_en;
  logic [5:0]      apu_op;       // APU_WOP_CPU=6
  logic [1:0]      apu_lat;
  logic [2:0]      fp_rnd_mode;
  logic            regfile_mem_we, regfile_alu_we, regfile_alu_we_dec;
  logic            regfile_alu_waddr_sel;
  logic            csr_access, csr_status;
  csr_opcode_e     csr_op;
  logic            data_req, data_we, prepost_useincr;
  logic [1:0]      data_type, data_sign_extension, data_reg_offset;
  logic            data_load_event;
  logic [5:0]      atop;
  logic [2:0]      hwlp_we;
  logic [1:0]      hwlp_target_mux_sel, hwlp_start_mux_sel;
  logic            hwlp_cnt_mux_sel;
  logic [1:0]      ctrl_transfer_insn_in_dec, ctrl_transfer_insn_in_id;
  logic [1:0]      ctrl_transfer_target_mux_sel;

  cv32e40p_decoder #(
      .COREV_PULP       (1),
      .COREV_CLUSTER    (0),
      .A_EXTENSION      (0),
      .FPU              (0),
      .FPU_ADDMUL_LAT   (0),
      .FPU_OTHERS_LAT   (0),
      .ZFINX            (0),
      .PULP_SECURE      (0),
      .USE_PMP          (0),
      .APU_WOP_CPU      (6),
      .DEBUG_TRIGGER_EN (1)
  ) dut (
      .deassert_we_i             (deassert_we),
      .illegal_insn_o            (illegal_insn),
      .ebrk_insn_o               (ebrk_insn),
      .mret_insn_o               (mret_insn),
      .uret_insn_o               (uret_insn),
      .dret_insn_o               (dret_insn),
      .mret_dec_o                (mret_dec),
      .uret_dec_o                (uret_dec),
      .dret_dec_o                (dret_dec),
      .ecall_insn_o              (ecall_insn),
      .wfi_o                     (wfi),
      .fencei_insn_o             (fencei_insn),
      .rega_used_o               (rega_used),
      .regb_used_o               (regb_used),
      .regc_used_o               (regc_used),
      .reg_fp_a_o                (reg_fp_a),
      .reg_fp_b_o                (reg_fp_b),
      .reg_fp_c_o                (reg_fp_c),
      .reg_fp_d_o                (reg_fp_d),
      .bmask_a_mux_o             (bmask_a_mux),
      .bmask_b_mux_o             (bmask_b_mux),
      .alu_bmask_a_mux_sel_o     (alu_bmask_a_mux_sel),
      .alu_bmask_b_mux_sel_o     (alu_bmask_b_mux_sel),
      .instr_rdata_i             (instr_rdata),
      .illegal_c_insn_i          (illegal_c_insn),
      .alu_en_o                  (alu_en),
      .alu_operator_o            (alu_operator),
      .alu_op_a_mux_sel_o        (alu_op_a_mux_sel),
      .alu_op_b_mux_sel_o        (alu_op_b_mux_sel),
      .alu_op_c_mux_sel_o        (alu_op_c_mux_sel),
      .alu_vec_o                 (alu_vec),
      .alu_vec_mode_o            (alu_vec_mode),
      .scalar_replication_o      (scalar_replication),
      .scalar_replication_c_o    (scalar_replication_c),
      .imm_a_mux_sel_o           (imm_a_mux_sel),
      .imm_b_mux_sel_o           (imm_b_mux_sel),
      .regc_mux_o                (regc_mux),
      .is_clpx_o                 (is_clpx),
      .is_subrot_o               (is_subrot),
      .mult_operator_o           (mult_operator),
      .mult_int_en_o             (mult_int_en),
      .mult_dot_en_o             (mult_dot_en),
      .mult_imm_mux_o            (mult_imm_mux),
      .mult_sel_subword_o        (mult_sel_subword),
      .mult_signed_mode_o        (mult_signed_mode),
      .mult_dot_signed_o         (mult_dot_signed),
      .fs_off_i                  (fs_off),
      .frm_i                     (frm),
      .fpu_dst_fmt_o             (fpu_dst_fmt),
      .fpu_src_fmt_o             (fpu_src_fmt),
      .fpu_int_fmt_o             (fpu_int_fmt),
      .apu_en_o                  (apu_en),
      .apu_op_o                  (apu_op),
      .apu_lat_o                 (apu_lat),
      .fp_rnd_mode_o             (fp_rnd_mode),
      .regfile_mem_we_o          (regfile_mem_we),
      .regfile_alu_we_o          (regfile_alu_we),
      .regfile_alu_we_dec_o      (regfile_alu_we_dec),
      .regfile_alu_waddr_sel_o   (regfile_alu_waddr_sel),
      .csr_access_o              (csr_access),
      .csr_status_o              (csr_status),
      .csr_op_o                  (csr_op),
      .current_priv_lvl_i        (current_priv_lvl),
      .data_req_o                (data_req),
      .data_we_o                 (data_we),
      .prepost_useincr_o         (prepost_useincr),
      .data_type_o               (data_type),
      .data_sign_extension_o     (data_sign_extension),
      .data_reg_offset_o         (data_reg_offset),
      .data_load_event_o         (data_load_event),
      .atop_o                    (atop),
      .hwlp_we_o                 (hwlp_we),
      .hwlp_target_mux_sel_o     (hwlp_target_mux_sel),
      .hwlp_start_mux_sel_o      (hwlp_start_mux_sel),
      .hwlp_cnt_mux_sel_o        (hwlp_cnt_mux_sel),
      .debug_mode_i              (debug_mode),
      .debug_wfi_no_sleep_i      (debug_wfi_no_sleep),
      .ctrl_transfer_insn_in_dec_o     (ctrl_transfer_insn_in_dec),
      .ctrl_transfer_insn_in_id_o      (ctrl_transfer_insn_in_id),
      .ctrl_transfer_target_mux_sel_o  (ctrl_transfer_target_mux_sel),
      .mcounteren_i              (mcounteren)
  );

  initial begin
    // cv.srl: funct6=010000_0, [24:23]=01 (non-zero reserved bits),
    // funct3=110, opcode=OPCODE_CUSTOM_3 (7'h7b)
    instr_rdata = 32'h4080_607B;
    #1;
    if (illegal_insn) begin
      $display("PASS: cv.srl with reserved imm6 bits flagged illegal.");
      $finish;
    end else begin
      $display("FAIL: cv.srl with [24:23]=01 accepted (illegal_insn=%0b).",
               illegal_insn);
      $fatal(1, "buggy decoder skipped imm6 reserved-bit check");
    end
  end
endmodule
