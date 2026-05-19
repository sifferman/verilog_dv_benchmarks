// Shared focused-bug testbench for picorv32 problems.
//
// Each per-bug entry in this directory consists of a probe_<sha>.S (RISC-V
// assembly), a run_<sha>.sh (per-bug runner), and the <sha>.json instance
// spec. The runner assembles the probe to a raw little-endian binary, sets
// env vars (PROBE_BIN, EXPECTED_VALUE), then verilator-compiles this TB
// together with the picorv32 RTL and run_instructions.cpp.
//
// Memory + oracle live in C++ (run_instructions.cpp) and are accessed via
// DPI. SystemVerilog handles only clock, reset, bus wiring, watchdog, and
// the picorv32 instantiation.
//
// DUT parameter knobs are gated by `ifdef defines so each per-bug runner
// can opt into a non-default config (e.g. PARAM_RV32E for the RV32E shift
// bug) without recompiling the whole RTL.
//
// `timescale 1ns/1ps
module run_instructions;
    reg clk = 0;
    reg resetn = 0;
    wire trap;

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        resetn <= 1;
    end

    // ---- DPI imports -------------------------------------------------------
    import "DPI-C" function void dpi_init();
    import "DPI-C" function int  dpi_read_word(input int addr);
    import "DPI-C" function void dpi_observe_write(input int addr,
                                                   input int data,
                                                   input int wstrb);
    import "DPI-C" function int  dpi_on_trap();   // 0 = PASS, non-0 = FAIL

    initial dpi_init();

    // ---- bus signals -------------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [ 3:0] mem_wstrb;
    reg  [31:0] mem_rdata;

    // 1-cycle ready memory model; reads served from DPI, writes observed.
    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready <= 1'b0;
            mem_rdata <= 32'h0;
        end else begin
            mem_ready <= mem_valid && !mem_ready;
            if (mem_valid && !mem_ready) begin
                if (|mem_wstrb) begin
                    dpi_observe_write(mem_addr, mem_wdata, {{28{1'b0}}, mem_wstrb});
                end
                mem_rdata <= dpi_read_word(mem_addr);
            end
        end
    end

    // ---- trap handler ------------------------------------------------------
    always @(posedge clk) begin
        if (resetn && trap) begin
            if (dpi_on_trap() == 0) begin
                $display("PASS");
                $finish;
            end else begin
                $display("FAIL");
                $fatal(1, "buggy RTL");
            end
        end
    end

    // ---- watchdog ----------------------------------------------------------
    initial begin
        repeat (10_000) @(posedge clk);
        $display("FAIL: simulation timed out without trap.");
        $fatal(1, "watchdog");
    end

    // ---- DUT parameter knobs (set by per-bug runner via +define+) ----------
`ifdef PARAM_RV32E
    localparam bit ENABLE_REGS_16_31 = 1'b0;
`else
    localparam bit ENABLE_REGS_16_31 = 1'b1;
`endif

`ifdef PARAM_ENABLE_DIV
    localparam bit ENABLE_DIV = 1'b1;
    localparam bit ENABLE_PCPI = 1'b1;
`else
    localparam bit ENABLE_DIV = 1'b0;
    localparam bit ENABLE_PCPI = 1'b0;
`endif

`ifdef PARAM_COMPRESSED
    localparam bit COMPRESSED_ISA = 1'b1;
`else
    localparam bit COMPRESSED_ISA = 1'b0;
`endif

`ifdef PARAM_ENABLE_FAST_MUL
    localparam bit ENABLE_FAST_MUL = 1'b1;
`else
    localparam bit ENABLE_FAST_MUL = 1'b0;
`endif

    // Only pass parameter overrides that exist on every picorv32 snapshot
    // we mine against. ENABLE_DIV, for instance, was introduced in 2016-04
    // (00dd6ac); earlier commits don't declare that parameter, so passing
    // it would fail elaboration. Each PARAM_* runner flag opts-in to the
    // override only when the per-bug runner asks for it.
    picorv32 #(
        .ENABLE_REGS_16_31 (ENABLE_REGS_16_31),
`ifdef PARAM_ENABLE_DIV
        .ENABLE_DIV        (ENABLE_DIV),
`endif
`ifdef PARAM_ENABLE_FAST_MUL
        .ENABLE_FAST_MUL   (ENABLE_FAST_MUL),
`endif
        .COMPRESSED_ISA    (COMPRESSED_ISA)
    ) dut (
        .clk         (clk),
        .resetn      (resetn),
        .trap        (trap),
        .mem_valid   (mem_valid),
        .mem_instr   (mem_instr),
        .mem_ready   (mem_ready),
        .mem_addr    (mem_addr),
        .mem_wdata   (mem_wdata),
        .mem_wstrb   (mem_wstrb),
        .mem_rdata   (mem_rdata),
        .mem_la_read (), .mem_la_write(), .mem_la_addr (),
        .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid  (), .pcpi_insn   (), .pcpi_rs1    (), .pcpi_rs2 (),
        .pcpi_wr (1'b0), .pcpi_rd (32'h0), .pcpi_wait (1'b0), .pcpi_ready (1'b0),
        .irq         (32'h0), .eoi ()
        // trace_valid/trace_data were added in 2016-08; we leave them
        // disconnected here so the same TB works against older picorv32.v
        // snapshots that don't expose those ports.
    );
endmodule
