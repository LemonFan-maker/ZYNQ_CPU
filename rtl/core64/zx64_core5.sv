`include "cpu_defs.svh"
`include "cpu64_defs.svh"

module zx64_core5 #(
    parameter bit ENABLE_FPU = 1'b1
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        soft_reset,
    input  logic [63:0] reset_vector,
    input  logic        irq_timer,
    input  logic        irq_external,

    output logic        imem_valid,
    output logic [31:0] imem_addr,
    input  logic        imem_ready,
    input  logic [31:0] imem_rdata,

    output logic        dmem_valid,
    output logic        dmem_we,
    output logic [7:0]  dmem_wstrb,
    output logic [31:0] dmem_addr,
    output logic [63:0] dmem_wdata,
    input  logic        dmem_ready,
    input  logic [63:0] dmem_rdata,

    output logic        fence_i,
    output logic        halted,
    output logic        illegal_instr,
    output logic [31:0] dbg_state,
    output logic [63:0] dbg_pc,
    output logic [31:0] dbg_instr
);
    localparam logic [1:0] WB_ALU = 2'd0;
    localparam logic [1:0] WB_MEM = 2'd1;
    localparam logic [1:0] WB_PC4 = 2'd2;
    localparam logic [1:0] WB_CSR = 2'd3;

    localparam logic [11:0] CSR_FFLAGS    = 12'h001;
    localparam logic [11:0] CSR_FRM       = 12'h002;
    localparam logic [11:0] CSR_FCSR      = 12'h003;
    localparam logic [11:0] CSR_MSTATUS   = 12'h300;
    localparam logic [11:0] CSR_MISA      = 12'h301;
    localparam logic [11:0] CSR_MEDELEG   = 12'h302;
    localparam logic [11:0] CSR_MIDELEG   = 12'h303;
    localparam logic [11:0] CSR_MIE       = 12'h304;
    localparam logic [11:0] CSR_MTVEC     = 12'h305;
    localparam logic [11:0] CSR_MCOUNTEREN = 12'h306;
    localparam logic [11:0] CSR_SSTATUS   = 12'h100;
    localparam logic [11:0] CSR_SIE       = 12'h104;
    localparam logic [11:0] CSR_STVEC     = 12'h105;
    localparam logic [11:0] CSR_SCOUNTEREN = 12'h106;
    localparam logic [11:0] CSR_SSCRATCH  = 12'h140;
    localparam logic [11:0] CSR_SEPC      = 12'h141;
    localparam logic [11:0] CSR_SCAUSE    = 12'h142;
    localparam logic [11:0] CSR_STVAL     = 12'h143;
    localparam logic [11:0] CSR_SIP       = 12'h144;
    localparam logic [11:0] CSR_SATP      = 12'h180;
    localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
    localparam logic [11:0] CSR_MEPC      = 12'h341;
    localparam logic [11:0] CSR_MCAUSE    = 12'h342;
    localparam logic [11:0] CSR_MTVAL     = 12'h343;
    localparam logic [11:0] CSR_MIP       = 12'h344;
    localparam logic [11:0] CSR_MCYCLE    = 12'hb00;
    localparam logic [11:0] CSR_MINSTRET  = 12'hb02;
    localparam logic [11:0] CSR_CYCLE     = 12'hc00;
    localparam logic [11:0] CSR_TIME      = 12'hc01;
    localparam logic [11:0] CSR_INSTRET   = 12'hc02;
    localparam logic [11:0] CSR_MVENDORID = 12'hf11;
    localparam logic [11:0] CSR_MARCHID   = 12'hf12;
    localparam logic [11:0] CSR_MIMPID    = 12'hf13;
    localparam logic [11:0] CSR_MHARTID   = 12'hf14;
    localparam logic        HAS_FPU_CSR = ENABLE_FPU;
    localparam logic [63:0] CSR_MISA_VALUE = ENABLE_FPU ?
                                              64'h8000_0000_0004_112d : // RV64GC + S-mode.
                                              64'h8000_0000_0004_1105;  // RV64IMAC + S-mode.
    localparam logic [63:0] SSTATUS_MASK = 64'h8000_0003_000c_f122;
    localparam logic [63:0] MSTATUS_RESET = 64'h0000_000a_0000_1800;
    localparam logic [63:0] MCAUSE_ILLEGAL = 64'd2;
    localparam logic [63:0] MCAUSE_LOAD_ADDR_MISALIGNED = 64'd4;
    localparam logic [63:0] MCAUSE_STORE_ADDR_MISALIGNED = 64'd6;
    localparam logic [63:0] MCAUSE_ECALL_U = 64'd8;
    localparam logic [63:0] MCAUSE_ECALL_S = 64'd9;
    localparam logic [63:0] MCAUSE_ECALL_M = 64'd11;
    localparam logic [63:0] MCAUSE_INST_PAGE_FAULT = 64'd12;
    localparam logic [63:0] MCAUSE_LOAD_PAGE_FAULT = 64'd13;
    localparam logic [63:0] MCAUSE_STORE_PAGE_FAULT = 64'd15;
    localparam logic [63:0] MCAUSE_INTERRUPT = 64'h8000_0000_0000_0000;
    localparam int          TLB_ENTRIES = 16;
    localparam int          TLB_INDEX_BITS = $clog2(TLB_ENTRIES);
    localparam int          IRQ_S_TIMER = 5;
    localparam int          IRQ_M_TIMER = 7;
    localparam int          IRQ_S_EXT = 9;
    localparam int          IRQ_M_EXT = 11;
    localparam logic [63:0] MIP_STIP = 64'h0000_0000_0000_0020;
    localparam logic [63:0] MIP_MTIP = 64'h0000_0000_0000_0080;
    localparam logic [63:0] MIP_SEIP = 64'h0000_0000_0000_0200;
    localparam logic [63:0] MIP_MEIP = 64'h0000_0000_0000_0800;

    typedef enum logic [1:0] {
        PRIV_U = 2'b00,
        PRIV_S = 2'b01,
        PRIV_M = 2'b11
    } priv_mode_t;

    typedef enum logic [1:0] {
        AMO_READ,
        AMO_CALC,
        AMO_WRITE
    } amo_state_t;

    typedef enum logic [1:0] {
        PTW_IDLE,
        PTW_L2,
        PTW_L1,
        PTW_L0
    } ptw_state_t;

    logic [63:0] pc_q;
    logic        reset_vector_pending_q;
    logic        halted_q;
    logic        illegal_q;
    logic        wfi_q;
    logic        fetch2_q;
    logic [63:0] fetch2_pc_q;
    logic [15:0] fetch2_upper_half_q;

    logic        if_id_valid;
    logic [63:0] if_id_pc;
    logic [31:0] if_id_instr;
    logic [2:0]  if_id_instr_len;

    logic        id_ex_valid;
    logic [63:0] id_ex_pc;
    logic [31:0] id_ex_instr;
    logic [2:0]  id_ex_instr_len;
    logic [4:0]  id_ex_rs1;
    logic [4:0]  id_ex_rs2;
    logic [4:0]  id_ex_rs3;
    logic [4:0]  id_ex_rd;
    logic [63:0] id_ex_rs1_data;
    logic [63:0] id_ex_rs2_data;
    logic [63:0] id_ex_imm;
    alu_op_t     id_ex_alu_op;
    logic        id_ex_alu_a_pc;
    logic        id_ex_alu_b_imm;
    logic        id_ex_reg_write;
    logic        id_ex_mem_read;
    logic        id_ex_mem_write;
    logic [2:0]  id_ex_mem_funct3;
    logic [1:0]  id_ex_wb_sel;
    logic        id_ex_branch;
    logic        id_ex_jump;
    logic        id_ex_jalr;
    logic        id_ex_muldiv;
    logic        id_ex_amo;
    logic        id_ex_csr;
    logic        id_ex_fp_reg_write;
    logic        id_ex_fp_load;
    logic        id_ex_fp_store;
    logic        id_ex_fp_to_int;
    logic        id_ex_int_to_fp;
    logic        id_ex_fp_sgnj;
    logic        id_ex_fp_class;
    logic        id_ex_fp_cmp;
    logic        id_ex_fp_minmax;
    logic        id_ex_fp_addsub;
    logic        id_ex_fp_mul;
    logic        id_ex_fp_divsqrt;
    logic        id_ex_fp_fma;
    logic        id_ex_fp_cvt;
    logic [63:0] id_ex_frs1_data;
    logic [63:0] id_ex_frs2_data;
    logic [63:0] id_ex_frs3_data;
    logic        id_ex_ecall;
    logic        id_ex_wfi;
    logic        id_ex_fence_i;
    logic        id_ex_sfence_vma;
    logic        id_ex_mret;
    logic        id_ex_sret;
    logic        id_ex_halt;
    logic        id_ex_illegal;

    logic        ex_mem_valid;
    logic [63:0] ex_mem_pc;
    logic [31:0] ex_mem_instr;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_reg_write;
    logic        ex_mem_mem_read;
    logic        ex_mem_mem_write;
    logic [2:0]  ex_mem_mem_funct3;
    logic [63:0] ex_mem_alu_result;
    logic [63:0] ex_mem_store_data;
    logic [7:0]  ex_mem_store_strobe;
    logic [63:0] ex_mem_wb_data;
    logic        ex_mem_fp_reg_write;
    logic        ex_mem_fp_load;
    logic [63:0] ex_mem_fp_wb_data;
    logic [4:0]  ex_mem_fp_fflags;
    logic [1:0]  ex_mem_wb_sel;
    logic        ex_mem_halt;
    logic        ex_mem_illegal;
    logic [63:0] ex_mem_trap_cause;
    logic [63:0] ex_mem_trap_tval;
    logic        ex_mem_amo;
    logic [63:0] ex_mem_rs2_data;

    logic        mem_wb_valid;
    logic [4:0]  mem_wb_rd;
    logic        mem_wb_reg_write;
    logic [63:0] mem_wb_data;
    logic        mem_wb_fp_reg_write;
    logic [63:0] mem_wb_fp_data;

    logic [4:0]  id_rs1;
    logic [4:0]  id_rs2;
    logic [4:0]  id_rs3;
    logic [4:0]  id_rd;
    logic [6:0]  id_opcode;
    logic [2:0]  id_funct3;
    logic [6:0]  id_funct7;
    logic [63:0] rs1_data;
    logic [63:0] rs2_data;
    logic [63:0] id_rs1_data;
    logic [63:0] id_rs2_data;

    logic        id_uses_rs1;
    logic        id_uses_rs2;
    alu_op_t     id_alu_op;
    logic        id_alu_a_pc;
    logic        id_alu_b_imm;
    logic [63:0] id_imm;
    logic        id_reg_write;
    logic        id_mem_read;
    logic        id_mem_write;
    logic [1:0]  id_wb_sel;
    logic        id_branch;
    logic        id_jump;
    logic        id_jalr;
    logic        id_muldiv;
    logic        id_amo;
    logic        id_csr;
    logic        id_uses_frs1;
    logic        id_uses_frs2;
    logic        id_uses_frs3;
    logic        id_fp_reg_write;
    logic        id_fp_load;
    logic        id_fp_store;
    logic        id_fp_to_int;
    logic        id_int_to_fp;
    logic        id_fp_sgnj;
    logic        id_fp_class;
    logic        id_fp_cmp;
    logic        id_fp_minmax;
    logic        id_fp_addsub;
    logic        id_fp_mul;
    logic        id_fp_divsqrt;
    logic        id_fp_fma;
    logic        id_fp_cvt;
    logic        id_ecall;
    logic        id_wfi;
    logic        id_fence_i;
    logic        id_sfence_vma;
    logic        id_mret;
    logic        id_sret;
    logic        id_halt;
    logic        id_illegal;

    logic [63:0] ex_rs1_data;
    logic [63:0] ex_rs2_data;
    logic [63:0] frs1_data;
    logic [63:0] frs2_data;
    logic [63:0] frs3_data;
    logic [63:0] id_frs1_data;
    logic [63:0] id_frs2_data;
    logic [63:0] id_frs3_data;
    logic [63:0] ex_frs1_data;
    logic [63:0] ex_frs2_data;
    logic [63:0] ex_frs3_data;
    logic [63:0] ex_alu_a;
    logic [63:0] ex_alu_b;
    logic [63:0] ex_alu_y;
    logic [63:0] ex_word_y;
    logic        ex_word_op;
    logic        ex_branch_take;
    logic        ex_redirect;
    logic [63:0] ex_redirect_pc;
    logic        ex_mem_fault;
    logic [63:0] ex_wb_data;
    logic [63:0] ex_fp_wb_data;
    logic [4:0]  ex_fp_fflags_w;
    logic [4:0]  ex_mem_amo_funct5;
    logic        ex_mem_amo_width_w;
    logic        ex_mem_amo_lr;
    logic        ex_mem_amo_sc;

    logic        muldiv_start;
    logic        muldiv_busy;
    logic        muldiv_done;
    logic [63:0] muldiv_result;

    priv_mode_t  current_priv;
    logic [4:0]  csr_fflags;
    logic [2:0]  csr_frm;
    logic [63:0] csr_mstatus;
    logic [63:0] csr_medeleg;
    logic [63:0] csr_mideleg;
    logic [63:0] csr_mie;
    logic [63:0] csr_mcounteren;
    logic [63:0] csr_mtvec;
    logic [63:0] csr_sie;
    logic [63:0] csr_scounteren;
    logic [63:0] csr_stvec;
    logic [63:0] csr_sscratch;
    logic [63:0] csr_sepc;
    logic [63:0] csr_scause;
    logic [63:0] csr_stval;
    logic [63:0] csr_sip;
    logic [63:0] csr_satp;
    logic [63:0] csr_mscratch;
    logic [63:0] csr_mepc;
    logic [63:0] csr_mcause;
    logic [63:0] csr_mtval;
    logic [63:0] csr_mip;
    logic [63:0] csr_mip_view;
    logic [63:0] csr_sip_view;
    logic [63:0] mcycle_counter;
    logic [63:0] minstret_counter;
    logic        lr_reservation_valid;
    logic [29:0] lr_reservation_addr;
    amo_state_t  amo_state_q;
    ptw_state_t  ptw_state_q;
    logic        translate_active;
    logic        fetch_tlb_hit;
    logic [31:0] fetch_tlb_paddr;
    logic [63:0] fetch_vaddr;
    logic [63:0] fetch_epc;
    logic        fetch_translate_pending;
    logic        data_tlb_hit;
    logic [31:0] data_tlb_paddr;
    logic [63:0] data_vaddr;
    logic        data_is_store;
    logic        data_translate_needed;
    logic        data_translate_pending;
    logic        ptw_busy;
    logic [63:0] ptw_vaddr_q;
    logic [63:0] ptw_epc_q;
    logic        ptw_is_fetch_q;
    logic        ptw_we_q;
    logic [31:0] ptw_pte_addr_q;
    logic [TLB_ENTRIES-1:0]      itlb_valid;
    logic [TLB_ENTRIES-1:0]      dtlb_valid;
    logic [26:0]                 itlb_vpn_tags [0:TLB_ENTRIES-1];
    logic [26:0]                 dtlb_vpn_tags [0:TLB_ENTRIES-1];
    logic [63:0]                 itlb_ptes [0:TLB_ENTRIES-1];
    logic [63:0]                 dtlb_ptes [0:TLB_ENTRIES-1];
    logic [1:0]                  itlb_levels [0:TLB_ENTRIES-1];
    logic [1:0]                  dtlb_levels [0:TLB_ENTRIES-1];
    logic [63:0] amo_wdata_q;
    logic [7:0]  amo_wstrb_q;
    logic [63:0] amo_wb_data_q;
    logic [63:0] amo_rdata_q;
    logic [11:0] ex_csr_addr;
    logic [63:0] ex_csr_rdata;
    logic [63:0] ex_csr_operand;
    logic [63:0] ex_csr_wdata;
    logic        ex_csr_supported;
    logic        ex_csr_wen;
    logic        ex_csr_read_only;
    logic        ex_csr_fp;
    logic        ex_csr_illegal;
    logic        ex_ecall;
    logic        ex_wfi;
    logic        ex_fence_i;
    logic        ex_sfence_vma;
    logic        ex_mret;
    logic        ex_sret;
    logic [63:0] ex_trap_cause;
    logic        ex_trap_to_s;
    logic        ex_system_redirect;
    logic [63:0] ex_system_redirect_pc;
    logic [63:0] interrupt_cause;
    logic        interrupt_pending;
    logic [63:0] interrupt_epc;

    logic        load_use_hazard;
    logic        fp_raw_hazard;
    logic        ex_mem_fp_commit;
    logic        mem_stall;
    logic        amo_stall;
    logic        execute_stall;
    logic        fetch_accept;

    assign id_opcode = if_id_instr[6:0];
    assign id_rd = if_id_instr[11:7];
    assign id_funct3 = if_id_instr[14:12];
    assign id_rs1 = if_id_instr[19:15];
    assign id_rs2 = if_id_instr[24:20];
    assign id_rs3 = if_id_instr[31:27];
    assign id_funct7 = if_id_instr[31:25];

    assign translate_active = (csr_satp[63:60] == 4'h8) && (current_priv != PRIV_M);
    assign fetch_vaddr = fetch2_q ? (fetch2_pc_q + 64'd2) : pc_q;
    assign fetch_epc = fetch2_q ? fetch2_pc_q : pc_q;
    assign data_vaddr = ex_mem_alu_result;
    assign data_is_store = ex_mem_mem_write || ex_mem_amo;
    assign data_translate_needed = translate_active && ex_mem_valid &&
                                   (ex_mem_amo || ex_mem_mem_read || ex_mem_mem_write);
    assign fetch_translate_pending = translate_active && !fetch_tlb_hit;
    assign data_translate_pending = data_translate_needed && !data_tlb_hit;
    assign ptw_busy = (ptw_state_q != PTW_IDLE);

    assign imem_valid = !halted_q && !wfi_q && !mem_stall && !amo_stall &&
                        !execute_stall && !load_use_hazard && !fp_raw_hazard && !ptw_busy &&
                        !fetch_translate_pending && !data_translate_pending;
    assign imem_addr = translate_active ? fetch_tlb_paddr : fetch_vaddr[31:0];

    assign dmem_valid = ptw_busy ||
                        (!halted_q && ex_mem_valid &&
                         (ex_mem_amo || ex_mem_mem_read || ex_mem_mem_write) &&
                         (!ex_mem_amo || amo_state_q != AMO_CALC) &&
                         (!translate_active || data_tlb_hit));
    assign dmem_we = ptw_busy ? 1'b0 :
                     (ex_mem_amo ? (amo_state_q == AMO_WRITE) : ex_mem_mem_write);
    assign dmem_wstrb = dmem_we ? (ex_mem_amo ? amo_wstrb_q : ex_mem_store_strobe) : 8'd0;
    assign dmem_addr = ptw_busy ? ptw_pte_addr_q :
                       (translate_active ? data_tlb_paddr : ex_mem_alu_result[31:0]);
    assign dmem_wdata = ex_mem_amo ? amo_wdata_q : ex_mem_store_data;

    assign halted = halted_q;
    assign illegal_instr = illegal_q;
    assign dbg_state = {21'd0, fp_raw_hazard, amo_state_q, amo_stall, muldiv_busy, execute_stall,
                        mem_stall, load_use_hazard,
                        if_id_valid, id_ex_valid, ex_mem_valid};
    assign dbg_pc = pc_q;
    assign dbg_instr = if_id_instr;

    regfile64 u_regfile (
        .clk(clk),
        .wen(mem_wb_valid && mem_wb_reg_write && !halted_q),
        .waddr(mem_wb_rd),
        .wdata(mem_wb_data),
        .raddr1(id_rs1),
        .rdata1(rs1_data),
        .raddr2(id_rs2),
        .rdata2(rs2_data)
    );

    fregfile64 u_fregfile (
        .clk(clk),
        .wen(mem_wb_fp_reg_write && !halted_q),
        .waddr(mem_wb_rd),
        .wdata(mem_wb_fp_data),
        .raddr1(id_rs1),
        .rdata1(frs1_data),
        .raddr2(id_rs2),
        .rdata2(frs2_data),
        .raddr3(id_rs3),
        .rdata3(frs3_data)
    );

    alu64 u_alu (
        .op(id_ex_alu_op),
        .a(ex_alu_a),
        .b(ex_alu_b),
        .y(ex_alu_y)
    );

    zx64_muldiv_unit u_muldiv (
        .clk(clk),
        .rst_n(rst_n),
        .start(muldiv_start),
        .word_op(id_ex_instr[6:0] == OPCODE64_OP_32),
        .funct3(id_ex_instr[14:12]),
        .rs1(ex_rs1_data),
        .rs2(ex_rs2_data),
        .busy(muldiv_busy),
        .done(muldiv_done),
        .result(muldiv_result)
    );

    function automatic logic [63:0] sext32(input logic [31:0] v);
        sext32 = {{32{v[31]}}, v};
    endfunction

    function automatic logic [63:0] imm_i(input logic [31:0] inst);
        imm_i = {{52{inst[31]}}, inst[31:20]};
    endfunction

    function automatic logic [63:0] imm_s(input logic [31:0] inst);
        imm_s = {{52{inst[31]}}, inst[31:25], inst[11:7]};
    endfunction

    function automatic logic [63:0] imm_b(input logic [31:0] inst);
        imm_b = {{51{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    endfunction

    function automatic logic [63:0] imm_u(input logic [31:0] inst);
        imm_u = sext32({inst[31:12], 12'd0});
    endfunction

    function automatic logic [63:0] imm_j(input logic [31:0] inst);
        imm_j = {{43{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
    endfunction

    function automatic logic [31:0] enc_i32(input logic signed [11:0] imm,
                                            input logic [4:0] rs1_i,
                                            input logic [2:0] funct3_i,
                                            input logic [4:0] rd_i,
                                            input logic [6:0] opcode_i);
        enc_i32 = {imm[11:0], rs1_i, funct3_i, rd_i, opcode_i};
    endfunction

    function automatic logic [31:0] enc_s32(input logic signed [11:0] imm,
                                            input logic [4:0] rs2_i,
                                            input logic [4:0] rs1_i,
                                            input logic [2:0] funct3_i,
                                            input logic [6:0] opcode_i);
        enc_s32 = {imm[11:5], rs2_i, rs1_i, funct3_i, imm[4:0], opcode_i};
    endfunction

    function automatic logic [31:0] enc_b32(input logic signed [12:0] imm,
                                            input logic [4:0] rs2_i,
                                            input logic [4:0] rs1_i,
                                            input logic [2:0] funct3_i,
                                            input logic [6:0] opcode_i);
        enc_b32 = {imm[12], imm[10:5], rs2_i, rs1_i, funct3_i, imm[4:1], imm[11], opcode_i};
    endfunction

    function automatic logic [31:0] enc_u32(input logic [19:0] imm20,
                                            input logic [4:0] rd_i,
                                            input logic [6:0] opcode_i);
        enc_u32 = {imm20, rd_i, opcode_i};
    endfunction

    function automatic logic [31:0] enc_j32(input logic signed [20:0] imm,
                                            input logic [4:0] rd_i,
                                            input logic [6:0] opcode_i);
        enc_j32 = {imm[20], imm[10:1], imm[11], imm[19:12], rd_i, opcode_i};
    endfunction

    function automatic logic [31:0] enc_r32(input logic [6:0] funct7_i,
                                            input logic [4:0] rs2_i,
                                            input logic [4:0] rs1_i,
                                            input logic [2:0] funct3_i,
                                            input logic [4:0] rd_i,
                                            input logic [6:0] opcode_i);
        enc_r32 = {funct7_i, rs2_i, rs1_i, funct3_i, rd_i, opcode_i};
    endfunction

    function automatic logic [31:0] expand_compressed(input logic [15:0] c);
        logic [4:0] rd_i;
        logic [4:0] rs1_i;
        logic [4:0] rs2_i;
        logic [4:0] rdp_i;
        logic [4:0] rs1p_i;
        logic [4:0] rs2p_i;
        logic signed [11:0] imm12;
        logic signed [12:0] imm13;
        logic signed [20:0] imm21;
        logic [19:0] imm20;
        logic [5:0] shamt6;
        begin
            rd_i = c[11:7];
            rs1_i = c[11:7];
            rs2_i = c[6:2];
            rdp_i = {2'b01, c[4:2]};
            rs1p_i = {2'b01, c[9:7]};
            rs2p_i = {2'b01, c[4:2]};
            imm12 = 12'd0;
            imm13 = 13'd0;
            imm21 = 21'd0;
            imm20 = 20'd0;
            shamt6 = {c[12], c[6:2]};
            expand_compressed = 32'd0;

            unique case (c[1:0])
                2'b00: begin
                    unique case (c[15:13])
                        3'b000: begin
                            imm12 = {2'b00, c[10:7], c[12:11], c[5], c[6], 2'b00};
                            if (imm12 != 12'd0) begin
                                expand_compressed = enc_i32(imm12, 5'd2, 3'b000, rdp_i, OPCODE64_OP_IMM);
                            end
                        end
                        3'b010: begin
                            imm12 = {5'd0, c[5], c[12:10], c[6], 2'b00};
                            expand_compressed = enc_i32(imm12, rs1p_i, 3'b010, rdp_i, OPCODE64_LOAD);
                        end
                        3'b001: begin
                            imm12 = {4'd0, c[6:5], c[12:10], 3'b000};
                            expand_compressed = enc_i32(imm12, rs1p_i, 3'b011, rdp_i, OPCODE64_LOAD_FP);
                        end
                        3'b011: begin
                            imm12 = {4'd0, c[6:5], c[12:10], 3'b000};
                            expand_compressed = enc_i32(imm12, rs1p_i, 3'b011, rdp_i, OPCODE64_LOAD);
                        end
                        3'b110: begin
                            imm12 = {5'd0, c[5], c[12:10], c[6], 2'b00};
                            expand_compressed = enc_s32(imm12, rs2p_i, rs1p_i, 3'b010, OPCODE64_STORE);
                        end
                        3'b101: begin
                            imm12 = {4'd0, c[6:5], c[12:10], 3'b000};
                            expand_compressed = enc_s32(imm12, rs2p_i, rs1p_i, 3'b011, OPCODE64_STORE_FP);
                        end
                        3'b111: begin
                            imm12 = {4'd0, c[6:5], c[12:10], 3'b000};
                            expand_compressed = enc_s32(imm12, rs2p_i, rs1p_i, 3'b011, OPCODE64_STORE);
                        end
                        default: expand_compressed = 32'd0;
                    endcase
                end

                2'b01: begin
                    unique case (c[15:13])
                        3'b000: begin
                            imm12 = {{6{c[12]}}, c[12], c[6:2]};
                            expand_compressed = enc_i32(imm12, rd_i, 3'b000, rd_i, OPCODE64_OP_IMM);
                        end
                        3'b001: begin
                            imm12 = {{6{c[12]}}, c[12], c[6:2]};
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32(imm12, rd_i, 3'b000, rd_i, OPCODE64_OP_IMM_32);
                            end
                        end
                        3'b010: begin
                            imm12 = {{6{c[12]}}, c[12], c[6:2]};
                            expand_compressed = enc_i32(imm12, 5'd0, 3'b000, rd_i, OPCODE64_OP_IMM);
                        end
                        3'b011: begin
                            if (rd_i == 5'd2) begin
                                imm12 = {{2{c[12]}}, c[12], c[4:3], c[5], c[2], c[6], 4'b0000};
                                if (imm12 != 12'd0) begin
                                    expand_compressed = enc_i32(imm12, 5'd2, 3'b000, 5'd2, OPCODE64_OP_IMM);
                                end
                            end else if (rd_i != 5'd0) begin
                                imm20 = {{14{c[12]}}, c[12], c[6:2]};
                                if (c[12] || c[6:2] != 5'd0) begin
                                    expand_compressed = enc_u32(imm20, rd_i, OPCODE64_LUI);
                                end
                            end
                        end
                        3'b100: begin
                            unique case (c[11:10])
                                2'b00: expand_compressed = enc_i32({6'b000000, shamt6}, rs1p_i, 3'b101,
                                                                    rs1p_i, OPCODE64_OP_IMM);
                                2'b01: expand_compressed = enc_i32({6'b010000, shamt6}, rs1p_i, 3'b101,
                                                                    rs1p_i, OPCODE64_OP_IMM);
                                2'b10: begin
                                    imm12 = {{6{c[12]}}, c[12], c[6:2]};
                                    expand_compressed = enc_i32(imm12, rs1p_i, 3'b111, rs1p_i,
                                                                OPCODE64_OP_IMM);
                                end
                                2'b11: begin
                                    if (!c[12]) begin
                                        unique case (c[6:5])
                                            2'b00: expand_compressed = enc_r32(7'b0100000, rs2p_i, rs1p_i, 3'b000, rs1p_i, OPCODE64_OP);
                                            2'b01: expand_compressed = enc_r32(7'b0000000, rs2p_i, rs1p_i, 3'b100, rs1p_i, OPCODE64_OP);
                                            2'b10: expand_compressed = enc_r32(7'b0000000, rs2p_i, rs1p_i, 3'b110, rs1p_i, OPCODE64_OP);
                                            2'b11: expand_compressed = enc_r32(7'b0000000, rs2p_i, rs1p_i, 3'b111, rs1p_i, OPCODE64_OP);
                                            default: expand_compressed = 32'd0;
                                        endcase
                                    end else begin
                                        unique case (c[6:5])
                                            2'b00: expand_compressed = enc_r32(7'b0100000, rs2p_i, rs1p_i, 3'b000, rs1p_i, OPCODE64_OP_32);
                                            2'b01: expand_compressed = enc_r32(7'b0000000, rs2p_i, rs1p_i, 3'b000, rs1p_i, OPCODE64_OP_32);
                                            default: expand_compressed = 32'd0;
                                        endcase
                                    end
                                end
                                default: expand_compressed = 32'd0;
                            endcase
                        end
                        3'b101: begin
                            imm21 = {{9{c[12]}}, c[12], c[8], c[10:9], c[6], c[7],
                                     c[2], c[11], c[5:3], 1'b0};
                            expand_compressed = enc_j32(imm21, 5'd0, OPCODE64_JAL);
                        end
                        3'b110: begin
                            imm13 = {{4{c[12]}}, c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};
                            expand_compressed = enc_b32(imm13, 5'd0, rs1p_i, 3'b000, OPCODE64_BRANCH);
                        end
                        3'b111: begin
                            imm13 = {{4{c[12]}}, c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};
                            expand_compressed = enc_b32(imm13, 5'd0, rs1p_i, 3'b001, OPCODE64_BRANCH);
                        end
                        default: expand_compressed = 32'd0;
                    endcase
                end

                2'b10: begin
                    unique case (c[15:13])
                        3'b000: begin
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32({6'b000000, shamt6}, rd_i, 3'b001,
                                                            rd_i, OPCODE64_OP_IMM);
                            end
                        end
                        3'b010: begin
                            imm12 = {4'd0, c[3:2], c[12], c[6:4], 2'b00};
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32(imm12, 5'd2, 3'b010, rd_i, OPCODE64_LOAD);
                            end
                        end
                        3'b001: begin
                            imm12 = {3'd0, c[4:2], c[12], c[6:5], 3'b000};
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32(imm12, 5'd2, 3'b011, rd_i, OPCODE64_LOAD_FP);
                            end
                        end
                        3'b011: begin
                            imm12 = {3'd0, c[4:2], c[12], c[6:5], 3'b000};
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32(imm12, 5'd2, 3'b011, rd_i, OPCODE64_LOAD);
                            end
                        end
                        3'b100: begin
                            if (!c[12] && rs2_i != 5'd0) begin
                                expand_compressed = enc_r32(7'b0000000, rs2_i, 5'd0, 3'b000, rd_i, OPCODE64_OP);
                            end else if (!c[12] && rs2_i == 5'd0 && rd_i != 5'd0) begin
                                expand_compressed = enc_i32(12'd0, rd_i, 3'b000, 5'd0, OPCODE64_JALR);
                            end else if (c[12] && rd_i == 5'd0 && rs2_i == 5'd0) begin
                                expand_compressed = 32'h0010_0073;
                            end else if (c[12] && rs2_i == 5'd0 && rd_i != 5'd0) begin
                                expand_compressed = enc_i32(12'd0, rd_i, 3'b000, 5'd1, OPCODE64_JALR);
                            end else if (c[12] && rd_i != 5'd0 && rs2_i != 5'd0) begin
                                expand_compressed = enc_r32(7'b0000000, rs2_i, rd_i, 3'b000, rd_i, OPCODE64_OP);
                            end
                        end
                        3'b110: begin
                            imm12 = {4'd0, c[8:7], c[12:9], 2'b00};
                            expand_compressed = enc_s32(imm12, rs2_i, 5'd2, 3'b010, OPCODE64_STORE);
                        end
                        3'b101: begin
                            imm12 = {3'd0, c[9:7], c[12:10], 3'b000};
                            expand_compressed = enc_s32(imm12, rs2_i, 5'd2, 3'b011, OPCODE64_STORE_FP);
                        end
                        3'b111: begin
                            imm12 = {3'd0, c[9:7], c[12:10], 3'b000};
                            expand_compressed = enc_s32(imm12, rs2_i, 5'd2, 3'b011, OPCODE64_STORE);
                        end
                        default: expand_compressed = 32'd0;
                    endcase
                end

                default: expand_compressed = 32'd0;
            endcase
        end
    endfunction

    function automatic logic branch_supported(input logic [2:0] f3);
        branch_supported = (f3 == 3'b000) || (f3 == 3'b001) ||
                           (f3 == 3'b100) || (f3 == 3'b101) ||
                           (f3 == 3'b110) || (f3 == 3'b111);
    endfunction

    function automatic logic branch_taken(input logic [2:0] f3,
                                          input logic [63:0] a,
                                          input logic [63:0] b);
        case (f3)
            3'b000: branch_taken = (a == b);
            3'b001: branch_taken = (a != b);
            3'b100: branch_taken = ($signed(a) < $signed(b));
            3'b101: branch_taken = ($signed(a) >= $signed(b));
            3'b110: branch_taken = (a < b);
            3'b111: branch_taken = (a >= b);
            default: branch_taken = 1'b0;
        endcase
    endfunction

    function automatic logic mem_load_supported(input logic [2:0] f3);
        mem_load_supported = (f3 == 3'b000) || (f3 == 3'b001) ||
                             (f3 == 3'b010) || (f3 == 3'b011) ||
                             (f3 == 3'b100) || (f3 == 3'b101) ||
                             (f3 == 3'b110);
    endfunction

    function automatic logic mem_store_supported(input logic [2:0] f3);
        mem_store_supported = (f3 == 3'b000) || (f3 == 3'b001) ||
                              (f3 == 3'b010) || (f3 == 3'b011);
    endfunction

    function automatic logic mem_aligned(input logic [2:0] f3, input logic [2:0] off);
        case (f3)
            3'b000, 3'b100: mem_aligned = 1'b1;
            3'b001, 3'b101: mem_aligned = (off[0] == 1'b0);
            3'b010, 3'b110: mem_aligned = (off[1:0] == 2'b00);
            3'b011:         mem_aligned = (off == 3'b000);
            default:        mem_aligned = 1'b0;
        endcase
    endfunction

    function automatic logic [7:0] store_strobe(input logic [2:0] f3, input logic [2:0] off);
        case (f3)
            3'b000: store_strobe = 8'b0000_0001 << off;
            3'b001: store_strobe = 8'b0000_0011 << off;
            3'b010: store_strobe = 8'b0000_1111 << off;
            3'b011: store_strobe = 8'b1111_1111;
            default: store_strobe = 8'd0;
        endcase
    endfunction

    function automatic logic [63:0] store_data(input logic [2:0] f3,
                                               input logic [2:0] off,
                                               input logic [63:0] src);
        logic [63:0] masked;
        begin
            case (f3)
                3'b000: masked = {56'd0, src[7:0]};
                3'b001: masked = {48'd0, src[15:0]};
                3'b010: masked = {32'd0, src[31:0]};
                3'b011: masked = src;
                default: masked = 64'd0;
            endcase
            store_data = masked << {off, 3'b000};
        end
    endfunction

    function automatic logic [63:0] load_data(input logic [2:0] f3,
                                              input logic [2:0] off,
                                              input logic [63:0] src);
        logic [63:0] shifted;
        begin
            shifted = src >> {off, 3'b000};
            case (f3)
                3'b000: load_data = {{56{shifted[7]}}, shifted[7:0]};
                3'b001: load_data = {{48{shifted[15]}}, shifted[15:0]};
                3'b010: load_data = {{32{shifted[31]}}, shifted[31:0]};
                3'b011: load_data = shifted;
                3'b100: load_data = {56'd0, shifted[7:0]};
                3'b101: load_data = {48'd0, shifted[15:0]};
                3'b110: load_data = {32'd0, shifted[31:0]};
                default: load_data = 64'd0;
            endcase
        end
    endfunction

    function automatic logic fp_mem_supported(input logic [2:0] f3);
        fp_mem_supported = (f3 == 3'b010) || (f3 == 3'b011);
    endfunction

    function automatic logic fp_opcode(input logic [6:0] opcode);
        unique case (opcode)
            OPCODE64_LOAD_FP,
            OPCODE64_STORE_FP,
            OPCODE64_MADD,
            OPCODE64_MSUB,
            OPCODE64_NMSUB,
            OPCODE64_NMADD,
            OPCODE64_OP_FP: fp_opcode = 1'b1;
            default:        fp_opcode = 1'b0;
        endcase
    endfunction

    function automatic logic fp_rm_valid(input logic [2:0] rm,
                                         input logic [2:0] frm);
        fp_rm_valid = (rm <= 3'b100) || ((rm == 3'b111) && (frm <= 3'b100));
    endfunction

    function automatic logic [2:0] fp_effective_rm(input logic [2:0] rm,
                                                   input logic [2:0] frm);
        fp_effective_rm = (rm == 3'b111) ? frm : rm;
    endfunction

    function automatic logic [63:0] fp_load_data(input logic [2:0] f3,
                                                 input logic [2:0] off,
                                                 input logic [63:0] src);
        logic [63:0] shifted;
        begin
            shifted = src >> {off, 3'b000};
            unique case (f3)
                3'b010: fp_load_data = {32'hffff_ffff, shifted[31:0]};
                3'b011: fp_load_data = shifted;
                default: fp_load_data = 64'd0;
            endcase
        end
    endfunction

    function automatic logic [5:0] u64_msb_index(input logic [63:0] mag);
        begin
            u64_msb_index = 6'd0;
            for (int i = 0; i < 64; i++) begin
                if (mag[i]) begin
                    u64_msb_index = i[5:0];
                end
            end
        end
    endfunction

    function automatic logic [127:0] fp_shift_right_jam128(input logic [127:0] value,
                                                           input logic [7:0] shift);
        begin
            if (shift == 8'd0) begin
                fp_shift_right_jam128 = value;
            end else if (shift < 8'd128) begin
                fp_shift_right_jam128 = (value >> shift) |
                                        (((value & ((128'd1 << shift) - 128'd1)) != 128'd0) ?
                                         128'd1 : 128'd0);
            end else begin
                fp_shift_right_jam128 = (value != 128'd0) ? 128'd1 : 128'd0;
            end
        end
    endfunction

    function automatic logic [63:0] fp_round_int_mag(input logic [127:0] fixed,
                                                     input logic sign,
                                                     input logic [2:0] rm);
        logic [63:0] int_part;
        logic [63:0] frac_part;
        logic guard;
        logic sticky;
        logic inc;
        begin
            int_part = fixed[126:63];
            frac_part = fixed[62:0];
            guard = fixed[62];
            sticky = (fixed[61:0] != 62'd0);
            inc = fp_round_increment(rm, sign, guard, sticky, int_part[0]);
            fp_round_int_mag = int_part + {63'd0, inc};
        end
    endfunction

    function automatic logic [63:0] fp_cvt_f2i_sat(input logic sign,
                                                   input logic is_unsigned,
                                                   input logic is_word);
        begin
            if (is_word) begin
                if (is_unsigned) begin
                    fp_cvt_f2i_sat = sign ? 64'd0 : 64'hffff_ffff_ffff_ffff;
                end else begin
                    fp_cvt_f2i_sat = sign ? 64'hffff_ffff_8000_0000 : 64'h0000_0000_7fff_ffff;
                end
            end else begin
                if (is_unsigned) begin
                    fp_cvt_f2i_sat = sign ? 64'd0 : 64'hffff_ffff_ffff_ffff;
                end else begin
                    fp_cvt_f2i_sat = sign ? 64'h8000_0000_0000_0000 : 64'h7fff_ffff_ffff_ffff;
                end
            end
        end
    endfunction

    function automatic logic [63:0] fp_cvt_f2i_pack(input logic sign,
                                                    input logic is_unsigned,
                                                    input logic is_word,
                                                    input logic [63:0] mag);
        logic [63:0] raw;
        begin
            if (is_unsigned) begin
                raw = mag;
            end else begin
                raw = sign ? (~mag + 64'd1) : mag;
            end
            fp_cvt_f2i_pack = is_word ? {{32{raw[31]}}, raw[31:0]} : raw;
        end
    endfunction

    function automatic logic fp_cvt_f2i_overflow(input logic sign,
                                                 input logic is_unsigned,
                                                 input logic is_word,
                                                 input logic [63:0] mag);
        begin
            if (is_unsigned) begin
                fp_cvt_f2i_overflow = sign ? (mag != 64'd0) :
                                      (is_word ? (mag > 64'h0000_0000_ffff_ffff) :
                                                 1'b0);
            end else if (is_word) begin
                fp_cvt_f2i_overflow = sign ? (mag > 64'h0000_0000_8000_0000) :
                                             (mag > 64'h0000_0000_7fff_ffff);
            end else begin
                fp_cvt_f2i_overflow = sign ? (mag > 64'h8000_0000_0000_0000) :
                                             (mag > 64'h7fff_ffff_ffff_ffff);
            end
        end
    endfunction

    function automatic logic [63:0] fp_to_int_cvt_data(input logic [31:0] inst,
                                                       input logic [63:0] src,
                                                       input logic [2:0] frm);
        logic want_double;
        logic is_unsigned;
        logic is_word;
        logic sign;
        logic [10:0] exp64;
        logic [7:0] exp32;
        logic [51:0] frac64;
        logic [22:0] frac32;
        logic special;
        logic nan;
        logic signed [12:0] exp_unbiased;
        logic [127:0] fixed;
        logic [127:0] sig_ext;
        logic [7:0] shift;
        logic [63:0] mag;
        logic [2:0] rm;
        begin
            want_double = inst[25];
            is_unsigned = inst[20];
            is_word = !inst[21];
            rm = fp_effective_rm(inst[14:12], frm);

            if (want_double) begin
                sign = src[63];
                exp64 = src[62:52];
                frac64 = src[51:0];
                special = (exp64 == 11'h7ff);
                nan = special && (frac64 != 52'd0);
                if (exp64 == 11'd0) begin
                    exp_unbiased = -13'sd1022;
                    sig_ext = {75'd0, frac64};
                end else begin
                    exp_unbiased = $signed({2'd0, exp64}) - 13'sd1023;
                    sig_ext = {75'd0, 1'b1, frac64};
                end
                fixed = sig_ext << 7'd63;
                if (exp_unbiased >= 13'sd52) begin
                    shift = exp_unbiased - 13'sd52;
                    fixed = (shift >= 8'd12) ? 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff :
                                               (fixed << shift);
                end else begin
                    shift = 13'sd52 - exp_unbiased;
                    fixed = fp_shift_right_jam128(fixed, shift);
                end
            end else begin
                logic [31:0] src32;
                src32 = fp32_operand(src);
                sign = src32[31];
                exp32 = src32[30:23];
                frac32 = src32[22:0];
                special = (exp32 == 8'hff);
                nan = special && (frac32 != 23'd0);
                if (exp32 == 8'd0) begin
                    exp_unbiased = -13'sd126;
                    sig_ext = {104'd0, frac32};
                end else begin
                    exp_unbiased = $signed({5'd0, exp32}) - 13'sd127;
                    sig_ext = {104'd0, 1'b1, frac32};
                end
                fixed = sig_ext << 7'd63;
                if (exp_unbiased >= 13'sd23) begin
                    shift = exp_unbiased - 13'sd23;
                    fixed = (shift >= 8'd41) ? 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff :
                                               (fixed << shift);
                end else begin
                    shift = 13'sd23 - exp_unbiased;
                    fixed = fp_shift_right_jam128(fixed, shift);
                end
            end

            if (special || nan) begin
                fp_to_int_cvt_data = fp_cvt_f2i_sat(nan ? 1'b0 : sign, is_unsigned, is_word);
            end else begin
                mag = fp_round_int_mag(fixed, sign, rm);
                if (fp_cvt_f2i_overflow(sign, is_unsigned, is_word, mag)) begin
                    fp_to_int_cvt_data = fp_cvt_f2i_sat(sign, is_unsigned, is_word);
                end else begin
                    fp_to_int_cvt_data = fp_cvt_f2i_pack(sign, is_unsigned, is_word, mag);
                end
            end
        end
    endfunction

    function automatic logic fp_to_int_cvt_invalid(input logic [31:0] inst,
                                                   input logic [63:0] src,
                                                   input logic [2:0] frm);
        logic want_double;
        logic is_unsigned;
        logic is_word;
        logic sign;
        logic [10:0] exp64;
        logic [7:0] exp32;
        logic [51:0] frac64;
        logic [22:0] frac32;
        logic nan;
        logic inf;
        logic signed [12:0] exp_unbiased;
        logic [127:0] fixed;
        logic [127:0] sig_ext;
        logic [7:0] shift;
        logic [63:0] mag;
        logic [2:0] rm;
        begin
            want_double = inst[25];
            is_unsigned = inst[20];
            is_word = !inst[21];
            rm = fp_effective_rm(inst[14:12], frm);
            if (want_double) begin
                sign = src[63];
                exp64 = src[62:52];
                frac64 = src[51:0];
                nan = (exp64 == 11'h7ff) && (frac64 != 52'd0);
                inf = (exp64 == 11'h7ff) && (frac64 == 52'd0);
                if (exp64 == 11'd0) begin
                    exp_unbiased = -13'sd1022;
                    sig_ext = {75'd0, frac64};
                end else begin
                    exp_unbiased = $signed({2'd0, exp64}) - 13'sd1023;
                    sig_ext = {75'd0, 1'b1, frac64};
                end
                fixed = sig_ext << 7'd63;
                if (exp_unbiased >= 13'sd52) begin
                    shift = exp_unbiased - 13'sd52;
                    fixed = (shift >= 8'd12) ? 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff :
                                               (fixed << shift);
                end else begin
                    shift = 13'sd52 - exp_unbiased;
                    fixed = fp_shift_right_jam128(fixed, shift);
                end
            end else begin
                logic [31:0] src32;
                src32 = fp32_operand(src);
                sign = src32[31];
                exp32 = src32[30:23];
                frac32 = src32[22:0];
                nan = (exp32 == 8'hff) && (frac32 != 23'd0);
                inf = (exp32 == 8'hff) && (frac32 == 23'd0);
                if (exp32 == 8'd0) begin
                    exp_unbiased = -13'sd126;
                    sig_ext = {104'd0, frac32};
                end else begin
                    exp_unbiased = $signed({5'd0, exp32}) - 13'sd127;
                    sig_ext = {104'd0, 1'b1, frac32};
                end
                fixed = sig_ext << 7'd63;
                if (exp_unbiased >= 13'sd23) begin
                    shift = exp_unbiased - 13'sd23;
                    fixed = (shift >= 8'd41) ? 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff :
                                               (fixed << shift);
                end else begin
                    shift = 13'sd23 - exp_unbiased;
                    fixed = fp_shift_right_jam128(fixed, shift);
                end
            end
            mag = fp_round_int_mag(fixed, sign, rm);
            fp_to_int_cvt_invalid = nan || inf ||
                                    fp_cvt_f2i_overflow(sign, is_unsigned, is_word, mag);
        end
    endfunction

    function automatic logic fp_to_int_cvt_inexact(input logic [31:0] inst,
                                                   input logic [63:0] src);
        logic want_double;
        logic special;
        logic [127:0] fixed;
        logic signed [12:0] exp_unbiased;
        logic [127:0] sig_ext;
        logic [7:0] shift;
        begin
            want_double = inst[25];
            if (want_double) begin
                special = (src[62:52] == 11'h7ff);
                if (src[62:52] == 11'd0) begin
                    exp_unbiased = -13'sd1022;
                    sig_ext = {75'd0, src[51:0]};
                end else begin
                    exp_unbiased = $signed({2'd0, src[62:52]}) - 13'sd1023;
                    sig_ext = {75'd0, 1'b1, src[51:0]};
                end
                fixed = sig_ext << 7'd63;
                if (exp_unbiased >= 13'sd52) begin
                    shift = exp_unbiased - 13'sd52;
                    fixed = (shift >= 8'd12) ? 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff :
                                               (fixed << shift);
                end else begin
                    shift = 13'sd52 - exp_unbiased;
                    fixed = fp_shift_right_jam128(fixed, shift);
                end
            end else begin
                logic [31:0] src32;
                src32 = fp32_operand(src);
                special = (src32[30:23] == 8'hff);
                if (src32[30:23] == 8'd0) begin
                    exp_unbiased = -13'sd126;
                    sig_ext = {104'd0, src32[22:0]};
                end else begin
                    exp_unbiased = $signed({5'd0, src32[30:23]}) - 13'sd127;
                    sig_ext = {104'd0, 1'b1, src32[22:0]};
                end
                fixed = sig_ext << 7'd63;
                if (exp_unbiased >= 13'sd23) begin
                    shift = exp_unbiased - 13'sd23;
                    fixed = (shift >= 8'd41) ? 128'hffff_ffff_ffff_ffff_ffff_ffff_ffff_ffff :
                                               (fixed << shift);
                end else begin
                    shift = 13'sd23 - exp_unbiased;
                    fixed = fp_shift_right_jam128(fixed, shift);
                end
            end
            fp_to_int_cvt_inexact = !special && (fixed[62:0] != 63'd0);
        end
    endfunction

    function automatic logic [63:0] fp_to_int_data(input logic [31:0] inst,
                                                   input logic [63:0] src,
                                                   input logic [2:0] frm);
        begin
            unique case (inst[31:25])
                7'b1110000: fp_to_int_data = {{32{src[31]}}, src[31:0]}; // FMV.X.W
                7'b1110001: fp_to_int_data = src;                        // FMV.X.D
                7'b1100000,
                7'b1100001: fp_to_int_data = fp_to_int_cvt_data(inst, src, frm);
                default:    fp_to_int_data = 64'd0;
            endcase
        end
    endfunction

    function automatic logic fp_round_increment(input logic [2:0] rm,
                                                input logic sign,
                                                input logic guard,
                                                input logic sticky,
                                                input logic lsb);
        logic any_discarded;
        begin
            any_discarded = guard || sticky;
            unique case (rm)
                3'b000: fp_round_increment = guard && (sticky || lsb); // RNE
                3'b001: fp_round_increment = 1'b0;                     // RTZ
                3'b010: fp_round_increment = sign && any_discarded;    // RDN
                3'b011: fp_round_increment = !sign && any_discarded;   // RUP
                3'b100: fp_round_increment = guard;                    // RMM
                default: fp_round_increment = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [63:0] fp_cvt_i2f_mag(input logic want_double,
                                                   input logic sign,
                                                   input logic [63:0] mag,
                                                   input logic [2:0] rm);
        logic [5:0] msb;
        logic [6:0] shift;
        logic [63:0] mant;
        logic [63:0] rem;
        logic guard;
        logic sticky;
        logic inc;
        logic [11:0] exp64;
        logic [8:0] exp32;
        logic [63:0] bits64;
        logic [31:0] bits32;
        begin
            if (mag == 64'd0) begin
                fp_cvt_i2f_mag = want_double ? {sign, 63'd0} : {32'hffff_ffff, sign, 31'd0};
            end else begin
                msb = u64_msb_index(mag);
                if (want_double) begin
                    exp64 = {6'd0, msb} + 12'd1023;
                    if (msb <= 6'd52) begin
                        mant = mag << (6'd52 - msb);
                    end else begin
                        shift = {1'b0, msb} - 7'd52;
                        mant = mag >> shift;
                        rem = mag & ((64'd1 << shift) - 64'd1);
                        guard = ((mag >> (shift - 7'd1)) & 64'd1) != 64'd0;
                        sticky = (shift > 7'd1) &&
                                 ((mag & ((64'd1 << (shift - 7'd1)) - 64'd1)) != 64'd0);
                        inc = fp_round_increment(rm, sign, guard, sticky, mant[0]);
                        if (inc) begin
                            mant = mant + 64'd1;
                            if (mant[53]) begin
                                mant = mant >> 1;
                                exp64 = exp64 + 12'd1;
                            end
                        end
                    end
                    bits64 = {sign, exp64[10:0], mant[51:0]};
                    fp_cvt_i2f_mag = bits64;
                end else begin
                    exp32 = {3'd0, msb} + 9'd127;
                    if (msb <= 6'd23) begin
                        mant = mag << (6'd23 - msb);
                    end else begin
                        shift = {1'b0, msb} - 7'd23;
                        mant = mag >> shift;
                        rem = mag & ((64'd1 << shift) - 64'd1);
                        guard = ((mag >> (shift - 7'd1)) & 64'd1) != 64'd0;
                        sticky = (shift > 7'd1) &&
                                 ((mag & ((64'd1 << (shift - 7'd1)) - 64'd1)) != 64'd0);
                        inc = fp_round_increment(rm, sign, guard, sticky, mant[0]);
                        if (inc) begin
                            mant = mant + 64'd1;
                            if (mant[24]) begin
                                mant = mant >> 1;
                                exp32 = exp32 + 9'd1;
                            end
                        end
                    end
                    bits32 = {sign, exp32[7:0], mant[22:0]};
                    fp_cvt_i2f_mag = {32'hffff_ffff, bits32};
                end
            end
        end
    endfunction

    function automatic logic [63:0] int_to_fp_cvt_data(input logic [31:0] inst,
                                                       input logic [63:0] src,
                                                       input logic [2:0] frm);
        logic signed [63:0] signed_src;
        logic sign;
        logic [63:0] mag;
        logic want_double;
        logic [2:0] rm;
        begin
            sign = 1'b0;
            mag = 64'd0;
            unique case (inst[24:20])
                5'd0: begin
                    signed_src = {{32{src[31]}}, src[31:0]};
                    sign = signed_src[63];
                    mag = sign ? (~src[63:0] + 64'd1) : src[63:0];
                    if (sign) begin
                        mag = (~{{32{src[31]}}, src[31:0]}) + 64'd1;
                    end else begin
                        mag = {32'd0, src[31:0]};
                    end
                end
                5'd1: begin
                    sign = 1'b0;
                    mag = {32'd0, src[31:0]};
                end
                5'd2: begin
                    sign = src[63];
                    mag = sign ? (~src + 64'd1) : src;
                end
                5'd3: begin
                    sign = 1'b0;
                    mag = src;
                end
                default: begin
                    sign = 1'b0;
                    mag = 64'd0;
                end
            endcase
            want_double = inst[25];
            rm = fp_effective_rm(inst[14:12], frm);
            int_to_fp_cvt_data = fp_cvt_i2f_mag(want_double, sign, mag, rm);
        end
    endfunction

    function automatic logic int_to_fp_cvt_inexact(input logic [31:0] inst,
                                                   input logic [63:0] src);
        logic sign;
        logic [63:0] mag;
        logic [5:0] msb;
        logic [6:0] mant_bits;
        logic [6:0] shift;
        begin
            sign = 1'b0;
            unique case (inst[24:20])
                5'd0: begin
                    sign = src[31];
                    mag = sign ? (~{{32{src[31]}}, src[31:0]} + 64'd1) :
                                 {32'd0, src[31:0]};
                end
                5'd1: mag = {32'd0, src[31:0]};
                5'd2: begin
                    sign = src[63];
                    mag = sign ? (~src + 64'd1) : src;
                end
                5'd3: mag = src;
                default: mag = 64'd0;
            endcase
            if (mag == 64'd0) begin
                int_to_fp_cvt_inexact = 1'b0;
            end else begin
                msb = u64_msb_index(mag);
                mant_bits = inst[25] ? 7'd52 : 7'd23;
                if ({1'b0, msb} <= mant_bits) begin
                    int_to_fp_cvt_inexact = 1'b0;
                end else begin
                    shift = {1'b0, msb} - mant_bits;
                    int_to_fp_cvt_inexact = (mag & ((64'd1 << shift) - 64'd1)) != 64'd0;
                end
            end
        end
    endfunction

    function automatic logic [63:0] int_to_fp_data(input logic [31:0] inst,
                                                   input logic [63:0] src,
                                                   input logic [2:0] frm);
        begin
            unique case (inst[31:25])
                7'b1111000: int_to_fp_data = {32'hffff_ffff, src[31:0]}; // FMV.W.X
                7'b1111001: int_to_fp_data = src;                        // FMV.D.X
                7'b1101000,
                7'b1101001: int_to_fp_data = int_to_fp_cvt_data(inst, src, frm);
                default:    int_to_fp_data = 64'd0;
            endcase
        end
    endfunction

    function automatic logic [31:0] fp64_to_fp32_bits(input logic [63:0] src,
                                                      input logic [2:0] rm);
        logic sign;
        logic [10:0] exp64;
        logic [51:0] frac64;
        logic signed [12:0] exp_unbiased;
        logic [52:0] sig64;
        logic [23:0] sig_main;
        logic [23:0] sub_sig;
        logic [7:0] shift;
        logic guard;
        logic sticky;
        logic inc;
        logic [7:0] exp32;
        begin
            sign = src[63];
            exp64 = src[62:52];
            frac64 = src[51:0];
            fp64_to_fp32_bits = {sign, 31'd0};

            if (fp64_nan(src)) begin
                fp64_to_fp32_bits = 32'h7fc0_0000;
            end else if (exp64 == 11'h7ff) begin
                fp64_to_fp32_bits = {sign, 8'hff, 23'd0};
            end else if ((exp64 == 11'd0) && (frac64 == 52'd0)) begin
                fp64_to_fp32_bits = {sign, 31'd0};
            end else begin
                exp_unbiased = (exp64 == 11'd0) ? -13'sd1022 :
                               ($signed({2'd0, exp64}) - 13'sd1023);
                sig64 = {(exp64 != 11'd0), frac64};

                if (exp_unbiased > 13'sd127) begin
                    fp64_to_fp32_bits = {sign, 8'hff, 23'd0};
                end else if (exp_unbiased < -13'sd149) begin
                    fp64_to_fp32_bits = {sign, 31'd0};
                end else if (exp_unbiased < -13'sd126) begin
                    shift = -($signed(exp_unbiased) + 13'sd97);
                    sub_sig = (shift >= 8'd53) ? 24'd0 : (sig64 >> shift);
                    guard = (shift != 8'd0) && (shift <= 8'd53) && sig64[shift - 8'd1];
                    sticky = (shift > 8'd1) && ((sig64 & ((53'd1 << (shift - 8'd1)) - 53'd1)) != 53'd0);
                    inc = fp_round_increment(rm, sign, guard, sticky, sub_sig[0]);
                    if (inc) begin
                        sub_sig = sub_sig + 24'd1;
                    end
                    if (sub_sig[23]) begin
                        fp64_to_fp32_bits = {sign, 8'd1, 23'd0};
                    end else begin
                        fp64_to_fp32_bits = {sign, 8'd0, sub_sig[22:0]};
                    end
                end else begin
                    sig_main = sig64[52:29];
                    guard = sig64[28];
                    sticky = (sig64[27:0] != 28'd0);
                    exp32 = exp_unbiased + 13'sd127;
                    inc = fp_round_increment(rm, sign, guard, sticky, sig_main[0]);
                    if (inc) begin
                        sig_main = sig_main + 24'd1;
                        if (sig_main[23]) begin
                            exp32 = exp32 + 8'd1;
                        end
                    end
                    if (exp32 >= 8'hff) begin
                        fp64_to_fp32_bits = {sign, 8'hff, 23'd0};
                    end else begin
                        fp64_to_fp32_bits = {sign, exp32, sig_main[22:0]};
                    end
                end
            end
        end
    endfunction

    function automatic logic [63:0] fp32_to_fp64_data(input logic [31:0] src);
        logic sign;
        logic [7:0] exp32;
        logic [22:0] frac32;
        logic signed [12:0] exp_unbiased;
        logic [52:0] sig64;
        logic [10:0] exp64;
        begin
            sign = src[31];
            exp32 = src[30:23];
            frac32 = src[22:0];
            if (fp32_nan(src)) begin
                fp32_to_fp64_data = 64'h7ff8_0000_0000_0000;
            end else if (exp32 == 8'hff) begin
                fp32_to_fp64_data = {sign, 11'h7ff, 52'd0};
            end else if ((exp32 == 8'd0) && (frac32 == 23'd0)) begin
                fp32_to_fp64_data = {sign, 63'd0};
            end else if (exp32 == 8'd0) begin
                sig64 = {30'd0, frac32};
                exp_unbiased = -13'sd126;
                for (int i = 0; i < 23; i++) begin
                    if (!sig64[22]) begin
                        sig64 = sig64 << 1;
                        exp_unbiased = exp_unbiased - 13'sd1;
                    end
                end
                exp64 = exp_unbiased + 13'sd1023;
                fp32_to_fp64_data = {sign, exp64, sig64[21:0], 30'd0};
            end else begin
                exp_unbiased = $signed({5'd0, exp32}) - 13'sd127;
                exp64 = exp_unbiased + 13'sd1023;
                fp32_to_fp64_data = {sign, exp64, frac32, 29'd0};
            end
        end
    endfunction

    function automatic logic [63:0] fp_cvt_fp_data(input logic [31:0] inst,
                                                   input logic [63:0] src,
                                                   input logic [2:0] frm);
        logic [2:0] rm;
        begin
            rm = fp_effective_rm(inst[14:12], frm);
            unique case (inst[31:25])
                7'b0100000: fp_cvt_fp_data = {32'hffff_ffff, fp64_to_fp32_bits(src, rm)}; // FCVT.S.D
                7'b0100001: fp_cvt_fp_data = fp32_to_fp64_data(fp32_operand(src));        // FCVT.D.S
                default:    fp_cvt_fp_data = 64'd0;
            endcase
        end
    endfunction

    function automatic logic fp_cvt_fp_invalid(input logic [31:0] inst,
                                               input logic [63:0] src);
        logic [31:0] src32;
        begin
            src32 = fp32_operand(src);
            unique case (inst[31:25])
                7'b0100000: fp_cvt_fp_invalid = fp64_snan(src);
                7'b0100001: fp_cvt_fp_invalid = fp32_snan(src32);
                default:    fp_cvt_fp_invalid = 1'b0;
            endcase
        end
    endfunction

    function automatic logic fp_cvt_fp_inexact(input logic [31:0] inst,
                                               input logic [63:0] src);
        logic [10:0] exp64;
        logic [51:0] frac64;
        logic signed [12:0] exp_unbiased;
        begin
            exp64 = src[62:52];
            frac64 = src[51:0];
            if (inst[31:25] != 7'b0100000) begin
                fp_cvt_fp_inexact = 1'b0;
            end else if (fp64_nan(src) || (exp64 == 11'h7ff)) begin
                fp_cvt_fp_inexact = 1'b0;
            end else if ((exp64 == 11'd0) && (frac64 == 52'd0)) begin
                fp_cvt_fp_inexact = 1'b0;
            end else begin
                exp_unbiased = (exp64 == 11'd0) ? -13'sd1022 :
                               ($signed({2'd0, exp64}) - 13'sd1023);
                fp_cvt_fp_inexact = (exp_unbiased > 13'sd127) ||
                                    (exp_unbiased < -13'sd149) ||
                                    ((exp_unbiased < -13'sd126) && (frac64 != 52'd0)) ||
                                    ((exp_unbiased >= -13'sd126) && (frac64[28:0] != 29'd0));
            end
        end
    endfunction

    function automatic logic [63:0] fp_sgnj_data(input logic [31:0] inst,
                                                 input logic [63:0] a,
                                                 input logic [63:0] b);
        logic sign_bit;
        logic [31:0] result32;
        logic [63:0] result64;
        begin
            if (inst[25]) begin
                unique case (inst[14:12])
                    3'b000: sign_bit = b[63];
                    3'b001: sign_bit = ~b[63];
                    3'b010: sign_bit = a[63] ^ b[63];
                    default: sign_bit = a[63];
                endcase
                result64 = {sign_bit, a[62:0]};
                fp_sgnj_data = result64;
            end else begin
                unique case (inst[14:12])
                    3'b000: sign_bit = b[31];
                    3'b001: sign_bit = ~b[31];
                    3'b010: sign_bit = a[31] ^ b[31];
                    default: sign_bit = a[31];
                endcase
                result32 = {sign_bit, a[30:0]};
                fp_sgnj_data = {32'hffff_ffff, result32};
            end
        end
    endfunction

    function automatic logic [31:0] fp32_operand(input logic [63:0] src);
        begin
            fp32_operand = (src[63:32] == 32'hffff_ffff) ? src[31:0] : 32'h7fc0_0000;
        end
    endfunction

    function automatic logic fp32_nan(input logic [31:0] v);
        fp32_nan = (v[30:23] == 8'hff) && (v[22:0] != 23'd0);
    endfunction

    function automatic logic fp32_snan(input logic [31:0] v);
        fp32_snan = fp32_nan(v) && !v[22];
    endfunction

    function automatic logic fp64_nan(input logic [63:0] v);
        fp64_nan = (v[62:52] == 11'h7ff) && (v[51:0] != 52'd0);
    endfunction

    function automatic logic fp64_snan(input logic [63:0] v);
        fp64_snan = fp64_nan(v) && !v[51];
    endfunction

    function automatic logic [9:0] fp32_class(input logic [31:0] v);
        logic sign;
        logic exp_zero;
        logic exp_ones;
        logic frac_zero;
        begin
            sign = v[31];
            exp_zero = (v[30:23] == 8'd0);
            exp_ones = (v[30:23] == 8'hff);
            frac_zero = (v[22:0] == 23'd0);
            fp32_class = 10'd0;
            if (exp_ones && frac_zero) begin
                fp32_class[sign ? 0 : 7] = 1'b1;
            end else if (exp_ones) begin
                fp32_class[v[22] ? 9 : 8] = 1'b1;
            end else if (exp_zero && frac_zero) begin
                fp32_class[sign ? 3 : 4] = 1'b1;
            end else if (exp_zero) begin
                fp32_class[sign ? 2 : 5] = 1'b1;
            end else begin
                fp32_class[sign ? 1 : 6] = 1'b1;
            end
        end
    endfunction

    function automatic logic [9:0] fp64_class(input logic [63:0] v);
        logic sign;
        logic exp_zero;
        logic exp_ones;
        logic frac_zero;
        begin
            sign = v[63];
            exp_zero = (v[62:52] == 11'd0);
            exp_ones = (v[62:52] == 11'h7ff);
            frac_zero = (v[51:0] == 52'd0);
            fp64_class = 10'd0;
            if (exp_ones && frac_zero) begin
                fp64_class[sign ? 0 : 7] = 1'b1;
            end else if (exp_ones) begin
                fp64_class[v[51] ? 9 : 8] = 1'b1;
            end else if (exp_zero && frac_zero) begin
                fp64_class[sign ? 3 : 4] = 1'b1;
            end else if (exp_zero) begin
                fp64_class[sign ? 2 : 5] = 1'b1;
            end else begin
                fp64_class[sign ? 1 : 6] = 1'b1;
            end
        end
    endfunction

    function automatic logic [63:0] fp_class_data(input logic [31:0] inst,
                                                  input logic [63:0] a);
        begin
            if (inst[25]) begin
                fp_class_data = {54'd0, fp64_class(a)};
            end else begin
                fp_class_data = {54'd0, fp32_class(fp32_operand(a))};
            end
        end
    endfunction

    function automatic logic fp32_eq(input logic [31:0] a,
                                     input logic [31:0] b);
        begin
            if (fp32_nan(a) || fp32_nan(b)) begin
                fp32_eq = 1'b0;
            end else if ((a[30:0] == 31'd0) && (b[30:0] == 31'd0)) begin
                fp32_eq = 1'b1;
            end else begin
                fp32_eq = (a == b);
            end
        end
    endfunction

    function automatic logic fp64_eq(input logic [63:0] a,
                                     input logic [63:0] b);
        begin
            if (fp64_nan(a) || fp64_nan(b)) begin
                fp64_eq = 1'b0;
            end else if ((a[62:0] == 63'd0) && (b[62:0] == 63'd0)) begin
                fp64_eq = 1'b1;
            end else begin
                fp64_eq = (a == b);
            end
        end
    endfunction

    function automatic logic fp32_lt(input logic [31:0] a,
                                     input logic [31:0] b);
        begin
            if (fp32_nan(a) || fp32_nan(b) || fp32_eq(a, b)) begin
                fp32_lt = 1'b0;
            end else if (a[31] != b[31]) begin
                fp32_lt = a[31];
            end else if (a[31]) begin
                fp32_lt = (a[30:0] > b[30:0]);
            end else begin
                fp32_lt = (a[30:0] < b[30:0]);
            end
        end
    endfunction

    function automatic logic fp64_lt(input logic [63:0] a,
                                     input logic [63:0] b);
        begin
            if (fp64_nan(a) || fp64_nan(b) || fp64_eq(a, b)) begin
                fp64_lt = 1'b0;
            end else if (a[63] != b[63]) begin
                fp64_lt = a[63];
            end else if (a[63]) begin
                fp64_lt = (a[62:0] > b[62:0]);
            end else begin
                fp64_lt = (a[62:0] < b[62:0]);
            end
        end
    endfunction

    function automatic logic [63:0] fp_cmp_data(input logic [31:0] inst,
                                                input logic [63:0] a,
                                                input logic [63:0] b);
        logic [31:0] a32;
        logic [31:0] b32;
        logic result;
        begin
            a32 = fp32_operand(a);
            b32 = fp32_operand(b);
            if (inst[25]) begin
                unique case (inst[14:12])
                    3'b000: result = fp64_lt(a, b) || fp64_eq(a, b); // FLE.D
                    3'b001: result = fp64_lt(a, b);                  // FLT.D
                    3'b010: result = fp64_eq(a, b);                  // FEQ.D
                    default: result = 1'b0;
                endcase
            end else begin
                unique case (inst[14:12])
                    3'b000: result = fp32_lt(a32, b32) || fp32_eq(a32, b32); // FLE.S
                    3'b001: result = fp32_lt(a32, b32);                      // FLT.S
                    3'b010: result = fp32_eq(a32, b32);                      // FEQ.S
                    default: result = 1'b0;
                endcase
            end
            fp_cmp_data = {63'd0, result};
        end
    endfunction

    function automatic logic [63:0] fp_shift_right_jam64(input logic [63:0] value,
                                                         input logic [6:0] shift);
        begin
            if (shift == 7'd0) begin
                fp_shift_right_jam64 = value;
            end else if (shift < 7'd64) begin
                fp_shift_right_jam64 = (value >> shift) |
                                       (((value & ((64'd1 << shift) - 64'd1)) != 64'd0) ?
                                        64'd1 : 64'd0);
            end else begin
                fp_shift_right_jam64 = (value != 64'd0) ? 64'd1 : 64'd0;
            end
        end
    endfunction

    function automatic logic [63:0] fp64_addsub_data(input logic [63:0] a,
                                                     input logic [63:0] b,
                                                     input logic sub,
                                                     input logic [2:0] rm);
        logic sign_a;
        logic sign_b;
        logic [10:0] exp_a_field;
        logic [10:0] exp_b_field;
        logic [51:0] frac_a;
        logic [51:0] frac_b;
        logic signed [12:0] exp_a;
        logic signed [12:0] exp_b;
        logic signed [12:0] exp_r;
        logic [63:0] sig_a;
        logic [63:0] sig_b;
        logic [63:0] sig_r;
        logic [6:0] shift;
        logic sign_r;
        logic inc;
        logic [10:0] exp_field;
        logic [51:0] frac_field;
        begin
            sign_a = a[63];
            sign_b = b[63] ^ sub;
            exp_a_field = a[62:52];
            exp_b_field = b[62:52];
            frac_a = a[51:0];
            frac_b = b[51:0];

            if (fp64_nan(a) || fp64_nan(b)) begin
                fp64_addsub_data = 64'h7ff8_0000_0000_0000;
            end else if ((exp_a_field == 11'h7ff) && (exp_b_field == 11'h7ff) &&
                         (sign_a != sign_b)) begin
                fp64_addsub_data = 64'h7ff8_0000_0000_0000;
            end else if (exp_a_field == 11'h7ff) begin
                fp64_addsub_data = {sign_a, 11'h7ff, 52'd0};
            end else if (exp_b_field == 11'h7ff) begin
                fp64_addsub_data = {sign_b, 11'h7ff, 52'd0};
            end else begin
                exp_a = (exp_a_field == 11'd0) ? -13'sd1022 :
                        ($signed({2'd0, exp_a_field}) - 13'sd1023);
                exp_b = (exp_b_field == 11'd0) ? -13'sd1022 :
                        ($signed({2'd0, exp_b_field}) - 13'sd1023);
                sig_a = {8'd0, (exp_a_field != 11'd0), frac_a, 3'd0};
                sig_b = {8'd0, (exp_b_field != 11'd0), frac_b, 3'd0};

                if (exp_a > exp_b) begin
                    shift = exp_a - exp_b;
                    sig_b = fp_shift_right_jam64(sig_b, shift);
                    exp_r = exp_a;
                end else if (exp_b > exp_a) begin
                    shift = exp_b - exp_a;
                    sig_a = fp_shift_right_jam64(sig_a, shift);
                    exp_r = exp_b;
                end else begin
                    exp_r = exp_a;
                end

                if (sign_a == sign_b) begin
                    sig_r = sig_a + sig_b;
                    sign_r = sign_a;
                    if (sig_r[56]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 13'sd1;
                    end
                end else begin
                    if (sig_a > sig_b) begin
                        sig_r = sig_a - sig_b;
                        sign_r = sign_a;
                    end else if (sig_b > sig_a) begin
                        sig_r = sig_b - sig_a;
                        sign_r = sign_b;
                    end else begin
                        sig_r = 64'd0;
                        sign_r = (rm == 3'b010);
                    end
                    for (int i = 0; i < 56; i++) begin
                        if ((sig_r != 64'd0) && !sig_r[55] && (exp_r > -13'sd1022)) begin
                            sig_r = sig_r << 1;
                            exp_r = exp_r - 13'sd1;
                        end
                    end
                end

                inc = fp_round_increment(rm, sign_r, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[56]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 13'sd1;
                    end
                end

                if (sig_r == 64'd0) begin
                    fp64_addsub_data = {sign_r, 63'd0};
                end else if (exp_r > 13'sd1023) begin
                    fp64_addsub_data = {sign_r, 11'h7ff, 52'd0};
                end else begin
                    exp_field = exp_r + 13'sd1023;
                    frac_field = sig_r[54:3];
                    fp64_addsub_data = {sign_r, exp_field, frac_field};
                end
            end
        end
    endfunction

    function automatic logic [31:0] fp32_addsub_bits(input logic [31:0] a,
                                                     input logic [31:0] b,
                                                     input logic sub,
                                                     input logic [2:0] rm);
        logic sign_a;
        logic sign_b;
        logic [7:0] exp_a_field;
        logic [7:0] exp_b_field;
        logic [22:0] frac_a;
        logic [22:0] frac_b;
        logic signed [9:0] exp_a;
        logic signed [9:0] exp_b;
        logic signed [9:0] exp_r;
        logic [63:0] sig_a;
        logic [63:0] sig_b;
        logic [63:0] sig_r;
        logic [6:0] shift;
        logic sign_r;
        logic inc;
        logic [7:0] exp_field;
        logic [22:0] frac_field;
        begin
            sign_a = a[31];
            sign_b = b[31] ^ sub;
            exp_a_field = a[30:23];
            exp_b_field = b[30:23];
            frac_a = a[22:0];
            frac_b = b[22:0];

            if (fp32_nan(a) || fp32_nan(b)) begin
                fp32_addsub_bits = 32'h7fc0_0000;
            end else if ((exp_a_field == 8'hff) && (exp_b_field == 8'hff) &&
                         (sign_a != sign_b)) begin
                fp32_addsub_bits = 32'h7fc0_0000;
            end else if (exp_a_field == 8'hff) begin
                fp32_addsub_bits = {sign_a, 8'hff, 23'd0};
            end else if (exp_b_field == 8'hff) begin
                fp32_addsub_bits = {sign_b, 8'hff, 23'd0};
            end else begin
                exp_a = (exp_a_field == 8'd0) ? -10'sd126 :
                        ($signed({2'd0, exp_a_field}) - 10'sd127);
                exp_b = (exp_b_field == 8'd0) ? -10'sd126 :
                        ($signed({2'd0, exp_b_field}) - 10'sd127);
                sig_a = {37'd0, (exp_a_field != 8'd0), frac_a, 3'd0};
                sig_b = {37'd0, (exp_b_field != 8'd0), frac_b, 3'd0};

                if (exp_a > exp_b) begin
                    shift = exp_a - exp_b;
                    sig_b = fp_shift_right_jam64(sig_b, shift);
                    exp_r = exp_a;
                end else if (exp_b > exp_a) begin
                    shift = exp_b - exp_a;
                    sig_a = fp_shift_right_jam64(sig_a, shift);
                    exp_r = exp_b;
                end else begin
                    exp_r = exp_a;
                end

                if (sign_a == sign_b) begin
                    sig_r = sig_a + sig_b;
                    sign_r = sign_a;
                    if (sig_r[27]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 10'sd1;
                    end
                end else begin
                    if (sig_a > sig_b) begin
                        sig_r = sig_a - sig_b;
                        sign_r = sign_a;
                    end else if (sig_b > sig_a) begin
                        sig_r = sig_b - sig_a;
                        sign_r = sign_b;
                    end else begin
                        sig_r = 64'd0;
                        sign_r = (rm == 3'b010);
                    end
                    for (int i = 0; i < 27; i++) begin
                        if ((sig_r != 64'd0) && !sig_r[26] && (exp_r > -10'sd126)) begin
                            sig_r = sig_r << 1;
                            exp_r = exp_r - 10'sd1;
                        end
                    end
                end

                inc = fp_round_increment(rm, sign_r, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[27]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 10'sd1;
                    end
                end

                if (sig_r == 64'd0) begin
                    fp32_addsub_bits = {sign_r, 31'd0};
                end else if (exp_r > 10'sd127) begin
                    fp32_addsub_bits = {sign_r, 8'hff, 23'd0};
                end else begin
                    exp_field = exp_r + 10'sd127;
                    frac_field = sig_r[25:3];
                    fp32_addsub_bits = {sign_r, exp_field, frac_field};
                end
            end
        end
    endfunction

    function automatic logic [63:0] fp_addsub_data(input logic [31:0] inst,
                                                   input logic [63:0] a,
                                                   input logic [63:0] b,
                                                   input logic [2:0] frm);
        logic [2:0] rm;
        begin
            rm = fp_effective_rm(inst[14:12], frm);
            if (inst[25]) begin
                fp_addsub_data = fp64_addsub_data(a, b, inst[27], rm);
            end else begin
                fp_addsub_data = {32'hffff_ffff,
                                  fp32_addsub_bits(fp32_operand(a), fp32_operand(b), inst[27], rm)};
            end
        end
    endfunction

    function automatic logic fp_addsub_invalid(input logic [31:0] inst,
                                               input logic [63:0] a,
                                               input logic [63:0] b);
        logic [31:0] a32;
        logic [31:0] b32;
        logic b_sign_eff;
        begin
            if (inst[25]) begin
                b_sign_eff = b[63] ^ inst[27];
                fp_addsub_invalid = fp64_snan(a) || fp64_snan(b) ||
                                    ((a[62:52] == 11'h7ff) && (a[51:0] == 52'd0) &&
                                     (b[62:52] == 11'h7ff) && (b[51:0] == 52'd0) &&
                                     (a[63] != b_sign_eff));
            end else begin
                a32 = fp32_operand(a);
                b32 = fp32_operand(b);
                b_sign_eff = b32[31] ^ inst[27];
                fp_addsub_invalid = fp32_snan(a32) || fp32_snan(b32) ||
                                    ((a32[30:23] == 8'hff) && (a32[22:0] == 23'd0) &&
                                     (b32[30:23] == 8'hff) && (b32[22:0] == 23'd0) &&
                                     (a32[31] != b_sign_eff));
            end
        end
    endfunction

    function automatic logic [63:0] fp64_mul_data(input logic [63:0] a,
                                                  input logic [63:0] b,
                                                  input logic [2:0] rm);
        logic sign_r;
        logic [10:0] exp_a_field;
        logic [10:0] exp_b_field;
        logic [51:0] frac_a;
        logic [51:0] frac_b;
        logic zero_a;
        logic zero_b;
        logic inf_a;
        logic inf_b;
        logic signed [12:0] exp_a;
        logic signed [12:0] exp_b;
        logic signed [12:0] exp_r;
        logic [52:0] sig_a;
        logic [52:0] sig_b;
        logic [105:0] prod;
        logic [52:0] sig_main;
        logic guard;
        logic sticky;
        logic [63:0] sig_r;
        logic inc;
        logic [10:0] exp_field;
        begin
            sign_r = a[63] ^ b[63];
            exp_a_field = a[62:52];
            exp_b_field = b[62:52];
            frac_a = a[51:0];
            frac_b = b[51:0];
            zero_a = (exp_a_field == 11'd0) && (frac_a == 52'd0);
            zero_b = (exp_b_field == 11'd0) && (frac_b == 52'd0);
            inf_a = (exp_a_field == 11'h7ff) && (frac_a == 52'd0);
            inf_b = (exp_b_field == 11'h7ff) && (frac_b == 52'd0);

            if (fp64_nan(a) || fp64_nan(b) || ((inf_a && zero_b) || (inf_b && zero_a))) begin
                fp64_mul_data = 64'h7ff8_0000_0000_0000;
            end else if (inf_a || inf_b) begin
                fp64_mul_data = {sign_r, 11'h7ff, 52'd0};
            end else if (zero_a || zero_b) begin
                fp64_mul_data = {sign_r, 63'd0};
            end else begin
                exp_a = (exp_a_field == 11'd0) ? -13'sd1022 :
                        ($signed({2'd0, exp_a_field}) - 13'sd1023);
                exp_b = (exp_b_field == 11'd0) ? -13'sd1022 :
                        ($signed({2'd0, exp_b_field}) - 13'sd1023);
                exp_r = exp_a + exp_b;
                sig_a = {(exp_a_field != 11'd0), frac_a};
                sig_b = {(exp_b_field != 11'd0), frac_b};
                prod = sig_a * sig_b;
                if (prod[105]) begin
                    sig_main = prod[105:53];
                    guard = prod[52];
                    sticky = (prod[51:0] != 52'd0);
                    exp_r = exp_r + 13'sd1;
                end else begin
                    sig_main = prod[104:52];
                    guard = prod[51];
                    sticky = (prod[50:0] != 51'd0);
                end
                sig_r = {8'd0, sig_main, guard, 1'b0, sticky};
                inc = fp_round_increment(rm, sign_r, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[56]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 13'sd1;
                    end
                end
                if (exp_r > 13'sd1023) begin
                    fp64_mul_data = {sign_r, 11'h7ff, 52'd0};
                end else if (exp_r < -13'sd1022) begin
                    fp64_mul_data = {sign_r, 63'd0};
                end else begin
                    exp_field = exp_r + 13'sd1023;
                    fp64_mul_data = {sign_r, exp_field, sig_r[54:3]};
                end
            end
        end
    endfunction

    function automatic logic [31:0] fp32_mul_bits(input logic [31:0] a,
                                                  input logic [31:0] b,
                                                  input logic [2:0] rm);
        logic sign_r;
        logic [7:0] exp_a_field;
        logic [7:0] exp_b_field;
        logic [22:0] frac_a;
        logic [22:0] frac_b;
        logic zero_a;
        logic zero_b;
        logic inf_a;
        logic inf_b;
        logic signed [9:0] exp_a;
        logic signed [9:0] exp_b;
        logic signed [9:0] exp_r;
        logic [23:0] sig_a;
        logic [23:0] sig_b;
        logic [47:0] prod;
        logic [23:0] sig_main;
        logic guard;
        logic sticky;
        logic [63:0] sig_r;
        logic inc;
        logic [7:0] exp_field;
        begin
            sign_r = a[31] ^ b[31];
            exp_a_field = a[30:23];
            exp_b_field = b[30:23];
            frac_a = a[22:0];
            frac_b = b[22:0];
            zero_a = (exp_a_field == 8'd0) && (frac_a == 23'd0);
            zero_b = (exp_b_field == 8'd0) && (frac_b == 23'd0);
            inf_a = (exp_a_field == 8'hff) && (frac_a == 23'd0);
            inf_b = (exp_b_field == 8'hff) && (frac_b == 23'd0);

            if (fp32_nan(a) || fp32_nan(b) || ((inf_a && zero_b) || (inf_b && zero_a))) begin
                fp32_mul_bits = 32'h7fc0_0000;
            end else if (inf_a || inf_b) begin
                fp32_mul_bits = {sign_r, 8'hff, 23'd0};
            end else if (zero_a || zero_b) begin
                fp32_mul_bits = {sign_r, 31'd0};
            end else begin
                exp_a = (exp_a_field == 8'd0) ? -10'sd126 :
                        ($signed({2'd0, exp_a_field}) - 10'sd127);
                exp_b = (exp_b_field == 8'd0) ? -10'sd126 :
                        ($signed({2'd0, exp_b_field}) - 10'sd127);
                exp_r = exp_a + exp_b;
                sig_a = {(exp_a_field != 8'd0), frac_a};
                sig_b = {(exp_b_field != 8'd0), frac_b};
                prod = sig_a * sig_b;
                if (prod[47]) begin
                    sig_main = prod[47:24];
                    guard = prod[23];
                    sticky = (prod[22:0] != 23'd0);
                    exp_r = exp_r + 10'sd1;
                end else begin
                    sig_main = prod[46:23];
                    guard = prod[22];
                    sticky = (prod[21:0] != 22'd0);
                end
                sig_r = {37'd0, sig_main, guard, 1'b0, sticky};
                inc = fp_round_increment(rm, sign_r, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[27]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 10'sd1;
                    end
                end
                if (exp_r > 10'sd127) begin
                    fp32_mul_bits = {sign_r, 8'hff, 23'd0};
                end else if (exp_r < -10'sd126) begin
                    fp32_mul_bits = {sign_r, 31'd0};
                end else begin
                    exp_field = exp_r + 10'sd127;
                    fp32_mul_bits = {sign_r, exp_field, sig_r[25:3]};
                end
            end
        end
    endfunction

    function automatic logic [63:0] fp_mul_data(input logic [31:0] inst,
                                                input logic [63:0] a,
                                                input logic [63:0] b,
                                                input logic [2:0] frm);
        logic [2:0] rm;
        begin
            rm = fp_effective_rm(inst[14:12], frm);
            if (inst[25]) begin
                fp_mul_data = fp64_mul_data(a, b, rm);
            end else begin
                fp_mul_data = {32'hffff_ffff, fp32_mul_bits(fp32_operand(a), fp32_operand(b), rm)};
            end
        end
    endfunction

    function automatic logic fp_mul_invalid(input logic [31:0] inst,
                                            input logic [63:0] a,
                                            input logic [63:0] b);
        logic [31:0] a32;
        logic [31:0] b32;
        logic zero_a;
        logic zero_b;
        logic inf_a;
        logic inf_b;
        begin
            if (inst[25]) begin
                zero_a = (a[62:0] == 63'd0);
                zero_b = (b[62:0] == 63'd0);
                inf_a = (a[62:52] == 11'h7ff) && (a[51:0] == 52'd0);
                inf_b = (b[62:52] == 11'h7ff) && (b[51:0] == 52'd0);
                fp_mul_invalid = fp64_snan(a) || fp64_snan(b) ||
                                 (inf_a && zero_b) || (inf_b && zero_a);
            end else begin
                a32 = fp32_operand(a);
                b32 = fp32_operand(b);
                zero_a = (a32[30:0] == 31'd0);
                zero_b = (b32[30:0] == 31'd0);
                inf_a = (a32[30:23] == 8'hff) && (a32[22:0] == 23'd0);
                inf_b = (b32[30:23] == 8'hff) && (b32[22:0] == 23'd0);
                fp_mul_invalid = fp32_snan(a32) || fp32_snan(b32) ||
                                 (inf_a && zero_b) || (inf_b && zero_a);
            end
        end
    endfunction

    function automatic logic [63:0] isqrt128(input logic [127:0] value);
        logic [127:0] rem;
        logic [127:0] trial;
        logic [127:0] root;
        logic [127:0] work;
        begin
            rem = 128'd0;
            trial = 128'd0;
            root = 128'd0;
            work = value;
            for (int i = 0; i < 64; i++) begin
                rem = {rem[125:0], work[127:126]};
                work = {work[125:0], 2'b00};
                root = root << 1;
                trial = (root << 1) | 128'd1;
                if (rem >= trial) begin
                    rem = rem - trial;
                    root = root | 128'd1;
                end
            end
            isqrt128 = root[63:0];
        end
    endfunction

    function automatic logic [63:0] fp64_div_data(input logic [63:0] a,
                                                  input logic [63:0] b,
                                                  input logic [2:0] rm);
        logic sign_r;
        logic [10:0] exp_a_field;
        logic [10:0] exp_b_field;
        logic [51:0] frac_a;
        logic [51:0] frac_b;
        logic zero_a;
        logic zero_b;
        logic inf_a;
        logic inf_b;
        logic signed [12:0] exp_a;
        logic signed [12:0] exp_b;
        logic signed [12:0] exp_r;
        logic [52:0] sig_a;
        logic [52:0] sig_b;
        logic [127:0] numerator;
        logic [127:0] divisor;
        logic [127:0] quot;
        logic [127:0] rem;
        logic [63:0] sig_r;
        logic inc;
        logic [10:0] exp_field;
        begin
            sign_r = a[63] ^ b[63];
            exp_a_field = a[62:52];
            exp_b_field = b[62:52];
            frac_a = a[51:0];
            frac_b = b[51:0];
            zero_a = (exp_a_field == 11'd0) && (frac_a == 52'd0);
            zero_b = (exp_b_field == 11'd0) && (frac_b == 52'd0);
            inf_a = (exp_a_field == 11'h7ff) && (frac_a == 52'd0);
            inf_b = (exp_b_field == 11'h7ff) && (frac_b == 52'd0);

            if (fp64_nan(a) || fp64_nan(b) || (zero_a && zero_b) || (inf_a && inf_b)) begin
                fp64_div_data = 64'h7ff8_0000_0000_0000;
            end else if (inf_a || zero_b) begin
                fp64_div_data = {sign_r, 11'h7ff, 52'd0};
            end else if (zero_a || inf_b) begin
                fp64_div_data = {sign_r, 63'd0};
            end else begin
                exp_a = (exp_a_field == 11'd0) ? -13'sd1022 :
                        ($signed({2'd0, exp_a_field}) - 13'sd1023);
                exp_b = (exp_b_field == 11'd0) ? -13'sd1022 :
                        ($signed({2'd0, exp_b_field}) - 13'sd1023);
                exp_r = exp_a - exp_b;
                sig_a = {(exp_a_field != 11'd0), frac_a};
                sig_b = {(exp_b_field != 11'd0), frac_b};
                numerator = {75'd0, sig_a} << 7'd55;
                divisor = {75'd0, sig_b};
                quot = numerator / divisor;
                rem = numerator - (quot * divisor);
                if (!quot[55]) begin
                    quot = quot << 1;
                    rem = rem << 1;
                    if (rem >= divisor) begin
                        rem = rem - divisor;
                        quot = quot | 128'd1;
                    end
                    exp_r = exp_r - 13'sd1;
                end
                sig_r = {8'd0, quot[55:3], quot[2], quot[1], (quot[0] | (rem != 128'd0))};
                inc = fp_round_increment(rm, sign_r, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[56]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 13'sd1;
                    end
                end
                if (exp_r > 13'sd1023) begin
                    fp64_div_data = {sign_r, 11'h7ff, 52'd0};
                end else if (exp_r < -13'sd1022) begin
                    fp64_div_data = {sign_r, 63'd0};
                end else begin
                    exp_field = exp_r + 13'sd1023;
                    fp64_div_data = {sign_r, exp_field, sig_r[54:3]};
                end
            end
        end
    endfunction

    function automatic logic [31:0] fp32_div_bits(input logic [31:0] a,
                                                  input logic [31:0] b,
                                                  input logic [2:0] rm);
        logic sign_r;
        logic [7:0] exp_a_field;
        logic [7:0] exp_b_field;
        logic [22:0] frac_a;
        logic [22:0] frac_b;
        logic zero_a;
        logic zero_b;
        logic inf_a;
        logic inf_b;
        logic signed [9:0] exp_a;
        logic signed [9:0] exp_b;
        logic signed [9:0] exp_r;
        logic [23:0] sig_a;
        logic [23:0] sig_b;
        logic [127:0] numerator;
        logic [127:0] divisor;
        logic [127:0] quot;
        logic [127:0] rem;
        logic [63:0] sig_r;
        logic inc;
        logic [7:0] exp_field;
        begin
            sign_r = a[31] ^ b[31];
            exp_a_field = a[30:23];
            exp_b_field = b[30:23];
            frac_a = a[22:0];
            frac_b = b[22:0];
            zero_a = (exp_a_field == 8'd0) && (frac_a == 23'd0);
            zero_b = (exp_b_field == 8'd0) && (frac_b == 23'd0);
            inf_a = (exp_a_field == 8'hff) && (frac_a == 23'd0);
            inf_b = (exp_b_field == 8'hff) && (frac_b == 23'd0);

            if (fp32_nan(a) || fp32_nan(b) || (zero_a && zero_b) || (inf_a && inf_b)) begin
                fp32_div_bits = 32'h7fc0_0000;
            end else if (inf_a || zero_b) begin
                fp32_div_bits = {sign_r, 8'hff, 23'd0};
            end else if (zero_a || inf_b) begin
                fp32_div_bits = {sign_r, 31'd0};
            end else begin
                exp_a = (exp_a_field == 8'd0) ? -10'sd126 :
                        ($signed({2'd0, exp_a_field}) - 10'sd127);
                exp_b = (exp_b_field == 8'd0) ? -10'sd126 :
                        ($signed({2'd0, exp_b_field}) - 10'sd127);
                exp_r = exp_a - exp_b;
                sig_a = {(exp_a_field != 8'd0), frac_a};
                sig_b = {(exp_b_field != 8'd0), frac_b};
                numerator = {104'd0, sig_a} << 6'd26;
                divisor = {104'd0, sig_b};
                quot = numerator / divisor;
                rem = numerator - (quot * divisor);
                if (!quot[26]) begin
                    quot = quot << 1;
                    rem = rem << 1;
                    if (rem >= divisor) begin
                        rem = rem - divisor;
                        quot = quot | 128'd1;
                    end
                    exp_r = exp_r - 10'sd1;
                end
                sig_r = {37'd0, quot[26:3], quot[2], quot[1], (quot[0] | (rem != 128'd0))};
                inc = fp_round_increment(rm, sign_r, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[27]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 10'sd1;
                    end
                end
                if (exp_r > 10'sd127) begin
                    fp32_div_bits = {sign_r, 8'hff, 23'd0};
                end else if (exp_r < -10'sd126) begin
                    fp32_div_bits = {sign_r, 31'd0};
                end else begin
                    exp_field = exp_r + 10'sd127;
                    fp32_div_bits = {sign_r, exp_field, sig_r[25:3]};
                end
            end
        end
    endfunction

    function automatic logic [63:0] fp64_sqrt_data(input logic [63:0] a,
                                                   input logic [2:0] rm);
        logic sign;
        logic [10:0] exp_field_in;
        logic [51:0] frac;
        logic zero;
        logic inf;
        logic signed [12:0] exp_unbiased;
        logic signed [12:0] exp_r;
        logic [52:0] sig;
        logic [127:0] radicand;
        logic [63:0] root;
        logic [127:0] root_sq;
        logic [63:0] sig_r;
        logic inc;
        logic [10:0] exp_field;
        begin
            sign = a[63];
            exp_field_in = a[62:52];
            frac = a[51:0];
            zero = (exp_field_in == 11'd0) && (frac == 52'd0);
            inf = (exp_field_in == 11'h7ff) && (frac == 52'd0);

            if (fp64_nan(a) || (sign && !zero)) begin
                fp64_sqrt_data = 64'h7ff8_0000_0000_0000;
            end else if (zero) begin
                fp64_sqrt_data = a;
            end else if (inf) begin
                fp64_sqrt_data = a;
            end else begin
                exp_unbiased = (exp_field_in == 11'd0) ? -13'sd1022 :
                               ($signed({2'd0, exp_field_in}) - 13'sd1023);
                exp_r = exp_unbiased >>> 1;
                sig = {(exp_field_in != 11'd0), frac};
                radicand = ({75'd0, sig} << 7'd58);
                if (exp_unbiased[0]) begin
                    radicand = radicand << 1;
                end
                root = isqrt128(radicand);
                root_sq = {64'd0, root} * {64'd0, root};
                sig_r = {8'd0, root[55:3], root[2], root[1], (root[0] | (root_sq != radicand))};
                inc = fp_round_increment(rm, sign, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[56]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 13'sd1;
                    end
                end
                exp_field = exp_r + 13'sd1023;
                fp64_sqrt_data = {sign, exp_field, sig_r[54:3]};
            end
        end
    endfunction

    function automatic logic [31:0] fp32_sqrt_bits(input logic [31:0] a,
                                                   input logic [2:0] rm);
        logic sign;
        logic [7:0] exp_field_in;
        logic [22:0] frac;
        logic zero;
        logic inf;
        logic signed [9:0] exp_unbiased;
        logic signed [9:0] exp_r;
        logic [23:0] sig;
        logic [127:0] radicand;
        logic [63:0] root;
        logic [127:0] root_sq;
        logic [63:0] sig_r;
        logic inc;
        logic [7:0] exp_field;
        begin
            sign = a[31];
            exp_field_in = a[30:23];
            frac = a[22:0];
            zero = (exp_field_in == 8'd0) && (frac == 23'd0);
            inf = (exp_field_in == 8'hff) && (frac == 23'd0);

            if (fp32_nan(a) || (sign && !zero)) begin
                fp32_sqrt_bits = 32'h7fc0_0000;
            end else if (zero) begin
                fp32_sqrt_bits = a;
            end else if (inf) begin
                fp32_sqrt_bits = a;
            end else begin
                exp_unbiased = (exp_field_in == 8'd0) ? -10'sd126 :
                               ($signed({2'd0, exp_field_in}) - 10'sd127);
                exp_r = exp_unbiased >>> 1;
                sig = {(exp_field_in != 8'd0), frac};
                radicand = ({104'd0, sig} << 6'd29);
                if (exp_unbiased[0]) begin
                    radicand = radicand << 1;
                end
                root = isqrt128(radicand);
                root_sq = {64'd0, root} * {64'd0, root};
                sig_r = {37'd0, root[26:3], root[2], root[1], (root[0] | (root_sq != radicand))};
                inc = fp_round_increment(rm, sign, sig_r[2], (sig_r[1:0] != 2'd0), sig_r[3]);
                if (inc) begin
                    sig_r = sig_r + 64'd8;
                    if (sig_r[27]) begin
                        sig_r = fp_shift_right_jam64(sig_r, 7'd1);
                        exp_r = exp_r + 10'sd1;
                    end
                end
                exp_field = exp_r + 10'sd127;
                fp32_sqrt_bits = {sign, exp_field, sig_r[25:3]};
            end
        end
    endfunction

    function automatic logic [63:0] fp_divsqrt_data(input logic [31:0] inst,
                                                    input logic [63:0] a,
                                                    input logic [63:0] b,
                                                    input logic [2:0] frm);
        logic [2:0] rm;
        begin
            rm = fp_effective_rm(inst[14:12], frm);
            unique case (inst[31:25])
                7'b0001100: fp_divsqrt_data = {32'hffff_ffff, fp32_div_bits(fp32_operand(a), fp32_operand(b), rm)};
                7'b0001101: fp_divsqrt_data = fp64_div_data(a, b, rm);
                7'b0101100: fp_divsqrt_data = {32'hffff_ffff, fp32_sqrt_bits(fp32_operand(a), rm)};
                7'b0101101: fp_divsqrt_data = fp64_sqrt_data(a, rm);
                default:    fp_divsqrt_data = 64'd0;
            endcase
        end
    endfunction

    function automatic logic fp_divsqrt_invalid(input logic [31:0] inst,
                                                input logic [63:0] a,
                                                input logic [63:0] b);
        logic [31:0] a32;
        logic [31:0] b32;
        logic zero_a;
        logic zero_b;
        logic inf_a;
        logic inf_b;
        begin
            a32 = fp32_operand(a);
            b32 = fp32_operand(b);
            unique case (inst[31:25])
                7'b0001101: begin
                    zero_a = (a[62:0] == 63'd0);
                    zero_b = (b[62:0] == 63'd0);
                    inf_a = (a[62:52] == 11'h7ff) && (a[51:0] == 52'd0);
                    inf_b = (b[62:52] == 11'h7ff) && (b[51:0] == 52'd0);
                    fp_divsqrt_invalid = fp64_snan(a) || fp64_snan(b) ||
                                         (zero_a && zero_b) || (inf_a && inf_b);
                end
                7'b0001100: begin
                    zero_a = (a32[30:0] == 31'd0);
                    zero_b = (b32[30:0] == 31'd0);
                    inf_a = (a32[30:23] == 8'hff) && (a32[22:0] == 23'd0);
                    inf_b = (b32[30:23] == 8'hff) && (b32[22:0] == 23'd0);
                    fp_divsqrt_invalid = fp32_snan(a32) || fp32_snan(b32) ||
                                         (zero_a && zero_b) || (inf_a && inf_b);
                end
                7'b0101101: fp_divsqrt_invalid = fp64_snan(a) || (a[63] && (a[62:0] != 63'd0));
                7'b0101100: fp_divsqrt_invalid = fp32_snan(a32) || (a32[31] && (a32[30:0] != 31'd0));
                default:    fp_divsqrt_invalid = 1'b0;
            endcase
        end
    endfunction

    function automatic logic fp_div_by_zero(input logic [31:0] inst,
                                            input logic [63:0] a,
                                            input logic [63:0] b);
        logic [31:0] a32;
        logic [31:0] b32;
        begin
            a32 = fp32_operand(a);
            b32 = fp32_operand(b);
            if (inst[31:25] == 7'b0001101) begin
                fp_div_by_zero = (a[62:52] != 11'h7ff) && (a[62:0] != 63'd0) &&
                                 (b[62:0] == 63'd0);
            end else if (inst[31:25] == 7'b0001100) begin
                fp_div_by_zero = (a32[30:23] != 8'hff) && (a32[30:0] != 31'd0) &&
                                 (b32[30:0] == 31'd0);
            end else begin
                fp_div_by_zero = 1'b0;
            end
        end
    endfunction

    function automatic logic [63:0] fp_neg_data(input logic want_double,
                                                input logic [63:0] src);
        begin
            if (want_double) begin
                fp_neg_data = {~src[63], src[62:0]};
            end else begin
                fp_neg_data = {32'hffff_ffff, ~src[31], src[30:0]};
            end
        end
    endfunction

    function automatic logic fma_neg_product(input logic [6:0] opcode);
        fma_neg_product = (opcode == OPCODE64_NMSUB) || (opcode == OPCODE64_NMADD);
    endfunction

    function automatic logic fma_sub_addend(input logic [6:0] opcode);
        fma_sub_addend = (opcode == OPCODE64_MSUB) || (opcode == OPCODE64_NMADD);
    endfunction

    function automatic logic [63:0] fp_fma_data(input logic [31:0] inst,
                                                input logic [63:0] a,
                                                input logic [63:0] b,
                                                input logic [63:0] c,
                                                input logic [2:0] frm);
        logic want_double;
        logic [63:0] prod;
        logic [31:0] add_inst;
        begin
            want_double = inst[25];
            prod = fp_mul_data(inst, a, b, frm);
            if (fma_neg_product(inst[6:0])) begin
                prod = fp_neg_data(want_double, prod);
            end
            add_inst = inst;
            add_inst[27] = fma_sub_addend(inst[6:0]);
            fp_fma_data = fp_addsub_data(add_inst, prod, c, frm);
        end
    endfunction

    function automatic logic fp_fma_invalid(input logic [31:0] inst,
                                            input logic [63:0] a,
                                            input logic [63:0] b,
                                            input logic [63:0] c);
        logic want_double;
        logic prod_neg;
        logic addend_sub;
        logic prod_sign;
        logic addend_sign;
        logic prod_inf;
        logic addend_inf;
        logic mul_invalid;
        logic [31:0] a32;
        logic [31:0] b32;
        logic [31:0] c32;
        begin
            want_double = inst[25];
            prod_neg = fma_neg_product(inst[6:0]);
            addend_sub = fma_sub_addend(inst[6:0]);
            if (want_double) begin
                prod_sign = a[63] ^ b[63] ^ prod_neg;
                addend_sign = c[63] ^ addend_sub;
                prod_inf = ((a[62:52] == 11'h7ff) && (a[51:0] == 52'd0)) ||
                           ((b[62:52] == 11'h7ff) && (b[51:0] == 52'd0));
                addend_inf = (c[62:52] == 11'h7ff) && (c[51:0] == 52'd0);
                mul_invalid = fp64_snan(a) || fp64_snan(b) ||
                              (((a[62:52] == 11'h7ff) && (a[51:0] == 52'd0) &&
                                (b[62:0] == 63'd0)) ||
                               ((b[62:52] == 11'h7ff) && (b[51:0] == 52'd0) &&
                                (a[62:0] == 63'd0)));
                fp_fma_invalid = mul_invalid || fp64_snan(c) ||
                                 (prod_inf && addend_inf && (prod_sign != addend_sign));
            end else begin
                a32 = fp32_operand(a);
                b32 = fp32_operand(b);
                c32 = fp32_operand(c);
                prod_sign = a32[31] ^ b32[31] ^ prod_neg;
                addend_sign = c32[31] ^ addend_sub;
                prod_inf = ((a32[30:23] == 8'hff) && (a32[22:0] == 23'd0)) ||
                           ((b32[30:23] == 8'hff) && (b32[22:0] == 23'd0));
                addend_inf = (c32[30:23] == 8'hff) && (c32[22:0] == 23'd0);
                mul_invalid = fp32_snan(a32) || fp32_snan(b32) ||
                              (((a32[30:23] == 8'hff) && (a32[22:0] == 23'd0) &&
                                (b32[30:0] == 31'd0)) ||
                               ((b32[30:23] == 8'hff) && (b32[22:0] == 23'd0) &&
                                (a32[30:0] == 31'd0)));
                fp_fma_invalid = mul_invalid || fp32_snan(c32) ||
                                 (prod_inf && addend_inf && (prod_sign != addend_sign));
            end
        end
    endfunction

    function automatic logic [63:0] fp_minmax_data(input logic [31:0] inst,
                                                   input logic [63:0] a,
                                                   input logic [63:0] b);
        logic [31:0] a32;
        logic [31:0] b32;
        logic [31:0] r32;
        logic [63:0] r64;
        begin
            a32 = fp32_operand(a);
            b32 = fp32_operand(b);
            if (inst[25]) begin
                if (fp64_nan(a) && fp64_nan(b)) begin
                    r64 = 64'h7ff8_0000_0000_0000;
                end else if (fp64_nan(a)) begin
                    r64 = b;
                end else if (fp64_nan(b)) begin
                    r64 = a;
                end else if ((a[62:0] == 63'd0) && (b[62:0] == 63'd0)) begin
                    r64 = (inst[14:12] == 3'b000) ? {a[63] | b[63], 63'd0} :
                                                     {a[63] & b[63], 63'd0};
                end else if (fp64_lt(a, b)) begin
                    r64 = (inst[14:12] == 3'b000) ? a : b;
                end else begin
                    r64 = (inst[14:12] == 3'b000) ? b : a;
                end
                fp_minmax_data = r64;
            end else begin
                if (fp32_nan(a32) && fp32_nan(b32)) begin
                    r32 = 32'h7fc0_0000;
                end else if (fp32_nan(a32)) begin
                    r32 = b32;
                end else if (fp32_nan(b32)) begin
                    r32 = a32;
                end else if ((a32[30:0] == 31'd0) && (b32[30:0] == 31'd0)) begin
                    r32 = (inst[14:12] == 3'b000) ? {a32[31] | b32[31], 31'd0} :
                                                    {a32[31] & b32[31], 31'd0};
                end else if (fp32_lt(a32, b32)) begin
                    r32 = (inst[14:12] == 3'b000) ? a32 : b32;
                end else begin
                    r32 = (inst[14:12] == 3'b000) ? b32 : a32;
                end
                fp_minmax_data = {32'hffff_ffff, r32};
            end
        end
    endfunction

    function automatic logic [4:0] fp_fflags_data(input logic [31:0] inst,
                                                  input logic [63:0] a,
                                                  input logic [63:0] b,
                                                  input logic [63:0] c,
                                                  input logic [63:0] int_src);
        logic [31:0] a32;
        logic [31:0] b32;
        logic invalid;
        logic divide_by_zero;
        logic inexact;
        begin
            a32 = fp32_operand(a);
            b32 = fp32_operand(b);
            invalid = 1'b0;
            divide_by_zero = 1'b0;
            inexact = 1'b0;
            if ((inst[31:25] == 7'b1010000) || (inst[31:25] == 7'b1010001)) begin
                if (inst[25]) begin
                    invalid = (inst[14:12] == 3'b010) ? (fp64_snan(a) || fp64_snan(b)) :
                                                        (fp64_nan(a) || fp64_nan(b));
                end else begin
                    invalid = (inst[14:12] == 3'b010) ? (fp32_snan(a32) || fp32_snan(b32)) :
                                                        (fp32_nan(a32) || fp32_nan(b32));
                end
            end else if (((inst[31:25] == 7'b0000000) || (inst[31:25] == 7'b0000001) ||
                          (inst[31:25] == 7'b0000100) || (inst[31:25] == 7'b0000101))) begin
                invalid = fp_addsub_invalid(inst, a, b);
            end else if ((inst[31:25] == 7'b0001000) || (inst[31:25] == 7'b0001001)) begin
                invalid = fp_mul_invalid(inst, a, b);
            end else if ((inst[6:0] == OPCODE64_MADD) || (inst[6:0] == OPCODE64_MSUB) ||
                         (inst[6:0] == OPCODE64_NMSUB) || (inst[6:0] == OPCODE64_NMADD)) begin
                invalid = fp_fma_invalid(inst, a, b, c);
            end else if ((inst[31:25] == 7'b0001100) || (inst[31:25] == 7'b0001101) ||
                         (inst[31:25] == 7'b0101100) || (inst[31:25] == 7'b0101101)) begin
                invalid = fp_divsqrt_invalid(inst, a, b);
                divide_by_zero = !invalid && fp_div_by_zero(inst, a, b);
            end else if ((inst[31:25] == 7'b0010100) || (inst[31:25] == 7'b0010101)) begin
                invalid = inst[25] ? (fp64_snan(a) || fp64_snan(b)) :
                                     (fp32_snan(a32) || fp32_snan(b32));
            end else if (((inst[31:25] == 7'b1101000) || (inst[31:25] == 7'b1101001)) &&
                         (inst[24:20] <= 5'd3)) begin
                inexact = int_to_fp_cvt_inexact(inst, int_src);
            end else if (((inst[31:25] == 7'b1100000) || (inst[31:25] == 7'b1100001)) &&
                         (inst[24:20] <= 5'd3)) begin
                invalid = fp_to_int_cvt_invalid(inst, a, csr_frm);
                inexact = !invalid && fp_to_int_cvt_inexact(inst, a);
            end else if (((inst[31:25] == 7'b0100000) && (inst[24:20] == 5'd1)) ||
                         ((inst[31:25] == 7'b0100001) && (inst[24:20] == 5'd0))) begin
                invalid = fp_cvt_fp_invalid(inst, a);
                inexact = !invalid && fp_cvt_fp_inexact(inst, a);
            end
            fp_fflags_data = (invalid ? 5'b10000 : 5'd0) |
                             (divide_by_zero ? 5'b01000 : 5'd0) |
                             (inexact ? 5'b00001 : 5'd0);
        end
    endfunction

    function automatic logic sv39_canonical(input logic [63:0] vaddr);
        begin
            sv39_canonical = (vaddr[63:39] == {25{vaddr[38]}});
        end
    endfunction

    function automatic logic [31:0] sv39_pte_addr(input logic [63:0] root_ppn,
                                                  input logic [63:0] vaddr,
                                                  input logic [1:0] level);
        logic [8:0] vpn;
        begin
            case (level)
                2'd2: vpn = vaddr[38:30];
                2'd1: vpn = vaddr[29:21];
                default: vpn = vaddr[20:12];
            endcase
            sv39_pte_addr = ({root_ppn[19:0], 12'd0} + {20'd0, vpn, 3'd0});
        end
    endfunction

    function automatic logic sv39_pte_valid(input logic [63:0] pte);
        begin
            sv39_pte_valid = pte[0] && !(pte[2] && !pte[1]);
        end
    endfunction

    function automatic logic sv39_pte_leaf(input logic [63:0] pte);
        begin
            sv39_pte_leaf = pte[1] || pte[3];
        end
    endfunction

    function automatic logic sv39_superpage_aligned(input logic [63:0] pte,
                                                    input logic [1:0] level);
        begin
            case (level)
                2'd2: sv39_superpage_aligned = (pte[27:10] == 18'd0);
                2'd1: sv39_superpage_aligned = (pte[18:10] == 9'd0);
                default: sv39_superpage_aligned = 1'b1;
            endcase
        end
    endfunction

    function automatic logic sv39_access_ok(input logic [63:0] pte,
                                            priv_mode_t priv,
                                            input logic is_fetch,
                                            input logic is_store,
                                            input logic [63:0] mstatus);
        logic r_ok;
        logic w_ok;
        logic x_ok;
        logic u_ok;
        logic a_ok;
        logic d_ok;
        begin
            r_ok = pte[1] || (mstatus[19] && pte[3]);
            w_ok = pte[2];
            x_ok = pte[3];
            u_ok = pte[4];
            a_ok = pte[6];
            d_ok = pte[7];

            sv39_access_ok = a_ok;
            if (sv39_access_ok) begin
                if (is_fetch) begin
                    sv39_access_ok = x_ok;
                end else if (is_store) begin
                    sv39_access_ok = w_ok && d_ok;
                end else begin
                    sv39_access_ok = r_ok;
                end
            end

            if (sv39_access_ok) begin
                if (priv == PRIV_U) begin
                    sv39_access_ok = u_ok;
                end else if (priv == PRIV_S && u_ok && (is_fetch || !mstatus[18])) begin
                    sv39_access_ok = 1'b0;
                end
            end
        end
    endfunction

    function automatic logic [31:0] sv39_leaf_paddr(input logic [63:0] pte,
                                                    input logic [63:0] vaddr,
                                                    input logic [1:0] level);
        begin
            case (level)
                2'd2: sv39_leaf_paddr = {pte[53:28], vaddr[29:0]};
                2'd1: sv39_leaf_paddr = {pte[53:19], vaddr[20:0]};
                default: sv39_leaf_paddr = {pte[53:10], vaddr[11:0]};
            endcase
        end
    endfunction

    function automatic logic tlb_tag_match(input logic [63:0] vaddr,
                                           input logic [26:0] vpn_tag,
                                           input logic [1:0] level);
        begin
            case (level)
                2'd2: tlb_tag_match = (vaddr[38:30] == vpn_tag[26:18]);
                2'd1: tlb_tag_match = (vaddr[38:21] == vpn_tag[26:9]);
                default: tlb_tag_match = (vaddr[38:12] == vpn_tag);
            endcase
        end
    endfunction

    function automatic logic [63:0] ptw_fault_cause(input logic is_fetch,
                                                    input logic is_store);
        begin
            ptw_fault_cause = is_fetch ? MCAUSE_INST_PAGE_FAULT :
                              is_store ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
        end
    endfunction

    function automatic logic amo_supported_inst(input logic [2:0] f3,
                                                input logic [4:0] f5,
                                                input logic [4:0] rs2_reg);
        logic width_ok;
        begin
            width_ok = (f3 == 3'b010) || (f3 == 3'b011);
            unique case (f5)
                5'b00000,
                5'b00001,
                5'b00100,
                5'b01000,
                5'b01100,
                5'b10000,
                5'b10100,
                5'b11000,
                5'b11100,
                5'b00011: amo_supported_inst = width_ok;
                5'b00010: amo_supported_inst = width_ok && (rs2_reg == 5'd0);
                default:  amo_supported_inst = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [31:0] amo_result32(input logic [4:0] f5,
                                                 input logic [31:0] old_word,
                                                 input logic [31:0] rs2_word);
        begin
            unique case (f5)
                5'b00000: amo_result32 = old_word + rs2_word;
                5'b00001: amo_result32 = rs2_word;
                5'b00100: amo_result32 = old_word ^ rs2_word;
                5'b01000: amo_result32 = old_word | rs2_word;
                5'b01100: amo_result32 = old_word & rs2_word;
                5'b10000: amo_result32 = ($signed(old_word) < $signed(rs2_word)) ? old_word : rs2_word;
                5'b10100: amo_result32 = ($signed(old_word) > $signed(rs2_word)) ? old_word : rs2_word;
                5'b11000: amo_result32 = (old_word < rs2_word) ? old_word : rs2_word;
                5'b11100: amo_result32 = (old_word > rs2_word) ? old_word : rs2_word;
                default:  amo_result32 = old_word;
            endcase
        end
    endfunction

    function automatic logic [63:0] amo_result64(input logic [4:0] f5,
                                                 input logic [63:0] old_word,
                                                 input logic [63:0] rs2_word);
        begin
            unique case (f5)
                5'b00000: amo_result64 = old_word + rs2_word;
                5'b00001: amo_result64 = rs2_word;
                5'b00100: amo_result64 = old_word ^ rs2_word;
                5'b01000: amo_result64 = old_word | rs2_word;
                5'b01100: amo_result64 = old_word & rs2_word;
                5'b10000: amo_result64 = ($signed(old_word) < $signed(rs2_word)) ? old_word : rs2_word;
                5'b10100: amo_result64 = ($signed(old_word) > $signed(rs2_word)) ? old_word : rs2_word;
                5'b11000: amo_result64 = (old_word < rs2_word) ? old_word : rs2_word;
                5'b11100: amo_result64 = (old_word > rs2_word) ? old_word : rs2_word;
                default:  amo_result64 = old_word;
            endcase
        end
    endfunction

    function automatic logic [63:0] amo_read_result(input logic width_w,
                                                    input logic [2:0] off,
                                                    input logic [63:0] old_data);
        logic [63:0] shifted;
        begin
            shifted = old_data >> {off, 3'b000};
            amo_read_result = width_w ? sext32(shifted[31:0]) : old_data;
        end
    endfunction

    function automatic logic [63:0] amo_store_value(input logic [4:0] f5,
                                                    input logic width_w,
                                                    input logic [2:0] off,
                                                    input logic [63:0] old_data,
                                                    input logic [63:0] rs2_word);
        logic [63:0] shifted;
        logic [31:0] result32;
        logic [63:0] result64;
        begin
            if (width_w) begin
                shifted = old_data >> {off, 3'b000};
                result32 = amo_result32(f5, shifted[31:0], rs2_word[31:0]);
                amo_store_value = store_data(3'b010, off, {32'd0, result32});
            end else begin
                result64 = amo_result64(f5, old_data, rs2_word);
                amo_store_value = result64;
            end
        end
    endfunction

    function automatic logic [7:0] amo_store_strobe(input logic width_w,
                                                    input logic [2:0] off);
        begin
            amo_store_strobe = width_w ? store_strobe(3'b010, off) : 8'hff;
        end
    endfunction

    function automatic logic [63:0] word_result(input logic [31:0] inst,
                                                input logic [63:0] a,
                                                input logic [63:0] b);
        logic [31:0] imm32;
        begin
            imm32 = {{20{inst[31]}}, inst[31:20]};
            unique case (inst[6:0])
                OPCODE64_OP_IMM_32: begin
                    unique case (inst[14:12])
                        3'b000: word_result = sext32(a[31:0] + imm32);
                        3'b001: word_result = sext32(a[31:0] << inst[24:20]);
                        3'b101: begin
                            if (inst[30]) begin
                                word_result = sext32($signed(a[31:0]) >>> inst[24:20]);
                            end else begin
                                word_result = sext32(a[31:0] >> inst[24:20]);
                            end
                        end
                        default: word_result = 64'd0;
                    endcase
                end
                OPCODE64_OP_32: begin
                    unique case ({inst[31:25], inst[14:12]})
                        {7'b0000000, 3'b000}: word_result = sext32(a[31:0] + b[31:0]);
                        {7'b0100000, 3'b000}: word_result = sext32(a[31:0] - b[31:0]);
                        {7'b0000000, 3'b001}: word_result = sext32(a[31:0] << b[4:0]);
                        {7'b0000000, 3'b101}: word_result = sext32(a[31:0] >> b[4:0]);
                        {7'b0100000, 3'b101}: word_result = sext32($signed(a[31:0]) >>> b[4:0]);
                        default: word_result = 64'd0;
                    endcase
                end
                default: word_result = 64'd0;
            endcase
        end
    endfunction

    function automatic logic csr_supported(input logic [11:0] addr);
        unique case (addr)
            CSR_FFLAGS,
            CSR_FRM,
            CSR_FCSR: csr_supported = HAS_FPU_CSR;
            CSR_SSTATUS,
            CSR_SIE,
            CSR_STVEC,
            CSR_SCOUNTEREN,
            CSR_SSCRATCH,
            CSR_SEPC,
            CSR_SCAUSE,
            CSR_STVAL,
            CSR_SIP,
            CSR_SATP,
            CSR_MSTATUS,
            CSR_MISA,
            CSR_MEDELEG,
            CSR_MIDELEG,
            CSR_MIE,
            CSR_MTVEC,
            CSR_MCOUNTEREN,
            CSR_MSCRATCH,
            CSR_MEPC,
            CSR_MCAUSE,
            CSR_MTVAL,
            CSR_MIP,
            CSR_MCYCLE,
            CSR_MINSTRET,
            CSR_CYCLE,
            CSR_TIME,
            CSR_INSTRET,
            CSR_MVENDORID,
            CSR_MARCHID,
            CSR_MIMPID,
            CSR_MHARTID: csr_supported = 1'b1;
            default:    csr_supported = 1'b0;
        endcase
    endfunction

    function automatic logic [63:0] csr_read_data(input logic [11:0] addr);
        unique case (addr)
            CSR_FFLAGS:    csr_read_data = {59'd0, csr_fflags};
            CSR_FRM:       csr_read_data = {61'd0, csr_frm};
            CSR_FCSR:      csr_read_data = {56'd0, csr_frm, csr_fflags};
            CSR_SSTATUS:   csr_read_data = csr_mstatus & SSTATUS_MASK;
            CSR_SIE:       csr_read_data = csr_sie;
            CSR_STVEC:     csr_read_data = csr_stvec;
            CSR_SCOUNTEREN: csr_read_data = csr_scounteren;
            CSR_SSCRATCH:  csr_read_data = csr_sscratch;
            CSR_SEPC:      csr_read_data = csr_sepc;
            CSR_SCAUSE:    csr_read_data = csr_scause;
            CSR_STVAL:     csr_read_data = csr_stval;
            CSR_SIP:       csr_read_data = csr_sip_view;
            CSR_SATP:      csr_read_data = csr_satp;
            CSR_MSTATUS:   csr_read_data = csr_mstatus;
            CSR_MISA:      csr_read_data = CSR_MISA_VALUE;
            CSR_MEDELEG:   csr_read_data = csr_medeleg;
            CSR_MIDELEG:   csr_read_data = csr_mideleg;
            CSR_MIE:       csr_read_data = csr_mie;
            CSR_MTVEC:     csr_read_data = csr_mtvec;
            CSR_MCOUNTEREN: csr_read_data = csr_mcounteren;
            CSR_MSCRATCH:  csr_read_data = csr_mscratch;
            CSR_MEPC:      csr_read_data = csr_mepc;
            CSR_MCAUSE:    csr_read_data = csr_mcause;
            CSR_MTVAL:     csr_read_data = csr_mtval;
            CSR_MIP:       csr_read_data = csr_mip_view;
            CSR_MCYCLE,
            CSR_CYCLE,
            CSR_TIME:      csr_read_data = mcycle_counter;
            CSR_MINSTRET,
            CSR_INSTRET:   csr_read_data = minstret_counter;
            CSR_MVENDORID: csr_read_data = 64'd0;
            CSR_MARCHID:   csr_read_data = 64'h0000_0000_0000_5a64;
            CSR_MIMPID:    csr_read_data = 64'd1;
            CSR_MHARTID:   csr_read_data = 64'd0;
            default:       csr_read_data = 64'd0;
        endcase
    endfunction

    task automatic flush_tlbs;
        begin
            itlb_valid <= '0;
            dtlb_valid <= '0;
        end
    endtask

    task automatic fill_tlb(input logic is_fetch,
                            input logic [63:0] vaddr,
                            input logic [63:0] pte,
                            input logic [1:0] level);
        logic [TLB_INDEX_BITS-1:0] tlb_index;
        begin
            tlb_index = vaddr[TLB_INDEX_BITS+11:12];
            if (is_fetch) begin
                itlb_valid[tlb_index] <= 1'b1;
                itlb_vpn_tags[tlb_index] <= vaddr[38:12];
                itlb_ptes[tlb_index] <= pte;
                itlb_levels[tlb_index] <= level;
            end else begin
                dtlb_valid[tlb_index] <= 1'b1;
                dtlb_vpn_tags[tlb_index] <= vaddr[38:12];
                dtlb_ptes[tlb_index] <= pte;
                dtlb_levels[tlb_index] <= level;
            end
        end
    endtask

    task automatic start_ptw(input logic [63:0] vaddr,
                             input logic [63:0] epc,
                             input logic is_fetch,
                             input logic is_store);
        begin
            ptw_vaddr_q <= vaddr;
            ptw_epc_q <= epc;
            ptw_is_fetch_q <= is_fetch;
            ptw_we_q <= is_store;
            if (!sv39_canonical(vaddr)) begin
                enter_trap(ptw_fault_cause(is_fetch, is_store), vaddr, epc);
            end else begin
                ptw_pte_addr_q <= sv39_pte_addr(csr_satp[43:0], vaddr, 2'd2);
                ptw_state_q <= PTW_L2;
            end
        end
    endtask

    task automatic enter_trap(input logic [63:0] cause,
                              input logic [63:0] tval,
                              input logic [63:0] epc);
        begin
            if_id_valid <= 1'b0;
            id_ex_valid <= 1'b0;
            ex_mem_valid <= 1'b0;
            id_ex_fp_reg_write <= 1'b0;
            id_ex_fp_load <= 1'b0;
            id_ex_fp_store <= 1'b0;
            id_ex_fp_to_int <= 1'b0;
            id_ex_int_to_fp <= 1'b0;
            id_ex_fp_sgnj <= 1'b0;
            id_ex_fp_class <= 1'b0;
            id_ex_fp_cmp <= 1'b0;
            id_ex_fp_minmax <= 1'b0;
            id_ex_fp_addsub <= 1'b0;
            id_ex_fp_mul <= 1'b0;
            id_ex_fp_divsqrt <= 1'b0;
            id_ex_fp_cvt <= 1'b0;
            id_ex_fence_i <= 1'b0;
            id_ex_sfence_vma <= 1'b0;
            ex_mem_fp_reg_write <= 1'b0;
            ex_mem_fp_load <= 1'b0;
            ex_mem_amo <= 1'b0;
            fetch2_q <= 1'b0;
            wfi_q <= 1'b0;
            amo_state_q <= AMO_READ;
            ptw_state_q <= PTW_IDLE;

            if ((current_priv != PRIV_M) &&
                (cause[63] ? csr_mideleg[cause[5:0]] : csr_medeleg[cause[5:0]])) begin
                csr_sepc <= {epc[63:1], 1'b0};
                csr_scause <= cause;
                csr_stval <= tval;
                csr_mstatus[5] <= csr_mstatus[1];
                csr_mstatus[1] <= 1'b0;
                csr_mstatus[8] <= (current_priv == PRIV_S);
                current_priv <= PRIV_S;
                pc_q <= {csr_stvec[63:2], 2'b00};
            end else begin
                csr_mepc <= {epc[63:1], 1'b0};
                csr_mcause <= cause;
                csr_mtval <= tval;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                csr_mstatus[12:11] <= current_priv;
                current_priv <= PRIV_M;
                pc_q <= {csr_mtvec[63:2], 2'b00};
            end
        end
    endtask

    function automatic logic [63:0] csr_next_data(input logic [2:0] f3,
                                                  input logic [63:0] old_data,
                                                  input logic [63:0] operand);
        unique case (f3)
            3'b001, 3'b101: csr_next_data = operand;
            3'b010, 3'b110: csr_next_data = old_data | operand;
            3'b011, 3'b111: csr_next_data = old_data & ~operand;
            default:        csr_next_data = old_data;
        endcase
    endfunction

    function automatic logic [63:0] normalize_mstatus(input logic [63:0] data);
        begin
            normalize_mstatus = data;
            normalize_mstatus[63] = (data[14:13] == 2'b11) || (data[16:15] == 2'b11);
        end
    endfunction

    task automatic write_csr(input logic [11:0] addr, input logic [63:0] data);
        begin
            unique case (addr)
                CSR_FFLAGS: begin
                    csr_fflags <= data[4:0];
                    csr_mstatus[14:13] <= 2'b11;
                    csr_mstatus[63] <= 1'b1;
                end
                CSR_FRM: begin
                    csr_frm <= data[2:0];
                    csr_mstatus[14:13] <= 2'b11;
                    csr_mstatus[63] <= 1'b1;
                end
                CSR_FCSR: begin
                    csr_fflags <= data[4:0];
                    csr_frm <= data[7:5];
                    csr_mstatus[14:13] <= 2'b11;
                    csr_mstatus[63] <= 1'b1;
                end
                CSR_SSTATUS:   csr_mstatus <= normalize_mstatus((csr_mstatus & ~SSTATUS_MASK) |
                                                                 (data & SSTATUS_MASK));
                CSR_SIE:       csr_sie <= data;
                CSR_STVEC:     csr_stvec <= {data[63:2], 2'b00};
                CSR_SCOUNTEREN: csr_scounteren <= data;
                CSR_SSCRATCH:  csr_sscratch <= data;
                CSR_SEPC:      csr_sepc <= {data[63:1], 1'b0};
                CSR_SCAUSE:    csr_scause <= data;
                CSR_STVAL:     csr_stval <= data;
                CSR_SIP:       csr_sip <= data;
                CSR_SATP: begin
                    csr_satp <= data;
                    flush_tlbs();
                end
                CSR_MSTATUS:  csr_mstatus <= normalize_mstatus(data);
                CSR_MEDELEG:  csr_medeleg <= data;
                CSR_MIDELEG:  csr_mideleg <= data;
                CSR_MIE:      csr_mie <= data;
                CSR_MCOUNTEREN: csr_mcounteren <= data;
                CSR_MTVEC:    csr_mtvec <= {data[63:2], 2'b00};
                CSR_MSCRATCH: csr_mscratch <= data;
                CSR_MEPC:     csr_mepc <= {data[63:1], 1'b0};
                CSR_MCAUSE:   csr_mcause <= data;
                CSR_MTVAL:    csr_mtval <= data;
                CSR_MIP:      csr_mip <= data;
                CSR_MCYCLE:   mcycle_counter <= data;
                CSR_MINSTRET: minstret_counter <= data;
                default: begin
                end
            endcase
        end
    endtask

    always_comb begin
        id_uses_rs1 = 1'b0;
        id_uses_rs2 = 1'b0;
        id_alu_op = ALU_ADD;
        id_alu_a_pc = 1'b0;
        id_alu_b_imm = 1'b0;
        id_imm = 64'd0;
        id_reg_write = 1'b0;
        id_mem_read = 1'b0;
        id_mem_write = 1'b0;
        id_wb_sel = WB_ALU;
        id_branch = 1'b0;
        id_jump = 1'b0;
        id_jalr = 1'b0;
        id_muldiv = 1'b0;
        id_amo = 1'b0;
        id_csr = 1'b0;
        id_uses_frs1 = 1'b0;
        id_uses_frs2 = 1'b0;
        id_uses_frs3 = 1'b0;
        id_fp_reg_write = 1'b0;
        id_fp_load = 1'b0;
        id_fp_store = 1'b0;
        id_fp_to_int = 1'b0;
        id_int_to_fp = 1'b0;
        id_fp_sgnj = 1'b0;
        id_fp_class = 1'b0;
        id_fp_cmp = 1'b0;
        id_fp_minmax = 1'b0;
        id_fp_addsub = 1'b0;
        id_fp_mul = 1'b0;
        id_fp_divsqrt = 1'b0;
        id_fp_fma = 1'b0;
        id_fp_cvt = 1'b0;
        id_ecall = 1'b0;
        id_wfi = 1'b0;
        id_fence_i = 1'b0;
        id_sfence_vma = 1'b0;
        id_mret = 1'b0;
        id_sret = 1'b0;
        id_halt = 1'b0;
        id_illegal = 1'b0;

        unique case (id_opcode)
            OPCODE64_LUI: begin
                id_imm = imm_u(if_id_instr);
                id_alu_b_imm = 1'b1;
                id_reg_write = 1'b1;
            end
            OPCODE64_AUIPC: begin
                id_imm = imm_u(if_id_instr);
                id_alu_a_pc = 1'b1;
                id_alu_b_imm = 1'b1;
                id_reg_write = 1'b1;
            end
            OPCODE64_JAL: begin
                id_imm = imm_j(if_id_instr);
                id_reg_write = 1'b1;
                id_wb_sel = WB_PC4;
                id_jump = 1'b1;
            end
            OPCODE64_JALR: begin
                id_uses_rs1 = 1'b1;
                id_imm = imm_i(if_id_instr);
                id_reg_write = 1'b1;
                id_wb_sel = WB_PC4;
                id_jump = 1'b1;
                id_jalr = 1'b1;
                id_illegal = (id_funct3 != 3'b000);
            end
            OPCODE64_BRANCH: begin
                id_uses_rs1 = 1'b1;
                id_uses_rs2 = 1'b1;
                id_imm = imm_b(if_id_instr);
                id_branch = 1'b1;
                id_illegal = !branch_supported(id_funct3);
            end
            OPCODE64_LOAD: begin
                id_uses_rs1 = 1'b1;
                id_imm = imm_i(if_id_instr);
                id_alu_b_imm = 1'b1;
                id_reg_write = 1'b1;
                id_mem_read = 1'b1;
                id_wb_sel = WB_MEM;
                id_illegal = !mem_load_supported(id_funct3);
            end
            OPCODE64_STORE: begin
                id_uses_rs1 = 1'b1;
                id_uses_rs2 = 1'b1;
                id_imm = imm_s(if_id_instr);
                id_alu_b_imm = 1'b1;
                id_mem_write = 1'b1;
                id_illegal = !mem_store_supported(id_funct3);
            end
            OPCODE64_AMO: begin
                id_uses_rs1 = 1'b1;
                id_uses_rs2 = (id_funct7[6:2] != 5'b00010);
                id_imm = 64'd0;
                id_alu_b_imm = 1'b1;
                id_reg_write = 1'b1;
                id_mem_read = 1'b1;
                id_wb_sel = WB_MEM;
                id_amo = 1'b1;
                id_illegal = !amo_supported_inst(id_funct3, id_funct7[6:2], id_rs2);
            end
            OPCODE64_OP_IMM: begin
                id_uses_rs1 = 1'b1;
                id_imm = imm_i(if_id_instr);
                id_alu_b_imm = 1'b1;
                id_reg_write = 1'b1;
                case (id_funct3)
                    3'b000: id_alu_op = ALU_ADD;
                    3'b010: id_alu_op = ALU_SLT;
                    3'b011: id_alu_op = ALU_SLTU;
                    3'b100: id_alu_op = ALU_XOR;
                    3'b110: id_alu_op = ALU_OR;
                    3'b111: id_alu_op = ALU_AND;
                    3'b001: begin
                        id_alu_op = ALU_SLL;
                        id_illegal = (if_id_instr[31:26] != 6'b000000);
                    end
                    3'b101: begin
                        if (if_id_instr[30]) begin
                            id_alu_op = ALU_SRA;
                        end else begin
                            id_alu_op = ALU_SRL;
                        end
                        id_illegal = (if_id_instr[31:26] != 6'b000000) &&
                                     (if_id_instr[31:26] != 6'b010000);
                    end
                    default: id_illegal = 1'b1;
                endcase
            end
            OPCODE64_OP_IMM_32: begin
                id_uses_rs1 = 1'b1;
                id_imm = imm_i(if_id_instr);
                id_alu_b_imm = 1'b1;
                id_reg_write = 1'b1;
                unique case (id_funct3)
                    3'b000: begin
                        id_alu_op = ALU_ADD;
                    end
                    3'b001: begin
                        id_alu_op = ALU_SLL;
                        id_illegal = (id_funct7 != 7'b0000000);
                    end
                    3'b101: begin
                        if (id_funct7 == 7'b0000000) begin
                            id_alu_op = ALU_SRL;
                        end else if (id_funct7 == 7'b0100000) begin
                            id_alu_op = ALU_SRA;
                        end else begin
                            id_illegal = 1'b1;
                        end
                    end
                    default: begin
                        id_illegal = 1'b1;
                    end
                endcase
            end
            OPCODE64_OP: begin
                id_uses_rs1 = 1'b1;
                id_uses_rs2 = 1'b1;
                id_reg_write = 1'b1;
                unique case ({id_funct7, id_funct3})
                    {7'b0000001, 3'b000},
                    {7'b0000001, 3'b001},
                    {7'b0000001, 3'b010},
                    {7'b0000001, 3'b011},
                    {7'b0000001, 3'b100},
                    {7'b0000001, 3'b101},
                    {7'b0000001, 3'b110},
                    {7'b0000001, 3'b111}: begin
                        id_alu_op = ALU_ADD;
                        id_muldiv = 1'b1;
                    end
                    {7'b0000000, 3'b000}: id_alu_op = ALU_ADD;
                    {7'b0100000, 3'b000}: id_alu_op = ALU_SUB;
                    {7'b0000000, 3'b001}: id_alu_op = ALU_SLL;
                    {7'b0000000, 3'b010}: id_alu_op = ALU_SLT;
                    {7'b0000000, 3'b011}: id_alu_op = ALU_SLTU;
                    {7'b0000000, 3'b100}: id_alu_op = ALU_XOR;
                    {7'b0000000, 3'b101}: id_alu_op = ALU_SRL;
                    {7'b0100000, 3'b101}: id_alu_op = ALU_SRA;
                    {7'b0000000, 3'b110}: id_alu_op = ALU_OR;
                    {7'b0000000, 3'b111}: id_alu_op = ALU_AND;
                    default: begin
                        id_alu_op = ALU_ADD;
                        id_illegal = 1'b1;
                    end
                endcase
            end
            OPCODE64_OP_32: begin
                id_uses_rs1 = 1'b1;
                id_uses_rs2 = 1'b1;
                id_reg_write = 1'b1;
                unique case ({id_funct7, id_funct3})
                    {7'b0000001, 3'b000},
                    {7'b0000001, 3'b100},
                    {7'b0000001, 3'b101},
                    {7'b0000001, 3'b110},
                    {7'b0000001, 3'b111}: begin
                        id_alu_op = ALU_ADD;
                        id_muldiv = 1'b1;
                    end
                    {7'b0000000, 3'b000}: id_alu_op = ALU_ADD;
                    {7'b0100000, 3'b000}: id_alu_op = ALU_SUB;
                    {7'b0000000, 3'b001}: id_alu_op = ALU_SLL;
                    {7'b0000000, 3'b101}: id_alu_op = ALU_SRL;
                    {7'b0100000, 3'b101}: id_alu_op = ALU_SRA;
                    default: begin
                        id_alu_op = ALU_ADD;
                        id_illegal = 1'b1;
                    end
                endcase
            end
            OPCODE64_MISC_MEM: begin
                unique case (id_funct3)
                    3'b000: begin
                        // FENCE is a no-op for the current strongly ordered single-core path.
                    end
                    3'b001: begin
                        id_fence_i = (if_id_instr[31:15] == 17'd0) && (id_rd == 5'd0);
                        id_illegal = !id_fence_i;
                    end
                    default: begin
                        id_illegal = 1'b1;
                    end
                endcase
            end
            OPCODE64_LOAD_FP: begin
                id_uses_rs1 = 1'b1;
                id_imm = imm_i(if_id_instr);
                id_alu_b_imm = 1'b1;
                id_mem_read = 1'b1;
                id_wb_sel = WB_MEM;
                id_fp_reg_write = 1'b1;
                id_fp_load = 1'b1;
                id_illegal = (csr_mstatus[14:13] == 2'b00) || !fp_mem_supported(id_funct3);
            end
            OPCODE64_STORE_FP: begin
                id_uses_rs1 = 1'b1;
                id_uses_frs2 = 1'b1;
                id_imm = imm_s(if_id_instr);
                id_alu_b_imm = 1'b1;
                id_mem_write = 1'b1;
                id_fp_store = 1'b1;
                id_illegal = (csr_mstatus[14:13] == 2'b00) || !fp_mem_supported(id_funct3);
            end
            OPCODE64_MADD,
            OPCODE64_MSUB,
            OPCODE64_NMSUB,
            OPCODE64_NMADD: begin
                if ((csr_mstatus[14:13] == 2'b00) || !fp_rm_valid(id_funct3, csr_frm) ||
                    ((if_id_instr[26:25] != 2'b00) && (if_id_instr[26:25] != 2'b01))) begin
                    id_illegal = 1'b1;
                end else begin
                    id_uses_frs1 = 1'b1;
                    id_uses_frs2 = 1'b1;
                    id_uses_frs3 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_fma = 1'b1;
                end
            end
            OPCODE64_OP_FP: begin
                if (csr_mstatus[14:13] == 2'b00) begin
                    id_illegal = 1'b1;
                end else if ((id_funct7 == 7'b0000000 || id_funct7 == 7'b0000001 ||
                              id_funct7 == 7'b0000100 || id_funct7 == 7'b0000101) &&
                             fp_rm_valid(id_funct3, csr_frm)) begin
                    id_uses_frs1 = 1'b1;
                    id_uses_frs2 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_addsub = 1'b1;
                end else if ((id_funct7 == 7'b0001000 || id_funct7 == 7'b0001001) &&
                             fp_rm_valid(id_funct3, csr_frm)) begin
                    id_uses_frs1 = 1'b1;
                    id_uses_frs2 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_mul = 1'b1;
                end else if ((id_funct7 == 7'b0001100 || id_funct7 == 7'b0001101) &&
                             fp_rm_valid(id_funct3, csr_frm)) begin
                    id_uses_frs1 = 1'b1;
                    id_uses_frs2 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_divsqrt = 1'b1;
                end else if ((id_funct7 == 7'b0101100 || id_funct7 == 7'b0101101) &&
                             id_rs2 == 5'd0 && fp_rm_valid(id_funct3, csr_frm)) begin
                    id_uses_frs1 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_divsqrt = 1'b1;
                end else if (((id_funct7 == 7'b0100000) && (id_rs2 == 5'd1) ||
                              (id_funct7 == 7'b0100001) && (id_rs2 == 5'd0)) &&
                             fp_rm_valid(id_funct3, csr_frm)) begin
                    id_uses_frs1 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_cvt = 1'b1;
                end else if ((id_funct7 == 7'b1110000 || id_funct7 == 7'b1110001) &&
                             id_rs2 == 5'd0 && id_funct3 == 3'b000) begin
                    id_uses_frs1 = 1'b1;
                    id_reg_write = 1'b1;
                    id_fp_to_int = 1'b1;
                end else if ((id_funct7 == 7'b1100000 || id_funct7 == 7'b1100001) &&
                             (id_rs2 <= 5'd3) && fp_rm_valid(id_funct3, csr_frm)) begin
                    id_uses_frs1 = 1'b1;
                    id_reg_write = 1'b1;
                    id_fp_to_int = 1'b1;
                end else if ((id_funct7 == 7'b1111000 || id_funct7 == 7'b1111001) &&
                             id_rs2 == 5'd0 && id_funct3 == 3'b000) begin
                    id_uses_rs1 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_int_to_fp = 1'b1;
                end else if ((id_funct7 == 7'b1101000 || id_funct7 == 7'b1101001) &&
                             (id_rs2 <= 5'd3) && fp_rm_valid(id_funct3, csr_frm)) begin
                    id_uses_rs1 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_int_to_fp = 1'b1;
                end else if ((id_funct7 == 7'b0010000 || id_funct7 == 7'b0010001) &&
                             ((id_funct3 == 3'b000) || (id_funct3 == 3'b001) ||
                              (id_funct3 == 3'b010))) begin
                    id_uses_frs1 = 1'b1;
                    id_uses_frs2 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_sgnj = 1'b1;
                end else if ((id_funct7 == 7'b1110000 || id_funct7 == 7'b1110001) &&
                             id_rs2 == 5'd0 && id_funct3 == 3'b001) begin
                    id_uses_frs1 = 1'b1;
                    id_reg_write = 1'b1;
                    id_fp_class = 1'b1;
                end else if ((id_funct7 == 7'b1010000 || id_funct7 == 7'b1010001) &&
                             ((id_funct3 == 3'b000) || (id_funct3 == 3'b001) ||
                              (id_funct3 == 3'b010))) begin
                    id_uses_frs1 = 1'b1;
                    id_uses_frs2 = 1'b1;
                    id_reg_write = 1'b1;
                    id_fp_cmp = 1'b1;
                end else if ((id_funct7 == 7'b0010100 || id_funct7 == 7'b0010101) &&
                             ((id_funct3 == 3'b000) || (id_funct3 == 3'b001))) begin
                    id_uses_frs1 = 1'b1;
                    id_uses_frs2 = 1'b1;
                    id_fp_reg_write = 1'b1;
                    id_fp_minmax = 1'b1;
                end else begin
                    id_illegal = 1'b1;
                end
            end
            OPCODE64_SYSTEM: begin
                if (id_funct3 == 3'b000) begin
                    if (if_id_instr == 32'h0000_0073) begin
                        id_ecall = 1'b1;
                    end else if (if_id_instr == 32'h0010_0073) begin
                        id_halt = 1'b1;
                    end else if (if_id_instr == 32'h1050_0073) begin
                        id_wfi = 1'b1;
                    end else if (if_id_instr == 32'h1020_0073) begin
                        id_sret = 1'b1;
                    end else if (if_id_instr == 32'h3020_0073) begin
                        id_mret = 1'b1;
                    end else if (id_funct7 == 7'b0001001 && id_rd == 5'd0) begin
                        id_sfence_vma = 1'b1;
                    end else begin
                        id_illegal = 1'b1;
                    end
                end else if ((id_funct3 == 3'b001) || (id_funct3 == 3'b010) ||
                             (id_funct3 == 3'b011) || (id_funct3 == 3'b101) ||
                             (id_funct3 == 3'b110) || (id_funct3 == 3'b111)) begin
                    id_csr = 1'b1;
                    id_reg_write = 1'b1;
                    id_wb_sel = WB_CSR;
                    id_uses_rs1 = !id_funct3[2] && (id_rs1 != 5'd0);
                end else begin
                    id_illegal = 1'b1;
                end
            end
            default: begin
                id_illegal = 1'b1;
            end
        endcase

        if (!ENABLE_FPU && fp_opcode(id_opcode)) begin
            id_uses_frs1 = 1'b0;
            id_uses_frs2 = 1'b0;
            id_uses_frs3 = 1'b0;
            id_fp_reg_write = 1'b0;
            id_fp_load = 1'b0;
            id_fp_store = 1'b0;
            id_fp_to_int = 1'b0;
            id_int_to_fp = 1'b0;
            id_fp_sgnj = 1'b0;
            id_fp_class = 1'b0;
            id_fp_cmp = 1'b0;
            id_fp_minmax = 1'b0;
            id_fp_addsub = 1'b0;
            id_fp_mul = 1'b0;
            id_fp_divsqrt = 1'b0;
            id_fp_fma = 1'b0;
            id_fp_cvt = 1'b0;
            id_illegal = 1'b1;
        end
    end

    always_comb begin
        id_rs1_data = rs1_data;
        id_rs2_data = rs2_data;
        if (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_rs1) begin
            id_rs1_data = mem_wb_data;
        end
        if (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0 && mem_wb_rd == id_rs2) begin
            id_rs2_data = mem_wb_data;
        end
    end

    always_comb begin
        id_frs1_data = frs1_data;
        id_frs2_data = frs2_data;
        id_frs3_data = frs3_data;
        if (mem_wb_fp_reg_write && mem_wb_rd == id_rs1) begin
            id_frs1_data = mem_wb_fp_data;
        end
        if (mem_wb_fp_reg_write && mem_wb_rd == id_rs2) begin
            id_frs2_data = mem_wb_fp_data;
        end
        if (mem_wb_fp_reg_write && mem_wb_rd == id_rs3) begin
            id_frs3_data = mem_wb_fp_data;
        end
    end

    always_comb begin
        ex_rs1_data = id_ex_rs1_data;
        ex_rs2_data = id_ex_rs2_data;
        ex_frs1_data = id_ex_frs1_data;
        ex_frs2_data = id_ex_frs2_data;
        ex_frs3_data = id_ex_frs3_data;

        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
            ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs1) begin
            ex_rs1_data = ex_mem_wb_data;
        end else if (mem_wb_valid && mem_wb_reg_write &&
                     mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs1) begin
            ex_rs1_data = mem_wb_data;
        end

        if (ex_mem_valid && ex_mem_reg_write && !ex_mem_mem_read &&
            ex_mem_rd != 5'd0 && ex_mem_rd == id_ex_rs2) begin
            ex_rs2_data = ex_mem_wb_data;
        end else if (mem_wb_valid && mem_wb_reg_write &&
                     mem_wb_rd != 5'd0 && mem_wb_rd == id_ex_rs2) begin
            ex_rs2_data = mem_wb_data;
        end

        if (mem_wb_fp_reg_write && mem_wb_rd == id_ex_rs1) begin
            ex_frs1_data = mem_wb_fp_data;
        end
        if (mem_wb_fp_reg_write && mem_wb_rd == id_ex_rs2) begin
            ex_frs2_data = mem_wb_fp_data;
        end
        if (mem_wb_fp_reg_write && mem_wb_rd == id_ex_rs3) begin
            ex_frs3_data = mem_wb_fp_data;
        end
    end

    assign ex_alu_a = id_ex_alu_a_pc ? id_ex_pc : ex_rs1_data;
    assign ex_alu_b = id_ex_alu_b_imm ? id_ex_imm : ex_rs2_data;
    assign ex_word_y = word_result(id_ex_instr, ex_rs1_data, ex_rs2_data);
    assign ex_word_op = (id_ex_instr[6:0] == OPCODE64_OP_IMM_32) ||
                        (id_ex_instr[6:0] == OPCODE64_OP_32);
    assign ex_mem_amo_funct5 = ex_mem_instr[31:27];
    assign ex_mem_amo_width_w = (ex_mem_instr[14:12] == 3'b010);
    assign ex_mem_amo_lr = (ex_mem_amo_funct5 == 5'b00010);
    assign ex_mem_amo_sc = (ex_mem_amo_funct5 == 5'b00011);
    assign ex_csr_addr = id_ex_instr[31:20];
    assign ex_csr_rdata = csr_read_data(ex_csr_addr);
    assign ex_csr_operand = id_ex_instr[14] ? {59'd0, id_ex_instr[19:15]} : ex_rs1_data;
    assign ex_csr_wdata = csr_next_data(id_ex_instr[14:12], ex_csr_rdata, ex_csr_operand);
    assign ex_csr_supported = csr_supported(ex_csr_addr);
    assign ex_csr_wen = id_ex_csr &&
                        ((id_ex_instr[14:12] == 3'b001) ||
                         (id_ex_instr[14:12] == 3'b101) ||
                         (id_ex_instr[19:15] != 5'd0));
    assign ex_csr_read_only = (ex_csr_addr[11:10] == 2'b11);
    assign ex_csr_fp = (ex_csr_addr == CSR_FFLAGS) ||
                       (ex_csr_addr == CSR_FRM) ||
                       (ex_csr_addr == CSR_FCSR);
    assign ex_csr_illegal = id_ex_csr &&
                            (!ex_csr_supported ||
                             (current_priv < ex_csr_addr[9:8]) ||
                             (ex_csr_read_only && ex_csr_wen) ||
                             (ex_csr_fp && (csr_mstatus[14:13] == 2'b00)));
    assign ex_ecall = id_ex_valid && id_ex_ecall && !id_ex_illegal;
    assign ex_wfi = id_ex_valid && id_ex_wfi && !id_ex_illegal && (current_priv != PRIV_U);
    assign ex_fence_i = id_ex_valid && id_ex_fence_i && !id_ex_illegal;
    assign ex_sfence_vma = id_ex_valid && id_ex_sfence_vma && !id_ex_illegal && (current_priv != PRIV_U);
    assign ex_trap_cause = (current_priv == PRIV_S) ? MCAUSE_ECALL_S :
                           (current_priv == PRIV_U) ? MCAUSE_ECALL_U : MCAUSE_ECALL_M;
    assign ex_trap_to_s = ex_ecall && (current_priv != PRIV_M) && csr_medeleg[ex_trap_cause[5:0]];
    assign ex_mret = id_ex_valid && id_ex_mret && !id_ex_illegal && (current_priv == PRIV_M);
    assign ex_sret = id_ex_valid && id_ex_sret && !id_ex_illegal && (current_priv != PRIV_U);
    assign ex_system_redirect = ex_ecall || ex_mret || ex_sret || ex_wfi || ex_fence_i || ex_sfence_vma;
    assign ex_system_redirect_pc = ex_ecall ? (ex_trap_to_s ? {csr_stvec[63:2], 2'b00} :
                                                              {csr_mtvec[63:2], 2'b00}) :
                                   (ex_mret ? csr_mepc :
                                    (ex_sret ? csr_sepc : (id_ex_pc + {61'd0, id_ex_instr_len})));
    assign ex_branch_take = id_ex_branch && branch_taken(id_ex_mem_funct3, ex_rs1_data, ex_rs2_data);
    assign ex_redirect = id_ex_valid && (id_ex_jump || ex_branch_take || ex_system_redirect);
    assign ex_mem_fp_commit = ENABLE_FPU && ex_mem_valid && !ex_mem_halt && !ex_mem_illegal &&
                              fp_opcode(ex_mem_instr[6:0]);
    assign ex_redirect_pc = ex_system_redirect ? ex_system_redirect_pc :
                            (id_ex_jalr ? ((ex_rs1_data + id_ex_imm) & ~64'd1) :
                             (id_ex_pc + id_ex_imm));
    assign fence_i = ex_fence_i;
    assign ex_mem_fault = id_ex_valid && (id_ex_mem_read || id_ex_mem_write) &&
                          !mem_aligned(id_ex_mem_funct3, ex_alu_y[2:0]);
    assign ex_wb_data = (ENABLE_FPU && id_ex_fp_to_int) ? fp_to_int_data(id_ex_instr, ex_frs1_data, csr_frm) :
                        (ENABLE_FPU && id_ex_fp_class) ? fp_class_data(id_ex_instr, ex_frs1_data) :
                        (ENABLE_FPU && id_ex_fp_cmp) ? fp_cmp_data(id_ex_instr, ex_frs1_data, ex_frs2_data) :
                        (id_ex_wb_sel == WB_PC4) ? (id_ex_pc + {61'd0, id_ex_instr_len}) :
                        (id_ex_muldiv ? muldiv_result :
                         ((id_ex_wb_sel == WB_CSR) ? ex_csr_rdata :
                          (ex_word_op ? ex_word_y : ex_alu_y)));
    assign ex_fp_wb_data = !ENABLE_FPU ? 64'd0 :
                           id_ex_int_to_fp ? int_to_fp_data(id_ex_instr, ex_rs1_data, csr_frm) :
                           id_ex_fp_sgnj ? fp_sgnj_data(id_ex_instr, ex_frs1_data, ex_frs2_data) :
                           id_ex_fp_minmax ? fp_minmax_data(id_ex_instr, ex_frs1_data, ex_frs2_data) :
                           id_ex_fp_addsub ? fp_addsub_data(id_ex_instr, ex_frs1_data, ex_frs2_data, csr_frm) :
                           id_ex_fp_mul ? fp_mul_data(id_ex_instr, ex_frs1_data, ex_frs2_data, csr_frm) :
                           id_ex_fp_divsqrt ? fp_divsqrt_data(id_ex_instr, ex_frs1_data, ex_frs2_data, csr_frm) :
                           id_ex_fp_fma ? fp_fma_data(id_ex_instr, ex_frs1_data, ex_frs2_data, ex_frs3_data, csr_frm) :
                           id_ex_fp_cvt ? fp_cvt_fp_data(id_ex_instr, ex_frs1_data, csr_frm) :
                           64'd0;
    assign ex_fp_fflags_w = !ENABLE_FPU ? 5'd0 :
                            (id_ex_valid && !id_ex_halt && !id_ex_illegal &&
                             !ex_mem_fault && !ex_csr_illegal && !ex_system_redirect) ?
                            fp_fflags_data(id_ex_instr, ex_frs1_data, ex_frs2_data,
                                           ex_frs3_data, ex_rs1_data) : 5'd0;
    assign muldiv_start = id_ex_valid && id_ex_muldiv && !id_ex_illegal &&
                          !mem_stall && !amo_stall && !muldiv_busy && !muldiv_done;

    assign load_use_hazard = if_id_valid && id_ex_valid && id_ex_mem_read &&
                             id_ex_rd != 5'd0 &&
                             ((id_uses_rs1 && id_rs1 == id_ex_rd) ||
                              (id_uses_rs2 && id_rs2 == id_ex_rd));
    assign fp_raw_hazard = if_id_valid &&
                           (((id_uses_frs1 &&
                              ((id_ex_valid && id_ex_fp_reg_write && id_ex_rd == id_rs1) ||
                               (ex_mem_valid && ex_mem_fp_reg_write && ex_mem_rd == id_rs1))) ||
                             (id_uses_frs2 &&
                             ((id_ex_valid && id_ex_fp_reg_write && id_ex_rd == id_rs2) ||
                               (ex_mem_valid && ex_mem_fp_reg_write && ex_mem_rd == id_rs2))) ||
                             (id_uses_frs3 &&
                              ((id_ex_valid && id_ex_fp_reg_write && id_ex_rd == id_rs3) ||
                               (ex_mem_valid && ex_mem_fp_reg_write && ex_mem_rd == id_rs3)))));
    assign mem_stall = dmem_valid && !ex_mem_amo && !dmem_ready;
    assign amo_stall = ex_mem_valid && ex_mem_amo;
    assign execute_stall = id_ex_valid && id_ex_muldiv && !muldiv_done;
    assign fetch_accept = imem_valid && imem_ready;
    assign csr_mip_view = csr_mip |
                          (irq_timer ? MIP_MTIP : 64'd0) |
                          ((irq_timer && csr_mideleg[IRQ_S_TIMER]) ? MIP_STIP : 64'd0) |
                          (irq_external ? MIP_MEIP : 64'd0) |
                          ((irq_external && csr_mideleg[IRQ_S_EXT]) ? MIP_SEIP : 64'd0);
    assign csr_sip_view = csr_sip |
                          ((irq_timer && csr_mideleg[IRQ_S_TIMER]) ? MIP_STIP : 64'd0) |
                          ((irq_external && csr_mideleg[IRQ_S_EXT]) ? MIP_SEIP : 64'd0);
    assign interrupt_cause = (irq_timer && (current_priv != PRIV_M) &&
                              csr_mideleg[IRQ_S_TIMER] &&
                              csr_sie[IRQ_S_TIMER] &&
                              (current_priv != PRIV_S || csr_mstatus[1])) ?
                             (MCAUSE_INTERRUPT | 64'd5) :
                             (irq_timer && csr_mie[IRQ_M_TIMER] &&
                              (current_priv == PRIV_M ? csr_mstatus[3] : !csr_mideleg[IRQ_S_TIMER])) ?
                             (MCAUSE_INTERRUPT | 64'd7) :
                             (irq_external && (current_priv != PRIV_M) &&
                              csr_mideleg[IRQ_S_EXT] &&
                              csr_sie[IRQ_S_EXT] &&
                              (current_priv != PRIV_S || csr_mstatus[1])) ?
                             (MCAUSE_INTERRUPT | 64'd9) :
                             (irq_external && csr_mie[IRQ_M_EXT] &&
                              (current_priv == PRIV_M ? csr_mstatus[3] : !csr_mideleg[IRQ_S_EXT])) ?
                             (MCAUSE_INTERRUPT | 64'd11) : 64'd0;
    assign interrupt_pending = (interrupt_cause != 64'd0);
    assign interrupt_epc = id_ex_valid ? id_ex_pc :
                           (if_id_valid ? if_id_pc : pc_q);

    always_comb begin
        logic [TLB_INDEX_BITS-1:0] tlb_index;

        tlb_index = fetch_vaddr[TLB_INDEX_BITS+11:12];
        fetch_tlb_hit = sv39_canonical(fetch_vaddr) &&
                        itlb_valid[tlb_index] &&
                        tlb_tag_match(fetch_vaddr, itlb_vpn_tags[tlb_index], itlb_levels[tlb_index]) &&
                        sv39_access_ok(itlb_ptes[tlb_index], current_priv, 1'b1, 1'b0, csr_mstatus);
        fetch_tlb_paddr = sv39_leaf_paddr(itlb_ptes[tlb_index], fetch_vaddr, itlb_levels[tlb_index]);

        tlb_index = data_vaddr[TLB_INDEX_BITS+11:12];
        data_tlb_hit = sv39_canonical(data_vaddr) &&
                       dtlb_valid[tlb_index] &&
                       tlb_tag_match(data_vaddr, dtlb_vpn_tags[tlb_index], dtlb_levels[tlb_index]) &&
                       sv39_access_ok(dtlb_ptes[tlb_index], current_priv, 1'b0, data_is_store, csr_mstatus);
        data_tlb_paddr = sv39_leaf_paddr(dtlb_ptes[tlb_index], data_vaddr, dtlb_levels[tlb_index]);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q <= 64'd0;
            reset_vector_pending_q <= 1'b1;
            halted_q <= 1'b0;
            illegal_q <= 1'b0;
            wfi_q <= 1'b0;
            fetch2_q <= 1'b0;
            fetch2_pc_q <= 64'd0;
            fetch2_upper_half_q <= 16'd0;
            if_id_valid <= 1'b0;
            if_id_pc <= 64'd0;
            if_id_instr <= 32'd0;
            if_id_instr_len <= 3'd4;
            id_ex_valid <= 1'b0;
            id_ex_pc <= 64'd0;
            id_ex_instr <= 32'd0;
            id_ex_instr_len <= 3'd4;
            id_ex_rs1 <= 5'd0;
            id_ex_rs2 <= 5'd0;
            id_ex_rs3 <= 5'd0;
            id_ex_rd <= 5'd0;
            id_ex_rs1_data <= 64'd0;
            id_ex_rs2_data <= 64'd0;
            id_ex_imm <= 64'd0;
            id_ex_alu_op <= ALU_ADD;
            id_ex_alu_a_pc <= 1'b0;
            id_ex_alu_b_imm <= 1'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_mem_funct3 <= 3'd0;
            id_ex_wb_sel <= WB_ALU;
            id_ex_branch <= 1'b0;
            id_ex_jump <= 1'b0;
            id_ex_jalr <= 1'b0;
            id_ex_muldiv <= 1'b0;
            id_ex_amo <= 1'b0;
            id_ex_csr <= 1'b0;
            id_ex_fp_reg_write <= 1'b0;
            id_ex_fp_load <= 1'b0;
            id_ex_fp_store <= 1'b0;
            id_ex_fp_to_int <= 1'b0;
            id_ex_int_to_fp <= 1'b0;
            id_ex_fp_sgnj <= 1'b0;
            id_ex_fp_class <= 1'b0;
            id_ex_fp_cmp <= 1'b0;
            id_ex_fp_minmax <= 1'b0;
            id_ex_fp_addsub <= 1'b0;
            id_ex_fp_mul <= 1'b0;
            id_ex_fp_divsqrt <= 1'b0;
            id_ex_fp_fma <= 1'b0;
            id_ex_fp_cvt <= 1'b0;
            id_ex_frs1_data <= 64'd0;
            id_ex_frs2_data <= 64'd0;
            id_ex_frs3_data <= 64'd0;
            id_ex_ecall <= 1'b0;
            id_ex_wfi <= 1'b0;
            id_ex_fence_i <= 1'b0;
            id_ex_sfence_vma <= 1'b0;
            id_ex_mret <= 1'b0;
            id_ex_sret <= 1'b0;
            id_ex_halt <= 1'b0;
            id_ex_illegal <= 1'b0;
            ex_mem_valid <= 1'b0;
            ex_mem_pc <= 64'd0;
            ex_mem_instr <= 32'd0;
            ex_mem_rd <= 5'd0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_mem_funct3 <= 3'd0;
            ex_mem_alu_result <= 64'd0;
            ex_mem_store_data <= 64'd0;
            ex_mem_store_strobe <= 8'd0;
            ex_mem_wb_data <= 64'd0;
            ex_mem_fp_reg_write <= 1'b0;
            ex_mem_fp_load <= 1'b0;
            ex_mem_fp_wb_data <= 64'd0;
            ex_mem_fp_fflags <= 5'd0;
            ex_mem_wb_sel <= WB_ALU;
            ex_mem_halt <= 1'b0;
            ex_mem_illegal <= 1'b0;
            ex_mem_trap_cause <= 64'd0;
            ex_mem_trap_tval <= 64'd0;
            ex_mem_amo <= 1'b0;
            ex_mem_rs2_data <= 64'd0;
            mem_wb_valid <= 1'b0;
            mem_wb_rd <= 5'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_data <= 64'd0;
            mem_wb_fp_reg_write <= 1'b0;
            mem_wb_fp_data <= 64'd0;
            current_priv <= PRIV_M;
            csr_fflags <= 5'd0;
            csr_frm <= 3'd0;
            csr_mstatus <= MSTATUS_RESET;
            csr_medeleg <= 64'd0;
            csr_mideleg <= 64'd0;
            csr_mie <= 64'd0;
            csr_mcounteren <= 64'd0;
            csr_mtvec <= 64'd0;
            csr_sie <= 64'd0;
            csr_scounteren <= 64'd0;
            csr_stvec <= 64'd0;
            csr_sscratch <= 64'd0;
            csr_sepc <= 64'd0;
            csr_scause <= 64'd0;
            csr_stval <= 64'd0;
            csr_sip <= 64'd0;
            csr_satp <= 64'd0;
            csr_mscratch <= 64'd0;
            csr_mepc <= 64'd0;
            csr_mcause <= 64'd0;
            csr_mtval <= 64'd0;
            csr_mip <= 64'd0;
            mcycle_counter <= 64'd0;
            minstret_counter <= 64'd0;
            lr_reservation_valid <= 1'b0;
            lr_reservation_addr <= 30'd0;
            amo_state_q <= AMO_READ;
            ptw_state_q <= PTW_IDLE;
            ptw_vaddr_q <= 64'd0;
            ptw_epc_q <= 64'd0;
            ptw_is_fetch_q <= 1'b0;
            ptw_we_q <= 1'b0;
            ptw_pte_addr_q <= 32'd0;
            itlb_valid <= '0;
            dtlb_valid <= '0;
            amo_wdata_q <= 64'd0;
            amo_wstrb_q <= 8'd0;
            amo_wb_data_q <= 64'd0;
            amo_rdata_q <= 64'd0;
        end else if (soft_reset || reset_vector_pending_q) begin
            pc_q <= reset_vector;
            reset_vector_pending_q <= 1'b0;
            halted_q <= 1'b0;
            illegal_q <= 1'b0;
            wfi_q <= 1'b0;
            fetch2_q <= 1'b0;
            fetch2_pc_q <= 64'd0;
            fetch2_upper_half_q <= 16'd0;
            if_id_valid <= 1'b0;
            if_id_instr_len <= 3'd4;
            id_ex_valid <= 1'b0;
            id_ex_instr_len <= 3'd4;
            id_ex_fp_reg_write <= 1'b0;
            id_ex_fp_load <= 1'b0;
            id_ex_fp_store <= 1'b0;
            id_ex_fp_to_int <= 1'b0;
            id_ex_int_to_fp <= 1'b0;
            id_ex_fp_sgnj <= 1'b0;
            id_ex_fp_class <= 1'b0;
            id_ex_fp_cmp <= 1'b0;
            id_ex_fp_minmax <= 1'b0;
            id_ex_fp_addsub <= 1'b0;
            id_ex_fp_mul <= 1'b0;
            id_ex_fp_divsqrt <= 1'b0;
            id_ex_fp_fma <= 1'b0;
            id_ex_fp_cvt <= 1'b0;
            id_ex_fence_i <= 1'b0;
            id_ex_sfence_vma <= 1'b0;
            ex_mem_valid <= 1'b0;
            ex_mem_fp_reg_write <= 1'b0;
            ex_mem_fp_load <= 1'b0;
            ex_mem_fp_fflags <= 5'd0;
            ex_mem_amo <= 1'b0;
            ex_mem_trap_cause <= 64'd0;
            ex_mem_trap_tval <= 64'd0;
            mem_wb_valid <= 1'b0;
            mem_wb_fp_reg_write <= 1'b0;
            current_priv <= PRIV_M;
            csr_fflags <= 5'd0;
            csr_frm <= 3'd0;
            csr_mstatus <= MSTATUS_RESET;
            csr_medeleg <= 64'd0;
            csr_mideleg <= 64'd0;
            csr_mie <= 64'd0;
            csr_mcounteren <= 64'd0;
            csr_mtvec <= 64'd0;
            csr_sie <= 64'd0;
            csr_scounteren <= 64'd0;
            csr_stvec <= 64'd0;
            csr_sscratch <= 64'd0;
            csr_sepc <= 64'd0;
            csr_scause <= 64'd0;
            csr_stval <= 64'd0;
            csr_sip <= 64'd0;
            csr_satp <= 64'd0;
            csr_mscratch <= 64'd0;
            csr_mepc <= 64'd0;
            csr_mcause <= 64'd0;
            csr_mtval <= 64'd0;
            csr_mip <= 64'd0;
            mcycle_counter <= 64'd0;
            minstret_counter <= 64'd0;
            lr_reservation_valid <= 1'b0;
            lr_reservation_addr <= 30'd0;
            amo_state_q <= AMO_READ;
            ptw_state_q <= PTW_IDLE;
            ptw_vaddr_q <= 64'd0;
            ptw_epc_q <= 64'd0;
            ptw_is_fetch_q <= 1'b0;
            ptw_we_q <= 1'b0;
            ptw_pte_addr_q <= 32'd0;
            itlb_valid <= '0;
            dtlb_valid <= '0;
            amo_wdata_q <= 64'd0;
            amo_wstrb_q <= 8'd0;
            amo_wb_data_q <= 64'd0;
            amo_rdata_q <= 64'd0;
        end else if (!halted_q) begin
            mcycle_counter <= mcycle_counter + 64'd1;
            if (mem_wb_fp_reg_write) begin
                csr_mstatus[14:13] <= 2'b11;
                csr_mstatus[63] <= 1'b1;
            end

            if (wfi_q) begin
                mem_wb_valid <= 1'b0;
                mem_wb_fp_reg_write <= 1'b0;
                if (interrupt_pending) begin
                    enter_trap(interrupt_cause, 64'd0, pc_q);
                end
            end else if (ptw_busy || data_translate_pending || fetch_translate_pending) begin
                mem_wb_valid <= 1'b0;
                mem_wb_fp_reg_write <= 1'b0;

                if (!ptw_busy) begin
                    if (data_translate_pending) begin
                        start_ptw(data_vaddr, ex_mem_pc, 1'b0, data_is_store);
                    end else begin
                        start_ptw(fetch_vaddr, fetch_epc, 1'b1, 1'b0);
                    end
                end else if (dmem_ready) begin
                    unique case (ptw_state_q)
                        PTW_L2: begin
                            if (!sv39_pte_valid(dmem_rdata)) begin
                                enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q),
                                           ptw_vaddr_q, ptw_epc_q);
                            end else if (sv39_pte_leaf(dmem_rdata)) begin
                                if (!sv39_superpage_aligned(dmem_rdata, 2'd2) ||
                                    !sv39_access_ok(dmem_rdata, current_priv,
                                                    ptw_is_fetch_q, ptw_we_q, csr_mstatus)) begin
                                    enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q),
                                               ptw_vaddr_q, ptw_epc_q);
                                end else begin
                                    fill_tlb(ptw_is_fetch_q, ptw_vaddr_q, dmem_rdata, 2'd2);
                                    ptw_state_q <= PTW_IDLE;
                                end
                            end else begin
                                ptw_pte_addr_q <= sv39_pte_addr(dmem_rdata[53:10], ptw_vaddr_q, 2'd1);
                                ptw_state_q <= PTW_L1;
                            end
                        end

                        PTW_L1: begin
                            if (!sv39_pte_valid(dmem_rdata)) begin
                                enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q),
                                           ptw_vaddr_q, ptw_epc_q);
                            end else if (sv39_pte_leaf(dmem_rdata)) begin
                                if (!sv39_superpage_aligned(dmem_rdata, 2'd1) ||
                                    !sv39_access_ok(dmem_rdata, current_priv,
                                                    ptw_is_fetch_q, ptw_we_q, csr_mstatus)) begin
                                    enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q),
                                               ptw_vaddr_q, ptw_epc_q);
                                end else begin
                                    fill_tlb(ptw_is_fetch_q, ptw_vaddr_q, dmem_rdata, 2'd1);
                                    ptw_state_q <= PTW_IDLE;
                                end
                            end else begin
                                ptw_pte_addr_q <= sv39_pte_addr(dmem_rdata[53:10], ptw_vaddr_q, 2'd0);
                                ptw_state_q <= PTW_L0;
                            end
                        end

                        PTW_L0: begin
                            if (!sv39_pte_valid(dmem_rdata) ||
                                !sv39_pte_leaf(dmem_rdata) ||
                                !sv39_access_ok(dmem_rdata, current_priv,
                                                ptw_is_fetch_q, ptw_we_q, csr_mstatus)) begin
                                enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q),
                                           ptw_vaddr_q, ptw_epc_q);
                            end else begin
                                fill_tlb(ptw_is_fetch_q, ptw_vaddr_q, dmem_rdata, 2'd0);
                                ptw_state_q <= PTW_IDLE;
                            end
                        end

                        default: begin
                            ptw_state_q <= PTW_IDLE;
                        end
                    endcase
                end
            end else if (amo_stall) begin
                if (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0) begin
                    if (mem_wb_rd == id_ex_rs1) begin
                        id_ex_rs1_data <= mem_wb_data;
                    end
                    if (mem_wb_rd == id_ex_rs2) begin
                        id_ex_rs2_data <= mem_wb_data;
                    end
                end

                mem_wb_valid <= 1'b0;
                mem_wb_fp_reg_write <= 1'b0;

                if (amo_state_q == AMO_CALC) begin
                    amo_wdata_q <= amo_store_value(ex_mem_amo_funct5,
                                                   ex_mem_amo_width_w,
                                                   ex_mem_alu_result[2:0],
                                                   amo_rdata_q,
                                                   ex_mem_rs2_data);
                    amo_wstrb_q <= amo_store_strobe(ex_mem_amo_width_w,
                                                    ex_mem_alu_result[2:0]);
                    amo_wb_data_q <= amo_read_result(ex_mem_amo_width_w,
                                                     ex_mem_alu_result[2:0],
                                                     amo_rdata_q);
                    amo_state_q <= AMO_WRITE;
                end else if (dmem_ready) begin
                    if (amo_state_q == AMO_WRITE) begin
                        if (lr_reservation_valid &&
                            lr_reservation_addr[29:1] == ex_mem_alu_result[31:3]) begin
                            lr_reservation_valid <= 1'b0;
                        end

                        mem_wb_valid <= ex_mem_reg_write;
                        mem_wb_rd <= ex_mem_rd;
                        mem_wb_reg_write <= ex_mem_reg_write;
                        mem_wb_data <= amo_wb_data_q;
                        mem_wb_fp_reg_write <= 1'b0;
                        if (!ex_mem_halt && !ex_mem_illegal) begin
                            minstret_counter <= minstret_counter + 64'd1;
                        end

                        ex_mem_valid <= 1'b0;
                        ex_mem_reg_write <= 1'b0;
                        ex_mem_mem_read <= 1'b0;
                        ex_mem_mem_write <= 1'b0;
                        ex_mem_halt <= 1'b0;
                        ex_mem_illegal <= 1'b0;
                        ex_mem_amo <= 1'b0;
                        amo_state_q <= AMO_READ;
                    end else if (ex_mem_amo_lr) begin
                        lr_reservation_valid <= 1'b1;
                        lr_reservation_addr <= ex_mem_alu_result[31:2];
                        mem_wb_valid <= ex_mem_reg_write;
                        mem_wb_rd <= ex_mem_rd;
                        mem_wb_reg_write <= ex_mem_reg_write;
                        mem_wb_data <= amo_read_result(ex_mem_amo_width_w,
                                                       ex_mem_alu_result[2:0],
                                                       dmem_rdata);
                        mem_wb_fp_reg_write <= 1'b0;
                        if (!ex_mem_halt && !ex_mem_illegal) begin
                            minstret_counter <= minstret_counter + 64'd1;
                        end

                        ex_mem_valid <= 1'b0;
                        ex_mem_reg_write <= 1'b0;
                        ex_mem_mem_read <= 1'b0;
                        ex_mem_mem_write <= 1'b0;
                        ex_mem_halt <= 1'b0;
                        ex_mem_illegal <= 1'b0;
                        ex_mem_amo <= 1'b0;
                    end else if (ex_mem_amo_sc) begin
                        if (lr_reservation_valid &&
                            lr_reservation_addr == ex_mem_alu_result[31:2]) begin
                            lr_reservation_valid <= 1'b0;
                            amo_wdata_q <= store_data(ex_mem_amo_width_w ? 3'b010 : 3'b011,
                                                       ex_mem_alu_result[2:0],
                                                       ex_mem_rs2_data);
                            amo_wstrb_q <= amo_store_strobe(ex_mem_amo_width_w,
                                                            ex_mem_alu_result[2:0]);
                            amo_wb_data_q <= 64'd0;
                            amo_state_q <= AMO_WRITE;
                        end else begin
                            lr_reservation_valid <= 1'b0;
                            mem_wb_valid <= ex_mem_reg_write;
                            mem_wb_rd <= ex_mem_rd;
                            mem_wb_reg_write <= ex_mem_reg_write;
                            mem_wb_data <= 64'd1;
                            mem_wb_fp_reg_write <= 1'b0;
                            if (!ex_mem_halt && !ex_mem_illegal) begin
                                minstret_counter <= minstret_counter + 64'd1;
                            end

                            ex_mem_valid <= 1'b0;
                            ex_mem_reg_write <= 1'b0;
                            ex_mem_mem_read <= 1'b0;
                            ex_mem_mem_write <= 1'b0;
                            ex_mem_halt <= 1'b0;
                            ex_mem_illegal <= 1'b0;
                            ex_mem_amo <= 1'b0;
                        end
                    end else begin
                        amo_rdata_q <= dmem_rdata;
                        amo_state_q <= AMO_CALC;
                    end
                end
            end else if (mem_stall) begin
                if (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0) begin
                    if (mem_wb_rd == id_ex_rs1) begin
                        id_ex_rs1_data <= mem_wb_data;
                    end
                    if (mem_wb_rd == id_ex_rs2) begin
                        id_ex_rs2_data <= mem_wb_data;
                    end
                end
                mem_wb_valid <= mem_wb_valid;
                mem_wb_fp_reg_write <= mem_wb_fp_reg_write;
            end else if (execute_stall) begin
                if (mem_wb_valid && mem_wb_reg_write && mem_wb_rd != 5'd0) begin
                    if (mem_wb_rd == id_ex_rs1) begin
                        id_ex_rs1_data <= mem_wb_data;
                    end
                    if (mem_wb_rd == id_ex_rs2) begin
                        id_ex_rs2_data <= mem_wb_data;
                    end
                end

                mem_wb_valid <= ex_mem_valid && !ex_mem_halt && !ex_mem_illegal;
                mem_wb_rd <= ex_mem_rd;
                mem_wb_reg_write <= ex_mem_reg_write;
                mem_wb_data <= (ex_mem_wb_sel == WB_MEM) ?
                               load_data(ex_mem_mem_funct3, ex_mem_alu_result[2:0], dmem_rdata) :
                               ex_mem_wb_data;
                mem_wb_fp_reg_write <= ex_mem_valid && !ex_mem_halt && !ex_mem_illegal &&
                                        ex_mem_fp_reg_write;
                mem_wb_fp_data <= ex_mem_fp_load ?
                                   fp_load_data(ex_mem_mem_funct3, ex_mem_alu_result[2:0], dmem_rdata) :
                                   ex_mem_fp_wb_data;
                if (ex_mem_valid && !ex_mem_halt && !ex_mem_illegal) begin
                    minstret_counter <= minstret_counter + 64'd1;
                    if (ex_mem_fp_fflags != 5'd0) begin
                        csr_fflags <= csr_fflags | ex_mem_fp_fflags;
                    end
                    if (ex_mem_fp_commit) begin
                        csr_mstatus[14:13] <= 2'b11;
                        csr_mstatus[63] <= 1'b1;
                    end
                end
                if (ex_mem_valid && ex_mem_mem_write && lr_reservation_valid &&
                    lr_reservation_addr[29:1] == ex_mem_alu_result[31:3]) begin
                    lr_reservation_valid <= 1'b0;
                end

                if (ex_mem_valid && ex_mem_halt) begin
                    halted_q <= 1'b1;
                end
                if (ex_mem_valid && ex_mem_illegal) begin
                    enter_trap(ex_mem_trap_cause, ex_mem_trap_tval, ex_mem_pc);
                end

                ex_mem_valid <= 1'b0;
                ex_mem_reg_write <= 1'b0;
                ex_mem_fp_reg_write <= 1'b0;
                ex_mem_fp_load <= 1'b0;
                ex_mem_fp_fflags <= 5'd0;
                ex_mem_mem_read <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_halt <= 1'b0;
                ex_mem_illegal <= 1'b0;
                ex_mem_amo <= 1'b0;
            end else begin
                mem_wb_valid <= ex_mem_valid && !ex_mem_halt && !ex_mem_illegal;
                mem_wb_rd <= ex_mem_rd;
                mem_wb_reg_write <= ex_mem_reg_write;
                mem_wb_data <= (ex_mem_wb_sel == WB_MEM) ?
                               load_data(ex_mem_mem_funct3, ex_mem_alu_result[2:0], dmem_rdata) :
                               ex_mem_wb_data;
                mem_wb_fp_reg_write <= ex_mem_valid && !ex_mem_halt && !ex_mem_illegal &&
                                        ex_mem_fp_reg_write;
                mem_wb_fp_data <= ex_mem_fp_load ?
                                   fp_load_data(ex_mem_mem_funct3, ex_mem_alu_result[2:0], dmem_rdata) :
                                   ex_mem_fp_wb_data;
                if (ex_mem_valid && !ex_mem_halt && !ex_mem_illegal) begin
                    minstret_counter <= minstret_counter + 64'd1;
                    if (ex_mem_fp_fflags != 5'd0) begin
                        csr_fflags <= csr_fflags | ex_mem_fp_fflags;
                    end
                    if (ex_mem_fp_commit) begin
                        csr_mstatus[14:13] <= 2'b11;
                        csr_mstatus[63] <= 1'b1;
                    end
                end
                if (ex_mem_valid && ex_mem_mem_write && lr_reservation_valid &&
                    lr_reservation_addr[29:1] == ex_mem_alu_result[31:3]) begin
                    lr_reservation_valid <= 1'b0;
                end

                if (ex_mem_valid && ex_mem_halt) begin
                    halted_q <= 1'b1;
                end else if (ex_mem_valid && ex_mem_illegal) begin
                    enter_trap(ex_mem_trap_cause, ex_mem_trap_tval, ex_mem_pc);
                end else if (interrupt_pending) begin
                    enter_trap(interrupt_cause, 64'd0, interrupt_epc);
                end else begin
                if (id_ex_valid && id_ex_csr && ex_csr_wen && !ex_csr_illegal) begin
                    write_csr(ex_csr_addr, ex_csr_wdata);
                end

                if (ex_ecall) begin
                    enter_trap(ex_trap_cause, 64'd0, id_ex_pc);
                end else if (ex_mret) begin
                    csr_mstatus[3] <= csr_mstatus[7];
                    csr_mstatus[7] <= 1'b1;
                    csr_mstatus[12:11] <= 2'b00;
                    unique case (csr_mstatus[12:11])
                        PRIV_U: current_priv <= PRIV_U;
                        PRIV_S: current_priv <= PRIV_S;
                        default: current_priv <= PRIV_M;
                    endcase
                end else if (ex_sret) begin
                    csr_mstatus[1] <= csr_mstatus[5];
                    csr_mstatus[5] <= 1'b1;
                    csr_mstatus[8] <= 1'b0;
                    if (csr_mstatus[8]) begin
                        current_priv <= PRIV_S;
                    end else begin
                        current_priv <= PRIV_U;
                    end
                end else if (ex_wfi) begin
                    wfi_q <= 1'b1;
                    pc_q <= id_ex_pc + {61'd0, id_ex_instr_len};
                end else if (ex_sfence_vma) begin
                    flush_tlbs();
                end

                ex_mem_valid <= id_ex_valid && !ex_system_redirect;
                ex_mem_pc <= id_ex_pc;
                ex_mem_instr <= id_ex_instr;
                ex_mem_rd <= id_ex_rd;
                ex_mem_reg_write <= id_ex_reg_write && !id_ex_halt && !id_ex_illegal &&
                                    !ex_mem_fault && !ex_csr_illegal && !ex_system_redirect;
                ex_mem_mem_read <= id_ex_mem_read && !id_ex_illegal && !ex_mem_fault;
                ex_mem_mem_write <= id_ex_mem_write && !id_ex_illegal && !ex_mem_fault;
                ex_mem_mem_funct3 <= id_ex_mem_funct3;
                ex_mem_alu_result <= ex_alu_y;
                ex_mem_store_data <= store_data(id_ex_mem_funct3, ex_alu_y[2:0],
                                                id_ex_fp_store ? ex_frs2_data : ex_rs2_data);
                ex_mem_store_strobe <= store_strobe(id_ex_mem_funct3, ex_alu_y[2:0]);
                ex_mem_wb_data <= ex_wb_data;
                ex_mem_fp_reg_write <= ENABLE_FPU && id_ex_fp_reg_write && !id_ex_halt && !id_ex_illegal &&
                                        !ex_mem_fault && !ex_csr_illegal && !ex_system_redirect;
                ex_mem_fp_load <= id_ex_fp_load;
                ex_mem_fp_wb_data <= ex_fp_wb_data;
                ex_mem_fp_fflags <= ex_fp_fflags_w;
                ex_mem_wb_sel <= id_ex_wb_sel;
                ex_mem_halt <= id_ex_halt;
                ex_mem_illegal <= id_ex_illegal || ex_mem_fault || ex_csr_illegal ||
                                  (id_ex_mret && current_priv != PRIV_M) ||
                                  (id_ex_sret && current_priv == PRIV_U) ||
                                  (id_ex_wfi && current_priv == PRIV_U) ||
                                  (id_ex_sfence_vma && current_priv == PRIV_U);
                ex_mem_trap_cause <= (id_ex_mem_read && ex_mem_fault) ? MCAUSE_LOAD_ADDR_MISALIGNED :
                                     (id_ex_mem_write && ex_mem_fault) ? MCAUSE_STORE_ADDR_MISALIGNED :
                                     MCAUSE_ILLEGAL;
                ex_mem_trap_tval <= ((id_ex_mem_read || id_ex_mem_write) && ex_mem_fault) ?
                                    ex_alu_y : {32'd0, id_ex_instr};
                ex_mem_amo <= id_ex_amo && !id_ex_illegal && !ex_mem_fault &&
                              !ex_csr_illegal && !ex_system_redirect;
                ex_mem_rs2_data <= ex_rs2_data;
                amo_state_q <= AMO_READ;

                if (ex_redirect) begin
                    pc_q <= ex_redirect_pc;
                    if_id_valid <= 1'b0;
                    id_ex_valid <= 1'b0;
                    id_ex_fp_reg_write <= 1'b0;
                    id_ex_fp_load <= 1'b0;
                    id_ex_fp_store <= 1'b0;
                    id_ex_fp_to_int <= 1'b0;
                    id_ex_int_to_fp <= 1'b0;
                    id_ex_fp_sgnj <= 1'b0;
                    id_ex_fp_class <= 1'b0;
                    id_ex_fp_cmp <= 1'b0;
                    id_ex_fp_minmax <= 1'b0;
                    id_ex_fp_addsub <= 1'b0;
                    id_ex_fp_mul <= 1'b0;
                    id_ex_fp_divsqrt <= 1'b0;
                    id_ex_fp_fma <= 1'b0;
                    id_ex_fp_cvt <= 1'b0;
                    id_ex_fence_i <= 1'b0;
                    id_ex_sfence_vma <= 1'b0;
                    fetch2_q <= 1'b0;
                end else if (load_use_hazard || fp_raw_hazard) begin
                    id_ex_valid <= 1'b0;
                    id_ex_fp_reg_write <= 1'b0;
                    id_ex_fp_load <= 1'b0;
                    id_ex_fp_store <= 1'b0;
                    id_ex_fp_to_int <= 1'b0;
                    id_ex_int_to_fp <= 1'b0;
                    id_ex_fp_sgnj <= 1'b0;
                    id_ex_fp_class <= 1'b0;
                    id_ex_fp_cmp <= 1'b0;
                    id_ex_fp_minmax <= 1'b0;
                    id_ex_fp_addsub <= 1'b0;
                    id_ex_fp_mul <= 1'b0;
                    id_ex_fp_divsqrt <= 1'b0;
                    id_ex_fp_fma <= 1'b0;
                    id_ex_fp_cvt <= 1'b0;
                    id_ex_fence_i <= 1'b0;
                    id_ex_sfence_vma <= 1'b0;
                end else begin
                    if (if_id_valid) begin
                        id_ex_valid <= 1'b1;
                        id_ex_pc <= if_id_pc;
                        id_ex_instr <= if_id_instr;
                        id_ex_instr_len <= if_id_instr_len;
                        id_ex_rs1 <= (id_uses_rs1 || id_uses_frs1) ? id_rs1 : 5'd0;
                        id_ex_rs2 <= (id_uses_rs2 || id_uses_frs2) ? id_rs2 : 5'd0;
                        id_ex_rs3 <= id_uses_frs3 ? id_rs3 : 5'd0;
                        id_ex_rd <= id_rd;
                        id_ex_rs1_data <= id_uses_rs1 ? id_rs1_data : 64'd0;
                        id_ex_rs2_data <= id_uses_rs2 ? id_rs2_data : 64'd0;
                        id_ex_imm <= id_imm;
                        id_ex_alu_op <= id_alu_op;
                        id_ex_alu_a_pc <= id_alu_a_pc;
                        id_ex_alu_b_imm <= id_alu_b_imm;
                        id_ex_reg_write <= id_reg_write;
                        id_ex_mem_read <= id_mem_read;
                        id_ex_mem_write <= id_mem_write;
                        id_ex_mem_funct3 <= id_funct3;
                        id_ex_wb_sel <= id_wb_sel;
                        id_ex_branch <= id_branch;
                        id_ex_jump <= id_jump;
                        id_ex_jalr <= id_jalr;
                        id_ex_muldiv <= id_muldiv;
                        id_ex_amo <= id_amo;
                        id_ex_csr <= id_csr;
                        id_ex_fp_reg_write <= id_fp_reg_write;
                        id_ex_fp_load <= id_fp_load;
                        id_ex_fp_store <= id_fp_store;
                        id_ex_fp_to_int <= id_fp_to_int;
                        id_ex_int_to_fp <= id_int_to_fp;
                        id_ex_fp_sgnj <= id_fp_sgnj;
                        id_ex_fp_class <= id_fp_class;
                        id_ex_fp_cmp <= id_fp_cmp;
                        id_ex_fp_minmax <= id_fp_minmax;
                        id_ex_fp_addsub <= id_fp_addsub;
                        id_ex_fp_mul <= id_fp_mul;
                        id_ex_fp_divsqrt <= id_fp_divsqrt;
                        id_ex_fp_fma <= id_fp_fma;
                        id_ex_fp_cvt <= id_fp_cvt;
                        id_ex_frs1_data <= id_uses_frs1 ? id_frs1_data : 64'd0;
                        id_ex_frs2_data <= id_uses_frs2 ? id_frs2_data : 64'd0;
                        id_ex_frs3_data <= id_uses_frs3 ? id_frs3_data : 64'd0;
                        id_ex_ecall <= id_ecall;
                        id_ex_wfi <= id_wfi;
                        id_ex_fence_i <= id_fence_i;
                        id_ex_sfence_vma <= id_sfence_vma;
                        id_ex_mret <= id_mret;
                        id_ex_sret <= id_sret;
                        id_ex_halt <= id_halt;
                        id_ex_illegal <= id_illegal;
                    end else begin
                        id_ex_valid <= 1'b0;
                        id_ex_fp_reg_write <= 1'b0;
                        id_ex_fp_load <= 1'b0;
                        id_ex_fp_store <= 1'b0;
                        id_ex_fp_to_int <= 1'b0;
                        id_ex_int_to_fp <= 1'b0;
                        id_ex_fp_sgnj <= 1'b0;
                        id_ex_fp_class <= 1'b0;
                        id_ex_fp_cmp <= 1'b0;
                        id_ex_fp_minmax <= 1'b0;
                        id_ex_fp_addsub <= 1'b0;
                        id_ex_fp_mul <= 1'b0;
                        id_ex_fp_divsqrt <= 1'b0;
                        id_ex_fp_fma <= 1'b0;
                        id_ex_fp_cvt <= 1'b0;
                        id_ex_fence_i <= 1'b0;
                        id_ex_sfence_vma <= 1'b0;
                    end

                    if (fetch_accept) begin
                        if (fetch2_q) begin
                            if_id_valid <= 1'b1;
                            if_id_pc <= fetch2_pc_q;
                            if_id_instr <= {imem_rdata[15:0], fetch2_upper_half_q};
                            if_id_instr_len <= 3'd4;
                            pc_q <= fetch2_pc_q + 64'd4;
                            fetch2_q <= 1'b0;
                        end else if ((pc_q[1] ? imem_rdata[17:16] : imem_rdata[1:0]) != 2'b11) begin
                            if_id_valid <= 1'b1;
                            if_id_pc <= pc_q;
                            if_id_instr <= expand_compressed(pc_q[1] ? imem_rdata[31:16] : imem_rdata[15:0]);
                            if_id_instr_len <= 3'd2;
                            pc_q <= pc_q + 64'd2;
                        end else if (!pc_q[1]) begin
                            if_id_valid <= 1'b1;
                            if_id_pc <= pc_q;
                            if_id_instr <= imem_rdata;
                            if_id_instr_len <= 3'd4;
                            pc_q <= pc_q + 64'd4;
                        end else begin
                            if_id_valid <= 1'b0;
                            fetch2_q <= 1'b1;
                            fetch2_pc_q <= pc_q;
                            fetch2_upper_half_q <= imem_rdata[31:16];
                        end
                    end else if (if_id_valid) begin
                        if_id_valid <= 1'b0;
                    end
                end
                end
            end
        end
    end
endmodule
