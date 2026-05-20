// Focused unit test for vortexgpgpu/vortex VX_onehot_encoder N=1 fix
// (commit 3075c173, 2024-08-02, "fixed bug in VX_onehot_encoder.sv (see
// issue #126)").
//
// Bug: in the N==1 branch of VX_onehot_encoder, data_out was assigned the
// value of data_in.  But data_out is an index (LN = LOG2UP(N) = 1 bit wide
// for N=1), so when the single one-hot input bit is asserted (data_in=1)
// the encoder reported index 1 instead of the correct index 0.
//
// Fixed RTL : data_out = 0      when data_in = 1  -> PASS
// Buggy RTL : data_out = data_in = 1 when data_in = 1 -> FAIL
//
// This TB instantiates the encoder with N=1 and checks the reported index
// matches the only valid index value (0) when valid_out is asserted.

`timescale 1ns/1ps
module tb_3075c173;

  logic [0:0] data_in;
  logic [0:0] data_out;
  logic       valid_out;

  VX_onehot_encoder #(
      .N      (1),
      .REVERSE(0),
      .MODEL  (1)
  ) dut (
      .data_in  (data_in),
      .data_out (data_out),
      .valid_out(valid_out)
  );

  initial begin
    data_in = 1'b1;  // the only valid one-hot input for N=1
    #1;
    if (!valid_out) begin
      $display("FAIL: valid_out not asserted when data_in=1");
      $fatal(1, "onehot encoder N=1 valid_out incorrect");
    end
    if (data_out !== 1'b0) begin
      $display("FAIL: data_out=%0b expected 0 (index of the only set bit)",
               data_out);
      $fatal(1, "onehot encoder N=1 returns wrong index");
    end
    $display("PASS: VX_onehot_encoder N=1 returns index 0 with valid=1.");
    $finish;
  end
endmodule
