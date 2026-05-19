// Focused unit test for cva6 compressed_decoder c.sh bit-6 check (fix e6867b8f).
// Combinational only — no clock needed. Drives the c.sh encoding with bit 6 = 1
// and checks that illegal_instr_o is asserted.

module tb_cva6_csh;
  logic [31:0] instr;
  logic [31:0] instr_o;
  logic illegal;
  logic is_macro, is_compressed, is_zcmt;

  // c.sh with bit 6 = 1 (illegal per spec):
  // [15:13]=100 (OpcodeC0Zcb), [12:10]=011 (sh), [9:7]=000 (rs1'),
  // [6]=1 (BUG TRIGGER), [5]=0, [4:2]=000 (rs2'), [1:0]=00
  // = 0b10001100_01000000 = 0x8C40
  assign instr = 32'h0000_8C40;

  // Use cv32a60x config: RVZCB=1
  localparam config_pkg::cva6_cfg_t TBCfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  compressed_decoder #(.CVA6Cfg(TBCfg)) dut (
    .instr_i(instr),
    .instr_o(instr_o),
    .illegal_instr_o(illegal),
    .is_macro_instr_o(is_macro),
    .is_compressed_o(is_compressed),
    .is_zcmt_instr_o(is_zcmt)
  );

  initial begin
    #1;
    if (illegal) begin
      $display("PASS: c.sh with bit[6]=1 flagged illegal as expected.");
      $finish;
    end else begin
      $display("FAIL: c.sh with bit[6]=1 was accepted as legal (instr_o=0x%h).", instr_o);
      $fatal(1, "buggy compressed_decoder");
    end
  end
endmodule
