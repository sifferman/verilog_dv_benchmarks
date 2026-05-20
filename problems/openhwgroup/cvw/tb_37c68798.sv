// Focused unit test for openhwgroup/cvw bmuctrl decoder fix (commit 37c68798).
//
// Bug summary (from commit message):
//   "Fixed decoder bug that doesn't throw illegal instruction exception for
//    RV32 immediate shifts by more than 31."
//
// RTL background: bmuctrl decodes RV32/RV64 shift instructions whose
// immediate amounts are encoded in funct7[6:0]||rs2[4:0] for the 7-bit
// funct7 + 5-bit rs2 (=12-bit shamt) field of the I-format shift. In
// RV32 the shift amount is 5 bits (rs2[4:0]) and funct7[0] (== InstrD[25])
// MUST be zero -- otherwise the encoding is illegal. The unfixed decoder
// (line ~155 of bmuctrl.sv at parent 6cee6fed) matched the slli/srli/srai
// row with the pattern `0?0000?` for funct7, so funct7[0]=1 was accepted
// (and the BMU shifter was driven), suppressing the illegal-instruction
// exception that the main controller would otherwise raise.
//
// The fix wraps the casez table with `if (P.XLEN == 64 | !Funct7D[0])`.
//
// Probe: SRLI x1, x0, 32 -- an immediate shift with shamt = 32 (>= 32),
// which is illegal in RV32. The 32-bit instruction word is:
//   funct7 = 0000001 (Funct7D[0]=1), shamt5 = 00000, rs1 = x0,
//   funct3 = 101 (SR* family), rd = x1, opcode = 0010011 (OP-IMM)
//   -> 0x02005093
//
// PASS criterion (XLEN=32 with Zbb/Zbs supported, as in rv32gc):
//   bmuctrl must report `IllegalBitmanipInstrD = 1` for this encoding.
// FAIL on the buggy RTL: it matches the shift row, drives the BMU shifter,
// and reports `IllegalBitmanipInstrD = 0`.

`timescale 1ns/1ps

`include "BranchPredictorType.vh"
`include "config.vh"

import cvw::*;

module tb_37c68798;

  // Bring in the full cvw_t struct P, populated from the rv32gc config.
  `include "parameter-defs.vh"

  logic        clk;
  logic        reset;
  logic [31:0] InstrD;
  logic        ALUOpD;
  logic        BRegWriteD;
  logic        BALUSrcBD;
  logic        BW64D;
  logic        BUW64D;
  logic        BSubArithD;
  logic        IllegalBitmanipInstrD;
  logic        StallE, FlushE;
  logic [2:0]  ALUSelectD;
  logic [3:0]  BSelectE;
  logic [3:0]  ZBBSelectE;
  logic [2:0]  BALUControlE;
  logic        BMUActiveE;

  bmuctrl #(.P(P)) dut (
    .clk(clk),
    .reset(reset),
    .InstrD(InstrD),
    .ALUOpD(ALUOpD),
    .BRegWriteD(BRegWriteD),
    .BALUSrcBD(BALUSrcBD),
    .BW64D(BW64D),
    .BUW64D(BUW64D),
    .BSubArithD(BSubArithD),
    .IllegalBitmanipInstrD(IllegalBitmanipInstrD),
    .StallE(StallE),
    .FlushE(FlushE),
    .ALUSelectD(ALUSelectD),
    .BSelectE(BSelectE),
    .ZBBSelectE(ZBBSelectE),
    .BALUControlE(BALUControlE),
    .BMUActiveE(BMUActiveE)
  );

  initial begin
    clk = 0; reset = 1; StallE = 0; FlushE = 0; ALUOpD = 1;
    InstrD = '0;
    #2 reset = 0;

    // srli x1, x0, 32 — shamt = 32 (illegal in RV32)
    InstrD = 32'h02005093;
    #2;

    if (IllegalBitmanipInstrD === 1'b1) begin
      $display("PASS: bmuctrl flagged RV32 srli shamt=32 as illegal.");
      $finish;
    end else begin
      $display("FAIL: bmuctrl did NOT flag RV32 srli shamt=32 (IllegalBitmanipInstrD=%b).",
               IllegalBitmanipInstrD);
      $fatal(1, "bmuctrl decoder accepted illegal RV32 shift shamt>=32");
    end
  end

endmodule
