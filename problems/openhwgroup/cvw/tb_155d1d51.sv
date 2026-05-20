// Focused unit test for openhwgroup/cvw privdec sinval.vma funct7 fix
// (commit 155d1d51).
//
// Bug summary (commit msg): "Fixed funct7 code for sinval.vma (issue #1154)".
//
// The RISC-V Svinval extension defines:
//   sinval.vma  rs1, rs2   -- funct7 = 7'b0001011, funct3 = 000, opcode = SYSTEM (0x73)
// Wally's privdec.sv had `sinvalvmaM = (InstrM[31:25] == 7'b0001001)`, which is
// the encoding of the *non*-svinval sfence.vma instruction. The fix changes
// the literal to 7'b0001011 so the correct svinval encoding is recognized.
//
// Observable effect: when sinval.vma is decoded as a privileged instruction
// in M-mode and Svinval is supported in the config (rv64gc has
// SVINVAL_SUPPORTED = 1), `sfencevmaM` must assert. In the buggy RTL
// sinvalvmaM stays 0, invalM stays 0, and (since InstrM[31:25]=0001011
// also fails the inline 0001001 check in the sfencevmaM assignment)
// sfencevmaM stays 0.
//
// Probe: sinval.vma x0, x0 -- funct7 = 0001011, rs2 = x0, rs1 = x0,
//   funct3 = 000, rd = x0, opcode = 1110011 (SYSTEM)
//   bits[31:25]=0001011, bits[24:20]=00000, bits[19:15]=00000,
//   bits[14:12]=000, bits[11:7]=00000, bits[6:0]=1110011
//   = 32'h16000073
//
// PASS criterion: sfencevmaM == 1'b1 with PrivilegedM=1, PrivilegeModeW=M_MODE.

`timescale 1ns/1ps

`include "BranchPredictorType.vh"
`include "config.vh"

import cvw::*;

module tb_155d1d51;

  `include "parameter-defs.vh"

  logic        clk;
  logic        reset;
  logic        StallW, FlushW;
  logic [31:15] InstrM;
  logic        PrivilegedM;
  logic        IllegalIEUFPUInstrM;
  logic        IllegalCSRAccessM;
  logic [1:0]  PrivilegeModeW;
  logic        STATUS_TSR, STATUS_TVM, STATUS_TW;
  logic        IllegalInstrFaultM;
  logic        EcallFaultM, BreakpointFaultM;
  logic        sretM, mretM, RetM;
  logic        wfiM, wfiW, sfencevmaM;

  privdec #(.P(P)) dut (
    .clk(clk),
    .reset(reset),
    .StallW(StallW),
    .FlushW(FlushW),
    .InstrM(InstrM),
    .PrivilegedM(PrivilegedM),
    .IllegalIEUFPUInstrM(IllegalIEUFPUInstrM),
    .IllegalCSRAccessM(IllegalCSRAccessM),
    .PrivilegeModeW(PrivilegeModeW),
    .STATUS_TSR(STATUS_TSR),
    .STATUS_TVM(STATUS_TVM),
    .STATUS_TW(STATUS_TW),
    .IllegalInstrFaultM(IllegalInstrFaultM),
    .EcallFaultM(EcallFaultM),
    .BreakpointFaultM(BreakpointFaultM),
    .sretM(sretM),
    .mretM(mretM),
    .RetM(RetM),
    .wfiM(wfiM),
    .wfiW(wfiW),
    .sfencevmaM(sfencevmaM)
  );

  initial begin
    clk = 0; reset = 1;
    StallW = 0; FlushW = 0;
    IllegalIEUFPUInstrM = 0; IllegalCSRAccessM = 0;
    STATUS_TSR = 0; STATUS_TVM = 0; STATUS_TW = 0;
    PrivilegedM = 1;
    PrivilegeModeW = 2'b11; // M-mode
    InstrM = '0;
    #2 reset = 0;

    // sinval.vma x0, x0 -- bits[31:15] = funct7(7) | rs2(5) | rs1(5) = 17 bits
    InstrM = 17'b0001011_00000_00000;
    #2;

    if (sfencevmaM === 1'b1) begin
      $display("PASS: privdec decoded sinval.vma (funct7=0001011) -> sfencevmaM=1.");
      $finish;
    end else begin
      $display("FAIL: privdec did NOT decode sinval.vma; sfencevmaM=%b.", sfencevmaM);
      $fatal(1, "privdec used wrong funct7 for sinval.vma");
    end
  end

endmodule
