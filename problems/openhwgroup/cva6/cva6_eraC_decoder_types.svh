// Shared parametric type declarations for cva6 era-C decoder unit tests.
//
// Era-C cva6 (2024-06+) factored its core types out of ariane_pkg and into
// localparam types inside core/cva6.sv. The decoder module accepts these
// types as `parameter type ...` and uses them in its scoreboard_entry_t
// output. Each focused unit-test would otherwise repeat ~80 lines of type
// plumbing; this header centralises them.
//
// Usage (include INSIDE a module's `decoder #(...)` scope, after defining
// `TBCfg` to the build_config_pkg::build_config(...) result):
//
//   `include "cva6_eraC_decoder_types.svh"
//   decoder #(
//       .CVA6Cfg              (TBCfg),
//       .branchpredict_sbe_t  (branchpredict_sbe_t),
//       .exception_t          (exception_t),
//       .irq_ctrl_t           (irq_ctrl_t),
//       .scoreboard_entry_t   (scoreboard_entry_t),
//       .interrupts_t         (interrupts_t),
//       .INTERRUPTS           (INTERRUPTS)
//   ) dut (...);
//
// Field layouts mirror core/cva6.sv at master (b3bee0ca). They are stable
// across the era-C window (≥ 21733e55) — if a future commit reshapes
// scoreboard_entry_t, this header will need to track that change.

`ifndef CVA6_ERAC_DECODER_TYPES_SVH
`define CVA6_ERAC_DECODER_TYPES_SVH

  typedef struct packed {
    ariane_pkg::cf_t          cf;
    logic [TBCfg.VLEN-1:0]    predict_address;
  } branchpredict_sbe_t;

  typedef struct packed {
    logic [TBCfg.XLEN-1:0]    cause;
    logic [TBCfg.XLEN-1:0]    tval;
    logic [TBCfg.GPLEN-1:0]   tval2;
    logic [31:0]              tinst;
    logic                     gva;
    logic                     valid;
  } exception_t;

  typedef struct packed {
    logic [TBCfg.XLEN-1:0]    mie;
    logic [TBCfg.XLEN-1:0]    mip;
    logic [TBCfg.XLEN-1:0]    mideleg;
    logic [TBCfg.XLEN-1:0]    hideleg;
    logic                     sie;
    logic                     global_enable;
  } irq_ctrl_t;

  typedef struct packed {
    logic [TBCfg.VLEN-1:0]           pc;
    logic [TBCfg.TRANS_ID_BITS-1:0]  trans_id;
    ariane_pkg::fu_t                 fu;
    ariane_pkg::fu_op                op;
    logic [ariane_pkg::REG_ADDR_SIZE-1:0] rs1;
    logic [ariane_pkg::REG_ADDR_SIZE-1:0] rs2;
    logic [ariane_pkg::REG_ADDR_SIZE-1:0] rd;
    logic [TBCfg.XLEN-1:0]           result;
    logic                            valid;
    logic                            use_imm;
    logic                            use_zimm;
    logic                            use_pc;
    exception_t                      ex;
    branchpredict_sbe_t              bp;
    logic                            is_compressed;
    logic                            is_macro_instr;
    logic                            is_last_macro_instr;
    logic                            is_double_rd_macro_instr;
    logic                            vfp;
    logic                            is_zcmt;
  } scoreboard_entry_t;

  typedef struct packed {
    logic [TBCfg.XLEN-1:0]    S_SW;
    logic [TBCfg.XLEN-1:0]    VS_SW;
    logic [TBCfg.XLEN-1:0]    M_SW;
    logic [TBCfg.XLEN-1:0]    S_TIMER;
    logic [TBCfg.XLEN-1:0]    VS_TIMER;
    logic [TBCfg.XLEN-1:0]    M_TIMER;
    logic [TBCfg.XLEN-1:0]    S_EXT;
    logic [TBCfg.XLEN-1:0]    VS_EXT;
    logic [TBCfg.XLEN-1:0]    M_EXT;
    logic [TBCfg.XLEN-1:0]    HS_EXT;
  } interrupts_t;

  localparam interrupts_t INTERRUPTS = '{
      S_SW:     (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_S_SOFT),
      VS_SW:    (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_VS_SOFT),
      M_SW:     (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_M_SOFT),
      S_TIMER:  (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_S_TIMER),
      VS_TIMER: (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_VS_TIMER),
      M_TIMER:  (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_M_TIMER),
      S_EXT:    (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_S_EXT),
      VS_EXT:   (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_VS_EXT),
      M_EXT:    (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_M_EXT),
      HS_EXT:   (TBCfg.XLEN'(1) << (TBCfg.XLEN - 1)) | TBCfg.XLEN'(riscv::IRQ_HS_EXT)
  };

`endif
