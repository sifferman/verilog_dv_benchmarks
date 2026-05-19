// Additional parametric types for era-C csr_regfile unit tests.
//
// csr_regfile takes `rvfi_probes_csr_t` (and on later master commits `jvt_t`)
// on top of the types already in `cva6_eraC_decoder_types.svh`. Include after
// `decoder_types` inside a module that has already defined `TBCfg` and
// imported `ariane_pkg::*`. Also requires the `riscv` package (riscv_pkg.sv)
// for fcsr_t / dcsr_t / pmpcfg_t.

`ifndef CVA6_ERAC_CSR_TYPES_SVH
`define CVA6_ERAC_CSR_TYPES_SVH

  // Mirror of `RVFI_PROBES_CSR_T` macro in core/include/rvfi_types.svh.
  typedef struct packed {
    riscv::fcsr_t                                  fcsr_q;
    riscv::dcsr_t                                  dcsr_q;
    logic [TBCfg.XLEN-1:0]                         jvt_q;
    logic [TBCfg.XLEN-1:0]                         dpc_q;
    logic [TBCfg.XLEN-1:0]                         dscratch0_q;
    logic [TBCfg.XLEN-1:0]                         dscratch1_q;
    logic [TBCfg.XLEN-1:0]                         mie_q;
    logic [TBCfg.XLEN-1:0]                         mip_q;
    logic [TBCfg.XLEN-1:0]                         stvec_q;
    logic [TBCfg.XLEN-1:0]                         scounteren_q;
    logic [TBCfg.XLEN-1:0]                         sscratch_q;
    logic [TBCfg.XLEN-1:0]                         sepc_q;
    logic [TBCfg.XLEN-1:0]                         scause_q;
    logic [TBCfg.XLEN-1:0]                         stval_q;
    logic [TBCfg.XLEN-1:0]                         satp_q;
    logic [TBCfg.XLEN-1:0]                         mstatus_extended;
    logic [TBCfg.XLEN-1:0]                         medeleg_q;
    logic [TBCfg.XLEN-1:0]                         mideleg_q;
    logic [TBCfg.XLEN-1:0]                         mtvec_q;
    logic [TBCfg.XLEN-1:0]                         mcounteren_q;
    logic [TBCfg.XLEN-1:0]                         mscratch_q;
    logic [TBCfg.XLEN-1:0]                         mepc_q;
    logic [TBCfg.XLEN-1:0]                         mcause_q;
    logic [TBCfg.XLEN-1:0]                         mtval_q;
    logic                                          fiom_q;
    logic [ariane_pkg::MHPMCounterNum+3-1:0]       mcountinhibit_q;
    logic [63:0]                                   cycle_q;
    logic [63:0]                                   instret_q;
    logic [TBCfg.XLEN-1:0]                         dcache_q;
    logic [TBCfg.XLEN-1:0]                         icache_q;
    logic [TBCfg.XLEN-1:0]                         acc_cons_q;
    riscv::pmpcfg_t [63:0]                         pmpcfg_q;
    logic [63:0][TBCfg.PLEN-3:0]                   pmpaddr_q;
  } rvfi_probes_csr_t;

`endif
