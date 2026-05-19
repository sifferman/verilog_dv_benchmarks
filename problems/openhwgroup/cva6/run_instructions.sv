// Shared focused-bug testbench for cva6 problems.
//
// Mirrors the picorv32 pattern (run_instructions.sv + run_instructions.cpp):
// per-bug entries are a probe_<sha>.S, run_<sha>.sh, and <sha>.json. The
// runner converts probe.S -> probe.bin -> probe.mem (32-bit hex words, one per
// line), exports PROBE_MEM + SUCCESS_ADDR + EXPECTED_VALUE, then compiles
// this harness with the cva6 RTL.
//
// What lives here:
//   - clock + reset, watchdog
//   - cva6 (via the ariane.sv wrapper) wired to ariane_axi::req_t/resp_t
//   - axi_sim_mem (pulp-platform/axi) as a byte-addressable backing store
//   - a tiny snooper that catches the write to SUCCESS_ADDR and ebreak-style
//     completion -> DPI for pass/fail verdict
//
// `timescale 1ns/1ps
module run_instructions
  import ariane_pkg::*;
;

  // ------------------------------------------------------------------------
  // Config: use the same RV32 imac sv32 config we already use for unit-tests.
  // It has CvxifEn=0 (no coprocessor), MmuPresent=1, XLEN=32. The runner can
  // override by passing a different config_pkg via +define+ if needed.
  // ------------------------------------------------------------------------
  localparam config_pkg::cva6_cfg_t CVA6Cfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  // ------------------------------------------------------------------------
  // Clock + reset
  // ------------------------------------------------------------------------
  logic clk   = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;            // 100 MHz

  initial begin
    repeat (16) @(posedge clk);
    rst_n <= 1'b1;
  end

  // ------------------------------------------------------------------------
  // DPI bridge (oracle lives in run_instructions.cpp)
  // ------------------------------------------------------------------------
  import "DPI-C" function void dpi_init();
  import "DPI-C" function void dpi_observe_write(input longint addr,
                                                 input longint data);
  import "DPI-C" function int  dpi_poll_done();   // 0 = continue, 1 = pass, 2 = fail

  initial dpi_init();

  // ------------------------------------------------------------------------
  // CVA6 AXI master <-> memory
  // ------------------------------------------------------------------------
  ariane_axi::req_t  noc_req;
  ariane_axi::resp_t noc_resp;

  ariane #(
    .CVA6Cfg     ( CVA6Cfg              ),
    .noc_req_t   ( ariane_axi::req_t    ),
    .noc_resp_t  ( ariane_axi::resp_t   )
  ) i_dut (
    .clk_i        ( clk                 ),
    .rst_ni       ( rst_n               ),
    .boot_addr_i  ( {CVA6Cfg.VLEN{1'b0}}),
    .hart_id_i    ( {CVA6Cfg.XLEN{1'b0}}),
    .irq_i        ( 2'b00               ),
    .ipi_i        ( 1'b0                ),
    .time_irq_i   ( 1'b0                ),
    .debug_req_i  ( 1'b0                ),
    .rvfi_probes_o(                     ),
    .noc_req_o    ( noc_req             ),
    .noc_resp_i   ( noc_resp            )
  );

  // ------------------------------------------------------------------------
  // Memory: axi_sim_mem from pulp-platform/axi. ariane_axi::req_t/resp_t are
  // structurally identical to AXI_TYPEDEF_*_CHAN_T outputs, so we can pass
  // them through as the slave's req_t/rsp_t parameters.
  // ------------------------------------------------------------------------
  localparam int unsigned MemAddrWidth = ariane_axi::AddrWidth;
  localparam int unsigned MemDataWidth = ariane_axi::DataWidth;
  localparam int unsigned MemIdWidth   = ariane_axi::IdWidth;
  localparam int unsigned MemUserWidth = ariane_axi::UserWidth;

  axi_sim_mem #(
    .AddrWidth         ( MemAddrWidth          ),
    .DataWidth         ( MemDataWidth          ),
    .IdWidth           ( MemIdWidth            ),
    .UserWidth         ( MemUserWidth          ),
    .req_t             ( ariane_axi::req_t     ),
    .rsp_t             ( ariane_axi::resp_t    ),
    .WarnUninitialized ( 1'b0                  ),
    .ApplDelay         ( 0ps                   ),
    .AcqDelay          ( 0ps                   )
  ) i_mem (
    .clk_i      ( clk      ),
    .rst_ni     ( rst_n    ),
    .axi_req_i  ( noc_req  ),
    .axi_rsp_o  ( noc_resp )
  );

  // ------------------------------------------------------------------------
  // Memory initialization: load probe.mem (32-bit words, $readmemh format)
  // into the byte-addressable backing store at the reset PC.
  //
  // The .mem file is produced by the per-bug runner from probe.bin via:
  //     hexdump -v -e '"%08x\n"' probe.bin > probe.mem
  // ------------------------------------------------------------------------
  initial begin : init_mem
    automatic string memfile;
    automatic int    fd;
    automatic int    code;
    automatic int    addr;
    automatic int    word;

    if (!$value$plusargs("MEMFILE=%s", memfile)) begin
      $fatal(1, "run_instructions: +MEMFILE=<path> required");
    end
    fd = $fopen(memfile, "r");
    if (fd == 0) $fatal(1, "run_instructions: cannot open %s", memfile);

    addr = 0;
    forever begin
      code = $fscanf(fd, "%h\n", word);
      if (code != 1) break;
      // axi_sim_mem.mem is an associative array indexed by byte address; store
      // 32-bit words little-endian.
      i_mem.mem[addr + 0] = word[ 7: 0];
      i_mem.mem[addr + 1] = word[15: 8];
      i_mem.mem[addr + 2] = word[23:16];
      i_mem.mem[addr + 3] = word[31:24];
      addr += 4;
    end
    $fclose(fd);
    $display("run_instructions: loaded %0d bytes from %s", addr, memfile);
  end

  // ------------------------------------------------------------------------
  // Write snooper: catch AW+W beats to SUCCESS_ADDR and forward to DPI. AXI
  // decouples AW from W; we queue AW addrs and pop one per W-last beat.
  // (CVA6 writes are non-bursting single-beat, but the queue handles general
  // INCR bursts correctly.)
  // ------------------------------------------------------------------------
  longint aw_queue[$];
  longint w_cur_addr;
  int     w_cur_beat;

  always @(posedge clk) begin
    if (!rst_n) begin
      aw_queue.delete();
      w_cur_beat <= 0;
    end else begin
      // Accept AW
      if (noc_req.aw_valid && noc_resp.aw_ready) begin
        aw_queue.push_back(longint'(noc_req.aw.addr));
      end
      // Accept W beats, increment per-beat address (size=3 -> 8B)
      if (noc_req.w_valid && noc_resp.w_ready) begin
        automatic longint base;
        automatic longint data64;
        if (aw_queue.size() == 0) begin
          base = 0;
        end else begin
          base = aw_queue[0];
        end
        if (w_cur_beat == 0) w_cur_addr = base;
        // Compose 64-bit data from the lower bytes; strobe is ignored for the
        // oracle (writes are always 32-bit word-sized for the probe magic).
        data64 = longint'(noc_req.w.data);
        dpi_observe_write(w_cur_addr, data64);
        if (noc_req.w.last) begin
          if (aw_queue.size() > 0) void'(aw_queue.pop_front());
          w_cur_beat <= 0;
        end else begin
          w_cur_addr <= w_cur_addr + 8;  // assume 8B beats (DataWidth=64)
          w_cur_beat <= w_cur_beat + 1;
        end
      end
    end
  end

  // ------------------------------------------------------------------------
  // Completion polling: dpi_poll_done returns non-zero once the probe has
  // signalled completion (write to SUCCESS_ADDR). We poll every cycle so a
  // single-cycle write to the magic addr ends sim deterministically.
  // ------------------------------------------------------------------------
  always @(posedge clk) begin
    if (rst_n) begin
      automatic int verdict;
      verdict = dpi_poll_done();
      if (verdict == 1) begin
        $display("PASS");
        $finish;
      end else if (verdict == 2) begin
        $display("FAIL");
        $fatal(1, "buggy RTL");
      end
    end
  end

  // ------------------------------------------------------------------------
  // Watchdog
  // ------------------------------------------------------------------------
  initial begin
    int max_cycles;
    max_cycles = 200_000;
    void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
    repeat (max_cycles) @(posedge clk);
    $display("FAIL: simulation timed out after %0d cycles.", max_cycles);
    $fatal(1, "watchdog");
  end

endmodule
