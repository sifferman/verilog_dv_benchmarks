// Focused unit test for cva6 compressed_decoder c.ld/c.sd FP fix (6d263a60).
//
// Bug: pre-fix, the compressed_decoder unconditionally expanded
//   c.ld -> LD (riscv::OpcodeLoad)
//   c.sd -> SD (riscv::OpcodeStore)
// even when XLEN=32, where LD/SD do not exist. Per the spec, in RV32 the
// {15:13}=100 quadrant-0 encodings repurpose as c.flw/c.fsw under RVF.
// The fix branches on `riscv::XLEN == 64`: RV64 keeps c.ld/c.sd, RV32
// expands to c.flw/c.fsw.
//
// Probe: drive c.ld rd'=x8, rs1'=x8, uimm=0 (encoding 0x0000_6000) on a
// RV32+RVF build (cv32a6_imafc_sv32). Check the decompressed opcode.
//   Fixed RTL: instr_o[6:0] == OpcodeLoadFp (FLW) -> PASS.
//   Buggy RTL: instr_o[6:0] == OpcodeLoad (LD; illegal in RV32) -> FAIL.
//
// `timescale 1ns/1ps
module tb_cva6_csd_fp;
  logic [31:0] instr_i;
  logic [31:0] instr_o;
  logic        illegal;
  logic        is_compressed;

  compressed_decoder dut (
      .instr_i        (instr_i),
      .instr_o        (instr_o),
      .illegal_instr_o(illegal),
      .is_compressed_o(is_compressed)
  );

  initial begin
    // c.ld with rd'=x8, rs1'=x8, uimm=0:
    // {3'b100, 3'b000, 3'b000, 2'b00, 3'b000, 2'b00} -> 0x6000
    instr_i = 32'h0000_6000;
    #1;

    if (illegal) begin
      $display("FAIL: compressed_decoder flagged c.ld illegal (unexpected).");
      $fatal(1, "decoder flagged illegal");
    end

    // OpcodeLoadFp is 7'b000_0111 = 0x07; OpcodeLoad is 7'b000_0011 = 0x03.
    if (instr_o[6:0] == 7'b000_0111) begin
      $display("PASS: c.ld decompressed to FLW (opcode=0x%02h) in RV32.",
               instr_o[6:0]);
      $finish;
    end else if (instr_o[6:0] == 7'b000_0011) begin
      $display("FAIL: c.ld decompressed to LD (opcode=0x03) in RV32 (RV64-only).");
      $fatal(1, "buggy decoder emitted RV64-only LD for c.ld in RV32");
    end else begin
      $display("FAIL: c.ld decompressed to unexpected opcode 0x%02h.",
               instr_o[6:0]);
      $fatal(1, "unknown decompression");
    end
  end
endmodule
