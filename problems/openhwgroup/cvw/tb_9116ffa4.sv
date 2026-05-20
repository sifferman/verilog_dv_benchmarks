// Focused unit test for openhwgroup/cvw bmuctrl rv32 w-type-shift fix (9116ffa4).
//
// Bug summary (commit msg): "Fixed Issue #1147 that w-type shifts do not
// throw illegal instruction trap in RV32GC".
//
// w-type shifts (sllw/sraw/srlw, slliw/sraiw/srliw -- opcodes 0111011 and
// 0011011 with funct3 = 001 or 101) are defined only in RV64. In RV32 they
// are illegal. Before this commit, bmuctrl matched these opcodes with the
// rv32i/64i shift casez table regardless of XLEN; the previous fix
// (37c68798) only guarded the immediate-shift-amount overflow, not the
// w-type opcodes themselves. Result: in RV32GC, slliw was accepted by the
// BMU decoder (IllegalBitmanipInstrD=0) so the controller never raised an
// illegal-instruction exception.
//
// The fix rewrites the shift-decode block to split per-row and guard each
// w-type row with `if (P.XLEN == 64)`.
//
// Probe: slliw x1, x0, 1 -- a w-type immediate shift, illegal in RV32.
//   opcode = 0011011 (OP-IMM-32), funct3 = 001, rd = x1, rs1 = x0,
//   shamt = 5'b00001, funct7 = 7'b0000000 -> 0x0010109B.
//
// PASS criterion (XLEN=32, Zbb supported, as in rv32gc):
//   IllegalBitmanipInstrD must be 1.

`timescale 1ns/1ps

`include "BranchPredictorType.vh"
`include "config.vh"

import cvw::*;

module tb_9116ffa4;

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

    // slliw x1, x0, 1 — RV64-only opcode, must trap in RV32.
    InstrD = 32'h0010109B;
    #2;

    if (IllegalBitmanipInstrD === 1'b1) begin
      $display("PASS: bmuctrl flagged slliw as illegal in RV32.");
      $finish;
    end else begin
      $display("FAIL: bmuctrl did NOT flag slliw in RV32 (IllegalBitmanipInstrD=%b).",
               IllegalBitmanipInstrD);
      $fatal(1, "bmuctrl accepted w-type shift in RV32");
    end
  end

endmodule
