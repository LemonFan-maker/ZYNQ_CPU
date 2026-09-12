`include "cpu_defs.svh"
`include "cpu64_defs.svh"

module zx64_core (
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

    output logic        halted,
    output logic        illegal_instr,
    output logic [31:0] dbg_state,
    output logic [63:0] dbg_pc,
    output logic [31:0] dbg_instr
);
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
    localparam logic [63:0] CSR_MISA_VALUE = 64'h8000_0000_0004_1105; // RV64IMAC + S-mode.
    localparam logic [63:0] SSTATUS_MASK = 64'h0000_0003_000c_f122;
    localparam logic [63:0] MSTATUS_RESET = 64'h0000_000a_0000_1800;
    localparam logic [63:0] MCAUSE_ILLEGAL = 64'd2;
    localparam logic [63:0] MCAUSE_BREAKPOINT = 64'd3;
    localparam logic [63:0] MCAUSE_ECALL_U = 64'd8;
    localparam logic [63:0] MCAUSE_ECALL_S = 64'd9;
    localparam logic [63:0] MCAUSE_ECALL_M = 64'd11;
    localparam logic [63:0] MCAUSE_INST_PAGE_FAULT = 64'd12;
    localparam logic [63:0] MCAUSE_LOAD_PAGE_FAULT = 64'd13;
    localparam logic [63:0] MCAUSE_STORE_PAGE_FAULT = 64'd15;
    localparam logic [63:0] MCAUSE_INTERRUPT = 64'h8000_0000_0000_0000;
    localparam int          IRQ_S_TIMER = 5;
    localparam int          IRQ_M_TIMER = 7;
    localparam int          IRQ_S_EXT = 9;
    localparam int          IRQ_M_EXT = 11;
    localparam logic [63:0] MIP_STIP = 64'h0000_0000_0000_0020;
    localparam logic [63:0] MIP_MTIP = 64'h0000_0000_0000_0080;
    localparam logic [63:0] MIP_SEIP = 64'h0000_0000_0000_0200;
    localparam logic [63:0] MIP_MEIP = 64'h0000_0000_0000_0800;
    localparam int          TLB_ENTRIES = 16;
    localparam int          TLB_INDEX_BITS = $clog2(TLB_ENTRIES);

    typedef enum logic [1:0] {
        PRIV_U = 2'b00,
        PRIV_S = 2'b01,
        PRIV_M = 2'b11
    } priv_mode_t;

    typedef enum logic [3:0] {
        ST_RESET,
        ST_FETCH,
        ST_FETCH2,
        ST_DECODE,
        ST_PT_L2,
        ST_PT_L1,
        ST_PT_L0,
        ST_MEMORY,
        ST_AMO_LOAD,
        ST_AMO_STORE,
        ST_WRITEBACK,
        ST_WFI,
        ST_HALT
    } state_t;

    state_t state;

    logic [63:0] pc;
    logic [31:0] instr_q;
    logic [2:0]  instr_len_q;
    logic [15:0] fetch_upper_half_q;
    logic [63:0] pc_next_q;

    logic        wb_enable_q;
    logic [4:0]  wb_rd_q;
    logic [63:0] wb_data_q;

    logic        mem_load_q;
    logic        mem_we_q;
    logic [2:0]  mem_funct3_q;
    logic [4:0]  mem_rd_q;
    logic [63:0] mem_addr_q;
    logic [63:0] mem_wdata_q;
    logic [7:0]  mem_wstrb_q;
    logic [63:0] amo_wb_data_q;
    logic        translate_active;
    logic        fetch_pa_valid;
    logic [31:0] fetch_paddr_q;
    logic        data_pa_valid;
    logic [31:0] data_paddr_q;
    logic [63:0] ptw_vaddr_q;
    logic        ptw_is_fetch_q;
    logic        ptw_we_q;
    state_t      ptw_return_state_q;
    logic [31:0] ptw_pte_addr_q;
    logic [63:0] ptw_l2_pte_q;
    logic [63:0] ptw_l1_pte_q;

    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [6:0]  opcode;
    logic [63:0] rs1_data;
    logic [63:0] rs2_data;
    logic [63:0] alu_y;
    logic [63:0] alu_a;
    logic [63:0] alu_b;
    alu_op_t     alu_op;
    priv_mode_t  current_priv;
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
    logic [11:0] csr_addr;
    logic [63:0] csr_rdata;
    logic [63:0] csr_operand;
    logic [63:0] csr_wdata;
    logic        csr_supported;
    logic        csr_priv_ok;
    logic        csr_read_only;
    logic        csr_counter_access_ok;
    logic        csr_wen;
    logic        system_csr;
    logic        system_ecall;
    logic        system_ebreak;
    logic        system_sret;
    logic        system_mret;
    logic        system_wfi;
    logic        system_sfence_vma;
    logic [63:0] trap_cause;
    logic        trap_to_s;
    logic [63:0] interrupt_cause;
    logic        interrupt_pending;
    logic [4:0]  amo_funct5;
    logic        amo_width_w;
    logic        amo_width_d;
    logic        amo_lr;
    logic        amo_sc;
    logic        amo_supported;
    logic        lr_reservation_valid;
    logic [29:0] lr_reservation_addr;
    logic [63:0] pc_seq;
    logic [TLB_ENTRIES-1:0]      itlb_valid;
    logic [TLB_ENTRIES-1:0]      dtlb_valid;
    logic [26:0]                 itlb_vpn_tags [0:TLB_ENTRIES-1];
    logic [26:0]                 dtlb_vpn_tags [0:TLB_ENTRIES-1];
    logic [63:0]                 itlb_ptes [0:TLB_ENTRIES-1];
    logic [63:0]                 dtlb_ptes [0:TLB_ENTRIES-1];
    logic [1:0]                  itlb_levels [0:TLB_ENTRIES-1];
    logic [1:0]                  dtlb_levels [0:TLB_ENTRIES-1];

    assign opcode = instr_q[6:0];
    assign rd     = instr_q[11:7];
    assign funct3 = instr_q[14:12];
    assign rs1    = instr_q[19:15];
    assign rs2    = instr_q[24:20];
    assign funct7 = instr_q[31:25];
    assign csr_addr = instr_q[31:20];
    assign system_csr = (opcode == OPCODE64_SYSTEM) && (funct3 != 3'b000);
    assign system_ecall = (opcode == OPCODE64_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h000);
    assign system_ebreak = (opcode == OPCODE64_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h001);
    assign system_sret = (opcode == OPCODE64_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h102);
    assign system_mret = (opcode == OPCODE64_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h302);
    assign system_wfi = (opcode == OPCODE64_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h105);
    assign system_sfence_vma = (opcode == OPCODE64_SYSTEM) && (funct3 == 3'b000) && (funct7 == 7'b0001001);
    assign csr_operand = funct3[2] ? {59'd0, rs1} : rs1_data;
    assign csr_wen = system_csr && ((funct3 == 3'b001) || (funct3 == 3'b101) || (rs1 != 5'd0));
    assign trap_cause = (current_priv == PRIV_S) ? MCAUSE_ECALL_S :
                        (current_priv == PRIV_U) ? MCAUSE_ECALL_U : MCAUSE_ECALL_M;
    assign trap_to_s = (current_priv != PRIV_M) && csr_medeleg[trap_cause[5:0]];
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
    assign amo_funct5 = instr_q[31:27];
    assign amo_width_w = (opcode == OPCODE64_AMO) && (funct3 == 3'b010);
    assign amo_width_d = (opcode == OPCODE64_AMO) && (funct3 == 3'b011);
    assign amo_lr = (opcode == OPCODE64_AMO) && (amo_funct5 == 5'b00010) && (rs2 == 5'd0);
    assign amo_sc = (opcode == OPCODE64_AMO) && (amo_funct5 == 5'b00011);
    assign amo_supported = (opcode == OPCODE64_AMO) && (amo_width_w || amo_width_d) &&
                           (amo_lr || amo_sc ||
                            amo_funct5 == 5'b00000 || amo_funct5 == 5'b00001 ||
                            amo_funct5 == 5'b00100 || amo_funct5 == 5'b01000 ||
                            amo_funct5 == 5'b01100 || amo_funct5 == 5'b10000 ||
                            amo_funct5 == 5'b10100 || amo_funct5 == 5'b11000 ||
                            amo_funct5 == 5'b11100);

    assign translate_active = (csr_satp[63:60] == 4'h8) && (current_priv != PRIV_M);
    assign pc_seq = pc + {61'd0, instr_len_q};
    assign imem_valid = ((state == ST_FETCH) && (!translate_active || fetch_pa_valid)) ||
                        (state == ST_FETCH2);
    assign imem_addr  = (state == ST_FETCH2) ?
                        ((translate_active && fetch_pa_valid) ? (fetch_paddr_q + 32'd2) : (pc[31:0] + 32'd2)) :
                        ((translate_active && fetch_pa_valid) ? fetch_paddr_q : pc[31:0]);

    assign dmem_valid = (state == ST_MEMORY) || (state == ST_AMO_LOAD) || (state == ST_AMO_STORE) ||
                        (state == ST_PT_L2) || (state == ST_PT_L1) || (state == ST_PT_L0);
    assign dmem_we    = ((state == ST_PT_L2) || (state == ST_PT_L1) || (state == ST_PT_L0)) ? 1'b0 : mem_we_q;
    assign dmem_addr  = ((state == ST_PT_L2) || (state == ST_PT_L1) || (state == ST_PT_L0)) ? ptw_pte_addr_q :
                        ((translate_active && data_pa_valid) ? data_paddr_q : mem_addr_q[31:0]);
    assign dmem_wdata = mem_wdata_q;
    assign dmem_wstrb = ((state == ST_PT_L2) || (state == ST_PT_L1) || (state == ST_PT_L0)) ? 8'd0 : mem_wstrb_q;

    assign halted   = (state == ST_HALT);
    assign dbg_state = {28'd0, state};
    assign dbg_pc    = pc;
    assign dbg_instr = instr_q;

    regfile64 u_regfile (
        .clk(clk),
        .wen(state == ST_WRITEBACK && wb_enable_q),
        .waddr(wb_rd_q),
        .wdata(wb_data_q),
        .raddr1(rs1),
        .rdata1(rs1_data),
        .raddr2(rs2),
        .rdata2(rs2_data)
    );

    alu64 u_alu (
        .op(alu_op),
        .a(alu_a),
        .b(alu_b),
        .y(alu_y)
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
                        3'b000: begin // c.addi4spn
                            imm12 = {2'b00, c[10:7], c[12:11], c[5], c[6], 2'b00};
                            if (imm12 != 12'd0) begin
                                expand_compressed = enc_i32(imm12, 5'd2, 3'b000, rdp_i, OPCODE64_OP_IMM);
                            end
                        end
                        3'b010: begin // c.lw
                            imm12 = {5'd0, c[5], c[12:10], c[6], 2'b00};
                            expand_compressed = enc_i32(imm12, rs1p_i, 3'b010, rdp_i, OPCODE64_LOAD);
                        end
                        3'b011: begin // c.ld
                            imm12 = {4'd0, c[6:5], c[12:10], 3'b000};
                            expand_compressed = enc_i32(imm12, rs1p_i, 3'b011, rdp_i, OPCODE64_LOAD);
                        end
                        3'b110: begin // c.sw
                            imm12 = {5'd0, c[5], c[12:10], c[6], 2'b00};
                            expand_compressed = enc_s32(imm12, rs2p_i, rs1p_i, 3'b010, OPCODE64_STORE);
                        end
                        3'b111: begin // c.sd
                            imm12 = {4'd0, c[6:5], c[12:10], 3'b000};
                            expand_compressed = enc_s32(imm12, rs2p_i, rs1p_i, 3'b011, OPCODE64_STORE);
                        end
                        default: begin
                            expand_compressed = 32'd0;
                        end
                    endcase
                end

                2'b01: begin
                    unique case (c[15:13])
                        3'b000: begin // c.addi / c.nop
                            imm12 = {{6{c[12]}}, c[12], c[6:2]};
                            expand_compressed = enc_i32(imm12, rd_i, 3'b000, rd_i, OPCODE64_OP_IMM);
                        end
                        3'b001: begin // c.addiw on RV64
                            imm12 = {{6{c[12]}}, c[12], c[6:2]};
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32(imm12, rd_i, 3'b000, rd_i, OPCODE64_OP_IMM_32);
                            end
                        end
                        3'b010: begin // c.li
                            imm12 = {{6{c[12]}}, c[12], c[6:2]};
                            expand_compressed = enc_i32(imm12, 5'd0, 3'b000, rd_i, OPCODE64_OP_IMM);
                        end
                        3'b011: begin
                            if (rd_i == 5'd2) begin // c.addi16sp
                                imm12 = {{2{c[12]}}, c[12], c[4:3], c[5], c[2], c[6], 4'b0000};
                                if (imm12 != 12'd0) begin
                                    expand_compressed = enc_i32(imm12, 5'd2, 3'b000, 5'd2, OPCODE64_OP_IMM);
                                end
                            end else if (rd_i != 5'd0) begin // c.lui
                                imm20 = {{14{c[12]}}, c[12], c[6:2]};
                                if (c[12] || c[6:2] != 5'd0) begin
                                    expand_compressed = enc_u32(imm20, rd_i, OPCODE64_LUI);
                                end
                            end
                        end
                        3'b100: begin
                            unique case (c[11:10])
                                2'b00: begin // c.srli
                                    expand_compressed = enc_i32({6'b000000, shamt6}, rs1p_i, 3'b101,
                                                                rs1p_i, OPCODE64_OP_IMM);
                                end
                                2'b01: begin // c.srai
                                    expand_compressed = enc_i32({6'b010000, shamt6}, rs1p_i, 3'b101,
                                                                rs1p_i, OPCODE64_OP_IMM);
                                end
                                2'b10: begin // c.andi
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
                                default: begin
                                    expand_compressed = 32'd0;
                                end
                            endcase
                        end
                        3'b101: begin // c.j
                            imm21 = {{9{c[12]}}, c[12], c[8], c[10:9], c[6], c[7],
                                     c[2], c[11], c[5:3], 1'b0};
                            expand_compressed = enc_j32(imm21, 5'd0, OPCODE64_JAL);
                        end
                        3'b110: begin // c.beqz
                            imm13 = {{4{c[12]}}, c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};
                            expand_compressed = enc_b32(imm13, 5'd0, rs1p_i, 3'b000, OPCODE64_BRANCH);
                        end
                        3'b111: begin // c.bnez
                            imm13 = {{4{c[12]}}, c[12], c[6:5], c[2], c[11:10], c[4:3], 1'b0};
                            expand_compressed = enc_b32(imm13, 5'd0, rs1p_i, 3'b001, OPCODE64_BRANCH);
                        end
                        default: begin
                            expand_compressed = 32'd0;
                        end
                    endcase
                end

                2'b10: begin
                    unique case (c[15:13])
                        3'b000: begin // c.slli
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32({6'b000000, shamt6}, rd_i, 3'b001,
                                                            rd_i, OPCODE64_OP_IMM);
                            end
                        end
                        3'b010: begin // c.lwsp
                            imm12 = {4'd0, c[3:2], c[12], c[6:4], 2'b00};
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32(imm12, 5'd2, 3'b010, rd_i, OPCODE64_LOAD);
                            end
                        end
                        3'b011: begin // c.ldsp
                            imm12 = {3'd0, c[4:2], c[12], c[6:5], 3'b000};
                            if (rd_i != 5'd0) begin
                                expand_compressed = enc_i32(imm12, 5'd2, 3'b011, rd_i, OPCODE64_LOAD);
                            end
                        end
                        3'b100: begin
                            if (!c[12] && rs2_i != 5'd0) begin // c.mv
                                expand_compressed = enc_r32(7'b0000000, rs2_i, 5'd0, 3'b000, rd_i, OPCODE64_OP);
                            end else if (!c[12] && rs2_i == 5'd0 && rd_i != 5'd0) begin // c.jr
                                expand_compressed = enc_i32(12'd0, rd_i, 3'b000, 5'd0, OPCODE64_JALR);
                            end else if (c[12] && rd_i == 5'd0 && rs2_i == 5'd0) begin // c.ebreak
                                expand_compressed = 32'h0010_0073;
                            end else if (c[12] && rs2_i == 5'd0 && rd_i != 5'd0) begin // c.jalr
                                expand_compressed = enc_i32(12'd0, rd_i, 3'b000, 5'd1, OPCODE64_JALR);
                            end else if (c[12] && rd_i != 5'd0 && rs2_i != 5'd0) begin // c.add
                                expand_compressed = enc_r32(7'b0000000, rs2_i, rd_i, 3'b000, rd_i, OPCODE64_OP);
                            end
                        end
                        3'b110: begin // c.swsp
                            imm12 = {4'd0, c[8:7], c[12:9], 2'b00};
                            expand_compressed = enc_s32(imm12, rs2_i, 5'd2, 3'b010, OPCODE64_STORE);
                        end
                        3'b111: begin // c.sdsp
                            imm12 = {3'd0, c[9:7], c[12:10], 3'b000};
                            expand_compressed = enc_s32(imm12, rs2_i, 5'd2, 3'b011, OPCODE64_STORE);
                        end
                        default: begin
                            expand_compressed = 32'd0;
                        end
                    endcase
                end

                default: begin
                    expand_compressed = 32'd0;
                end
            endcase
        end
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

    function automatic logic [31:0] amo_result32(input logic [4:0] f5,
                                                 input logic [31:0] old_word,
                                                 input logic [31:0] rs2_word);
        begin
            case (f5)
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
            case (f5)
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

    function automatic logic branch_supported(input logic [2:0] f3);
        branch_supported = (f3 == 3'b000) || (f3 == 3'b001) ||
                           (f3 == 3'b100) || (f3 == 3'b101) ||
                           (f3 == 3'b110) || (f3 == 3'b111);
    endfunction

    function automatic logic counter_access_ok(input logic [11:0] csr,
                                               input priv_mode_t priv,
                                               input logic [63:0] mcounteren,
                                               input logic [63:0] scounteren);
        logic [5:0] counter_bit;
        logic       is_counter;
        begin
            is_counter = 1'b1;
            case (csr)
                CSR_CYCLE:   counter_bit = 6'd0;
                CSR_TIME:    counter_bit = 6'd1;
                CSR_INSTRET: counter_bit = 6'd2;
                default: begin
                    is_counter = 1'b0;
                    counter_bit = 6'd0;
                end
            endcase

            if (!is_counter || priv == PRIV_M) begin
                counter_access_ok = 1'b1;
            end else if (priv == PRIV_S) begin
                counter_access_ok = mcounteren[counter_bit];
            end else begin
                counter_access_ok = mcounteren[counter_bit] && scounteren[counter_bit];
            end
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

    task automatic issue_wb(input logic [4:0] out_rd,
                            input logic [63:0] out_data,
                            input logic [63:0] out_next_pc);
        begin
            wb_enable_q <= 1'b1;
            wb_rd_q <= out_rd;
            wb_data_q <= out_data;
            pc_next_q <= out_next_pc;
            state <= ST_WRITEBACK;
        end
    endtask

    task automatic halt_illegal;
        begin
            illegal_instr <= 1'b1;
            state <= ST_HALT;
        end
    endtask

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

    task automatic translate_fetch_or_walk;
        logic [TLB_INDEX_BITS-1:0] tlb_index;
        begin
            tlb_index = pc[TLB_INDEX_BITS+11:12];
            if (sv39_canonical(pc) &&
                itlb_valid[tlb_index] &&
                tlb_tag_match(pc, itlb_vpn_tags[tlb_index], itlb_levels[tlb_index]) &&
                sv39_access_ok(itlb_ptes[tlb_index], current_priv, 1'b1, 1'b0, csr_mstatus)) begin
                fetch_paddr_q <= sv39_leaf_paddr(itlb_ptes[tlb_index], pc, itlb_levels[tlb_index]);
                fetch_pa_valid <= 1'b1;
                state <= ST_FETCH;
            end else begin
                start_ptw(pc, 1'b1, 1'b0, ST_FETCH);
            end
        end
    endtask

    task automatic translate_data_or_walk(input logic [63:0] vaddr,
                                          input logic is_store,
                                          input state_t return_state);
        logic [TLB_INDEX_BITS-1:0] tlb_index;
        begin
            tlb_index = vaddr[TLB_INDEX_BITS+11:12];
            if (sv39_canonical(vaddr) &&
                dtlb_valid[tlb_index] &&
                tlb_tag_match(vaddr, dtlb_vpn_tags[tlb_index], dtlb_levels[tlb_index]) &&
                sv39_access_ok(dtlb_ptes[tlb_index], current_priv, 1'b0, is_store, csr_mstatus)) begin
                data_paddr_q <= sv39_leaf_paddr(dtlb_ptes[tlb_index], vaddr, dtlb_levels[tlb_index]);
                data_pa_valid <= 1'b1;
                state <= return_state;
            end else begin
                start_ptw(vaddr, 1'b0, is_store, return_state);
            end
        end
    endtask

    task automatic enter_trap(input logic [63:0] cause,
                              input logic [63:0] tval,
                              input logic [63:0] epc);
        begin
            fetch_pa_valid <= 1'b0;
            data_pa_valid <= 1'b0;
            if ((current_priv != PRIV_M) &&
                (cause[63] ? csr_mideleg[cause[5:0]] : csr_medeleg[cause[5:0]])) begin
                csr_sepc <= {epc[63:1], 1'b0};
                csr_scause <= cause;
                csr_stval <= tval;
                csr_mstatus[5] <= csr_mstatus[1];
                csr_mstatus[1] <= 1'b0;
                csr_mstatus[8] <= (current_priv == PRIV_S);
                current_priv <= PRIV_S;
                pc <= {csr_stvec[63:2], 2'b00};
            end else begin
                csr_mepc <= {epc[63:1], 1'b0};
                csr_mcause <= cause;
                csr_mtval <= tval;
                csr_mstatus[7] <= csr_mstatus[3];
                csr_mstatus[3] <= 1'b0;
                csr_mstatus[12:11] <= current_priv;
                current_priv <= PRIV_M;
                pc <= {csr_mtvec[63:2], 2'b00};
            end
            state <= ST_FETCH;
        end
    endtask

    task automatic start_ptw(input logic [63:0] vaddr,
                             input logic is_fetch,
                             input logic is_store,
                             input state_t return_state);
        begin
            ptw_vaddr_q <= vaddr;
            ptw_is_fetch_q <= is_fetch;
            ptw_we_q <= is_store;
            ptw_return_state_q <= return_state;
            ptw_l2_pte_q <= 64'd0;
            ptw_l1_pte_q <= 64'd0;
            if (!sv39_canonical(vaddr)) begin
                enter_trap(ptw_fault_cause(is_fetch, is_store), vaddr, pc);
            end else begin
                ptw_pte_addr_q <= sv39_pte_addr(csr_satp[43:0], vaddr, 2'd2);
                state <= ST_PT_L2;
            end
        end
    endtask

    task automatic write_csr(input logic [11:0] addr, input logic [63:0] data);
        begin
            case (addr)
                CSR_SSTATUS:   csr_mstatus <= (csr_mstatus & ~SSTATUS_MASK) | (data & SSTATUS_MASK);
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
                CSR_MSTATUS:  csr_mstatus <= data;
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

    function automatic logic [127:0] abs_product64(input logic [63:0] a,
                                                   input logic [63:0] b,
                                                   input logic signed_a,
                                                   input logic signed_b);
        logic neg;
        logic [63:0] abs_a;
        logic [63:0] abs_b;
        logic [127:0] prod_abs;
        begin
            neg = (signed_a && a[63]) ^ (signed_b && b[63]);
            abs_a = (signed_a && a[63]) ? (~a + 64'd1) : a;
            abs_b = (signed_b && b[63]) ? (~b + 64'd1) : b;
            prod_abs = abs_a * abs_b;
            abs_product64 = neg ? (~prod_abs + 128'd1) : prod_abs;
        end
    endfunction

    function automatic logic [63:0] div64_signed(input logic [63:0] dividend,
                                                 input logic [63:0] divisor);
        begin
            if (divisor == 64'd0) begin
                div64_signed = 64'hffff_ffff_ffff_ffff;
            end else if (dividend == 64'h8000_0000_0000_0000 &&
                         divisor == 64'hffff_ffff_ffff_ffff) begin
                div64_signed = dividend;
            end else begin
                div64_signed = $signed(dividend) / $signed(divisor);
            end
        end
    endfunction

    function automatic logic [63:0] rem64_signed(input logic [63:0] dividend,
                                                 input logic [63:0] divisor);
        begin
            if (divisor == 64'd0) begin
                rem64_signed = dividend;
            end else if (dividend == 64'h8000_0000_0000_0000 &&
                         divisor == 64'hffff_ffff_ffff_ffff) begin
                rem64_signed = 64'd0;
            end else begin
                rem64_signed = $signed(dividend) % $signed(divisor);
            end
        end
    endfunction

    function automatic logic [63:0] div32_signed(input logic [31:0] dividend,
                                                 input logic [31:0] divisor);
        logic [31:0] q;
        begin
            if (divisor == 32'd0) begin
                q = 32'hffff_ffff;
            end else if (dividend == 32'h8000_0000 && divisor == 32'hffff_ffff) begin
                q = dividend;
            end else begin
                q = $signed(dividend) / $signed(divisor);
            end
            div32_signed = sext32(q);
        end
    endfunction

    function automatic logic [63:0] rem32_signed(input logic [31:0] dividend,
                                                 input logic [31:0] divisor);
        logic [31:0] r;
        begin
            if (divisor == 32'd0) begin
                r = dividend;
            end else if (dividend == 32'h8000_0000 && divisor == 32'hffff_ffff) begin
                r = 32'd0;
            end else begin
                r = $signed(dividend) % $signed(divisor);
            end
            rem32_signed = sext32(r);
        end
    endfunction

    function automatic logic [63:0] rv64m_result(input logic [2:0] f3,
                                                 input logic [63:0] a,
                                                 input logic [63:0] b);
        logic [127:0] product;
        begin
            case (f3)
                3'b000: rv64m_result = (a * b);
                3'b001: begin
                    product = abs_product64(a, b, 1'b1, 1'b1);
                    rv64m_result = product[127:64];
                end
                3'b010: begin
                    product = abs_product64(a, b, 1'b1, 1'b0);
                    rv64m_result = product[127:64];
                end
                3'b011: begin
                    product = a * b;
                    rv64m_result = product[127:64];
                end
                3'b100: rv64m_result = div64_signed(a, b);
                3'b101: rv64m_result = (b == 64'd0) ? 64'hffff_ffff_ffff_ffff : (a / b);
                3'b110: rv64m_result = rem64_signed(a, b);
                3'b111: rv64m_result = (b == 64'd0) ? a : (a % b);
                default: rv64m_result = 64'd0;
            endcase
        end
    endfunction

    function automatic logic [63:0] rv64m_w_result(input logic [2:0] f3,
                                                   input logic [63:0] a,
                                                   input logic [63:0] b);
        logic [31:0] result32;
        begin
            case (f3)
                3'b000: begin
                    result32 = a[31:0] * b[31:0];
                    rv64m_w_result = sext32(result32);
                end
                3'b100: rv64m_w_result = div32_signed(a[31:0], b[31:0]);
                3'b101: begin
                    result32 = (b[31:0] == 32'd0) ? 32'hffff_ffff : (a[31:0] / b[31:0]);
                    rv64m_w_result = sext32(result32);
                end
                3'b110: rv64m_w_result = rem32_signed(a[31:0], b[31:0]);
                3'b111: begin
                    result32 = (b[31:0] == 32'd0) ? a[31:0] : (a[31:0] % b[31:0]);
                    rv64m_w_result = sext32(result32);
                end
                default: rv64m_w_result = 64'd0;
            endcase
        end
    endfunction

    always_comb begin
        csr_supported = 1'b1;
        csr_priv_ok = (current_priv >= csr_addr[9:8]);
        csr_read_only = (csr_addr[11:10] == 2'b11);
        csr_counter_access_ok = counter_access_ok(csr_addr, current_priv, csr_mcounteren, csr_scounteren);
        csr_priv_ok = csr_priv_ok && csr_counter_access_ok;
        case (csr_addr)
            CSR_SSTATUS:  csr_rdata = csr_mstatus & SSTATUS_MASK;
            CSR_SIE:      csr_rdata = csr_sie;
            CSR_STVEC:    csr_rdata = csr_stvec;
            CSR_SCOUNTEREN: csr_rdata = csr_scounteren;
            CSR_SSCRATCH: csr_rdata = csr_sscratch;
            CSR_SEPC:     csr_rdata = csr_sepc;
            CSR_SCAUSE:   csr_rdata = csr_scause;
            CSR_STVAL:    csr_rdata = csr_stval;
            CSR_SIP:      csr_rdata = csr_sip_view;
            CSR_SATP:     csr_rdata = csr_satp;
            CSR_MSTATUS:   csr_rdata = csr_mstatus;
            CSR_MISA:      csr_rdata = CSR_MISA_VALUE;
            CSR_MEDELEG:   csr_rdata = csr_medeleg;
            CSR_MIDELEG:   csr_rdata = csr_mideleg;
            CSR_MIE:       csr_rdata = csr_mie;
            CSR_MCOUNTEREN: csr_rdata = csr_mcounteren;
            CSR_MTVEC:     csr_rdata = csr_mtvec;
            CSR_MSCRATCH:  csr_rdata = csr_mscratch;
            CSR_MEPC:      csr_rdata = csr_mepc;
            CSR_MCAUSE:    csr_rdata = csr_mcause;
            CSR_MTVAL:     csr_rdata = csr_mtval;
            CSR_MIP:       csr_rdata = csr_mip_view;
            CSR_MCYCLE:    csr_rdata = mcycle_counter;
            CSR_MINSTRET:  csr_rdata = minstret_counter;
            CSR_CYCLE:     csr_rdata = mcycle_counter;
            CSR_TIME:      csr_rdata = mcycle_counter;
            CSR_INSTRET:   csr_rdata = minstret_counter;
            CSR_MVENDORID: csr_rdata = 64'd0;
            CSR_MARCHID:   csr_rdata = 64'h0000_0000_0000_5a64;
            CSR_MIMPID:    csr_rdata = 64'd1;
            CSR_MHARTID:   csr_rdata = 64'd0;
            default: begin
                csr_rdata = 64'd0;
                csr_supported = 1'b0;
            end
        endcase

        case (funct3)
            3'b001, 3'b101: csr_wdata = csr_operand;
            3'b010, 3'b110: csr_wdata = csr_rdata | csr_operand;
            3'b011, 3'b111: csr_wdata = csr_rdata & ~csr_operand;
            default:        csr_wdata = csr_rdata;
        endcase
    end

    always_comb begin
        alu_a = rs1_data;
        alu_b = rs2_data;
        alu_op = ALU_ADD;

        case (opcode)
            OPCODE64_OP_IMM: begin
                alu_b = imm_i(instr_q);
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: begin
                        if (instr_q[31:26] == 6'b010000) begin
                            alu_op = ALU_SRA;
                        end else begin
                            alu_op = ALU_SRL;
                        end
                    end
                    default: alu_op = ALU_ADD;
                endcase
            end

            OPCODE64_OP: begin
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: alu_op = ALU_ADD;
                    {7'b0100000, 3'b000}: alu_op = ALU_SUB;
                    {7'b0000000, 3'b001}: alu_op = ALU_SLL;
                    {7'b0000000, 3'b010}: alu_op = ALU_SLT;
                    {7'b0000000, 3'b011}: alu_op = ALU_SLTU;
                    {7'b0000000, 3'b100}: alu_op = ALU_XOR;
                    {7'b0000000, 3'b101}: alu_op = ALU_SRL;
                    {7'b0100000, 3'b101}: alu_op = ALU_SRA;
                    {7'b0000000, 3'b110}: alu_op = ALU_OR;
                    {7'b0000000, 3'b111}: alu_op = ALU_AND;
                    default:              alu_op = ALU_ADD;
                endcase
            end

            default: begin
                alu_a = rs1_data;
                alu_b = rs2_data;
                alu_op = ALU_ADD;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        logic [63:0] addr_calc;
        logic [63:0] op_result;
        if (!rst_n) begin
            state <= ST_RESET;
            pc <= 64'd0;
            instr_q <= 32'd0;
            instr_len_q <= 3'd4;
            fetch_upper_half_q <= 16'd0;
            pc_next_q <= 64'd0;
            wb_enable_q <= 1'b0;
            wb_rd_q <= 5'd0;
            wb_data_q <= 64'd0;
            mem_load_q <= 1'b0;
            mem_we_q <= 1'b0;
            mem_funct3_q <= 3'd0;
            mem_rd_q <= 5'd0;
            mem_addr_q <= 64'd0;
            mem_wdata_q <= 64'd0;
            mem_wstrb_q <= 8'd0;
            amo_wb_data_q <= 64'd0;
            fetch_pa_valid <= 1'b0;
            fetch_paddr_q <= 32'd0;
            data_pa_valid <= 1'b0;
            data_paddr_q <= 32'd0;
            ptw_vaddr_q <= 64'd0;
            ptw_is_fetch_q <= 1'b0;
            ptw_we_q <= 1'b0;
            ptw_return_state_q <= ST_RESET;
            ptw_pte_addr_q <= 32'd0;
            ptw_l2_pte_q <= 64'd0;
            ptw_l1_pte_q <= 64'd0;
            illegal_instr <= 1'b0;
            current_priv <= PRIV_M;
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
            itlb_valid <= '0;
            dtlb_valid <= '0;
        end else if (soft_reset) begin
            state <= ST_RESET;
            instr_len_q <= 3'd4;
            fetch_upper_half_q <= 16'd0;
            wb_enable_q <= 1'b0;
            amo_wb_data_q <= 64'd0;
            fetch_pa_valid <= 1'b0;
            fetch_paddr_q <= 32'd0;
            data_pa_valid <= 1'b0;
            data_paddr_q <= 32'd0;
            ptw_vaddr_q <= 64'd0;
            ptw_is_fetch_q <= 1'b0;
            ptw_we_q <= 1'b0;
            ptw_return_state_q <= ST_RESET;
            ptw_pte_addr_q <= 32'd0;
            ptw_l2_pte_q <= 64'd0;
            ptw_l1_pte_q <= 64'd0;
            illegal_instr <= 1'b0;
            current_priv <= PRIV_M;
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
            itlb_valid <= '0;
            dtlb_valid <= '0;
        end else begin
            mcycle_counter <= mcycle_counter + 64'd1;
            case (state)
                ST_RESET: begin
                    pc <= reset_vector;
                    instr_q <= 32'd0;
                    instr_len_q <= 3'd4;
                    fetch_upper_half_q <= 16'd0;
                    wb_enable_q <= 1'b0;
                    illegal_instr <= 1'b0;
                    fetch_pa_valid <= 1'b0;
                    data_pa_valid <= 1'b0;
                    state <= ST_FETCH;
                end

                ST_FETCH: begin
                    wb_enable_q <= 1'b0;
                    data_pa_valid <= 1'b0;
                    if (interrupt_pending) begin
                        enter_trap(interrupt_cause, 64'd0, pc);
                    end else if (translate_active && !fetch_pa_valid) begin
                        translate_fetch_or_walk();
                    end else if (imem_ready) begin
                        if (pc[1] ? (imem_rdata[17:16] != 2'b11) : (imem_rdata[1:0] != 2'b11)) begin
                            instr_q <= expand_compressed(pc[1] ? imem_rdata[31:16] : imem_rdata[15:0]);
                            instr_len_q <= 3'd2;
                            fetch_pa_valid <= 1'b0;
                            state <= ST_DECODE;
                        end else if (!pc[1]) begin
                            instr_q <= imem_rdata;
                            instr_len_q <= 3'd4;
                            fetch_pa_valid <= 1'b0;
                            state <= ST_DECODE;
                        end else begin
                            fetch_upper_half_q <= imem_rdata[31:16];
                            state <= ST_FETCH2;
                        end
                    end
                end

                ST_FETCH2: begin
                    wb_enable_q <= 1'b0;
                    data_pa_valid <= 1'b0;
                    if (imem_ready) begin
                        instr_q <= {imem_rdata[15:0], fetch_upper_half_q};
                        instr_len_q <= 3'd4;
                        fetch_pa_valid <= 1'b0;
                        state <= ST_DECODE;
                    end
                end

                ST_DECODE: begin
                    wb_enable_q <= 1'b0;
                    pc_next_q <= pc_seq;
                    case (opcode)
                        OPCODE64_LUI: begin
                            issue_wb(rd, imm_u(instr_q), pc_seq);
                        end

                        OPCODE64_AUIPC: begin
                            issue_wb(rd, pc + imm_u(instr_q), pc_seq);
                        end

                        OPCODE64_JAL: begin
                            issue_wb(rd, pc_seq, pc + imm_j(instr_q));
                        end

                        OPCODE64_JALR: begin
                            issue_wb(rd, pc_seq, (rs1_data + imm_i(instr_q)) & ~64'd1);
                        end

                        OPCODE64_BRANCH: begin
                            if (branch_supported(funct3)) begin
                                pc <= branch_taken(funct3, rs1_data, rs2_data) ? pc + imm_b(instr_q) : pc_seq;
                                state <= ST_FETCH;
                            end else begin
                                halt_illegal();
                            end
                        end

                        OPCODE64_LOAD: begin
                            addr_calc = rs1_data + imm_i(instr_q);
                            if (!mem_load_supported(funct3) || !mem_aligned(funct3, addr_calc[2:0])) begin
                                halt_illegal();
                            end else begin
                                mem_load_q <= 1'b1;
                                mem_we_q <= 1'b0;
                                mem_funct3_q <= funct3;
                                mem_rd_q <= rd;
                                mem_addr_q <= addr_calc;
                                mem_wdata_q <= 64'd0;
                                mem_wstrb_q <= 8'd0;
                                pc_next_q <= pc_seq;
                                if (translate_active) begin
                                    data_pa_valid <= 1'b0;
                                    translate_data_or_walk(addr_calc, 1'b0, ST_MEMORY);
                                end else begin
                                    state <= ST_MEMORY;
                                end
                            end
                        end

                        OPCODE64_STORE: begin
                            addr_calc = rs1_data + imm_s(instr_q);
                            if (!mem_store_supported(funct3) || !mem_aligned(funct3, addr_calc[2:0])) begin
                                halt_illegal();
                            end else begin
                                mem_load_q <= 1'b0;
                                mem_we_q <= 1'b1;
                                mem_funct3_q <= funct3;
                                mem_rd_q <= 5'd0;
                                mem_addr_q <= addr_calc;
                                mem_wdata_q <= store_data(funct3, addr_calc[2:0], rs2_data);
                                mem_wstrb_q <= store_strobe(funct3, addr_calc[2:0]);
                                pc_next_q <= pc_seq;
                                if (translate_active) begin
                                    data_pa_valid <= 1'b0;
                                    translate_data_or_walk(addr_calc, 1'b1, ST_MEMORY);
                                end else begin
                                    state <= ST_MEMORY;
                                end
                            end
                        end

                        OPCODE64_AMO: begin
                            addr_calc = rs1_data;
                            if (!amo_supported ||
                                (amo_width_w && addr_calc[1:0] != 2'b00) ||
                                (amo_width_d && addr_calc[2:0] != 3'b000)) begin
                                halt_illegal();
                            end else begin
                                mem_load_q <= 1'b1;
                                mem_we_q <= 1'b0;
                                mem_funct3_q <= funct3;
                                mem_rd_q <= rd;
                                mem_addr_q <= addr_calc;
                                mem_wdata_q <= 64'd0;
                                mem_wstrb_q <= 8'd0;
                                amo_wb_data_q <= 64'd0;
                                pc_next_q <= pc_seq;
                                if (translate_active) begin
                                    data_pa_valid <= 1'b0;
                                    translate_data_or_walk(addr_calc, 1'b1, ST_AMO_LOAD);
                                end else begin
                                    state <= ST_AMO_LOAD;
                                end
                            end
                        end

                        OPCODE64_OP_IMM: begin
                            case (funct3)
                                3'b000, 3'b010, 3'b011, 3'b100, 3'b110, 3'b111: op_result = alu_y;
                                3'b001: begin
                                    if (instr_q[31:26] != 6'b000000) begin
                                        halt_illegal();
                                        op_result = 64'd0;
                                    end else begin
                                        op_result = alu_y;
                                    end
                                end
                                3'b101: begin
                                    if (instr_q[31:26] == 6'b000000) begin
                                        op_result = alu_y;
                                    end else if (instr_q[31:26] == 6'b010000) begin
                                        op_result = alu_y;
                                    end else begin
                                        halt_illegal();
                                        op_result = 64'd0;
                                    end
                                end
                                default: op_result = 64'd0;
                            endcase
                            if (state != ST_HALT) begin
                                issue_wb(rd, op_result, pc_seq);
                            end
                        end

                        OPCODE64_OP_IMM_32: begin
                            case (funct3)
                                3'b000: op_result = sext32(rs1_data[31:0] + {{20{instr_q[31]}}, instr_q[31:20]});
                                3'b001: begin
                                    if (instr_q[31:25] != 7'b0000000) begin
                                        halt_illegal();
                                        op_result = 64'd0;
                                    end else begin
                                        op_result = sext32(rs1_data[31:0] << instr_q[24:20]);
                                    end
                                end
                                3'b101: begin
                                    if (instr_q[31:25] == 7'b0000000) begin
                                        op_result = sext32(rs1_data[31:0] >> instr_q[24:20]);
                                    end else if (instr_q[31:25] == 7'b0100000) begin
                                        op_result = sext32($signed(rs1_data[31:0]) >>> instr_q[24:20]);
                                    end else begin
                                        halt_illegal();
                                        op_result = 64'd0;
                                    end
                                end
                                default: begin
                                    halt_illegal();
                                    op_result = 64'd0;
                                end
                            endcase
                            if (state != ST_HALT) begin
                                issue_wb(rd, op_result, pc_seq);
                            end
                        end

                        OPCODE64_OP: begin
                            unique case ({funct7, funct3})
                                {7'b0000001, 3'b000},
                                {7'b0000001, 3'b001},
                                {7'b0000001, 3'b010},
                                {7'b0000001, 3'b011},
                                {7'b0000001, 3'b100},
                                {7'b0000001, 3'b101},
                                {7'b0000001, 3'b110},
                                {7'b0000001, 3'b111}: op_result = rv64m_result(funct3, rs1_data, rs2_data);
                                {7'b0000000, 3'b000},
                                {7'b0100000, 3'b000},
                                {7'b0000000, 3'b001},
                                {7'b0000000, 3'b010},
                                {7'b0000000, 3'b011},
                                {7'b0000000, 3'b100},
                                {7'b0000000, 3'b101},
                                {7'b0100000, 3'b101},
                                {7'b0000000, 3'b110},
                                {7'b0000000, 3'b111}: op_result = alu_y;
                                default: begin
                                    halt_illegal();
                                    op_result = 64'd0;
                                end
                            endcase
                            if (state != ST_HALT) begin
                                issue_wb(rd, op_result, pc_seq);
                            end
                        end

                        OPCODE64_OP_32: begin
                            unique case ({funct7, funct3})
                                {7'b0000001, 3'b000},
                                {7'b0000001, 3'b100},
                                {7'b0000001, 3'b101},
                                {7'b0000001, 3'b110},
                                {7'b0000001, 3'b111}: op_result = rv64m_w_result(funct3, rs1_data, rs2_data);
                                {7'b0000000, 3'b000}: op_result = sext32(rs1_data[31:0] + rs2_data[31:0]);
                                {7'b0100000, 3'b000}: op_result = sext32(rs1_data[31:0] - rs2_data[31:0]);
                                {7'b0000000, 3'b001}: op_result = sext32(rs1_data[31:0] << rs2_data[4:0]);
                                {7'b0000000, 3'b101}: op_result = sext32(rs1_data[31:0] >> rs2_data[4:0]);
                                {7'b0100000, 3'b101}: op_result = sext32($signed(rs1_data[31:0]) >>> rs2_data[4:0]);
                                default: begin
                                    halt_illegal();
                                    op_result = 64'd0;
                                end
                            endcase
                            if (state != ST_HALT) begin
                                issue_wb(rd, op_result, pc_seq);
                            end
                        end

                        OPCODE64_MISC_MEM: begin
                            pc <= pc_seq;
                            state <= ST_FETCH;
                        end

                        OPCODE64_SYSTEM: begin
                            if (system_ecall) begin
                                if (trap_to_s) begin
                                    csr_sepc <= pc;
                                    csr_scause <= trap_cause;
                                    csr_stval <= 64'd0;
                                    csr_mstatus[5] <= csr_mstatus[1];
                                    csr_mstatus[1] <= 1'b0;
                                    csr_mstatus[8] <= (current_priv == PRIV_S);
                                    current_priv <= PRIV_S;
                                    pc <= {csr_stvec[63:2], 2'b00};
                                end else begin
                                    csr_mepc <= pc;
                                    csr_mcause <= trap_cause;
                                    csr_mtval <= 64'd0;
                                    csr_mstatus[7] <= csr_mstatus[3];
                                    csr_mstatus[3] <= 1'b0;
                                    csr_mstatus[12:11] <= current_priv;
                                    current_priv <= PRIV_M;
                                    pc <= {csr_mtvec[63:2], 2'b00};
                                end
                                state <= ST_FETCH;
                            end else if (system_mret) begin
                                if (current_priv != PRIV_M) begin
                                    halt_illegal();
                                end else begin
                                    csr_mstatus[3] <= csr_mstatus[7];
                                    csr_mstatus[7] <= 1'b1;
                                    csr_mstatus[12:11] <= 2'b00;
                                    if (csr_mstatus[12:11] == PRIV_S) begin
                                        current_priv <= PRIV_S;
                                    end else if (csr_mstatus[12:11] == PRIV_U) begin
                                        current_priv <= PRIV_U;
                                    end else begin
                                        current_priv <= PRIV_M;
                                    end
                                    pc <= csr_mepc;
                                    state <= ST_FETCH;
                                end
                            end else if (system_sret) begin
                                if (current_priv == PRIV_U) begin
                                    halt_illegal();
                                end else begin
                                    csr_mstatus[1] <= csr_mstatus[5];
                                    csr_mstatus[5] <= 1'b1;
                                    csr_mstatus[8] <= 1'b0;
                                    if (csr_mstatus[8]) begin
                                        current_priv <= PRIV_S;
                                    end else begin
                                        current_priv <= PRIV_U;
                                    end
                                    pc <= csr_sepc;
                                    state <= ST_FETCH;
                                end
                            end else if (system_sfence_vma) begin
                                if (current_priv == PRIV_U) begin
                                    halt_illegal();
                                end else begin
                                    flush_tlbs();
                                    pc <= pc_seq;
                                    state <= ST_FETCH;
                                end
                            end else if (system_wfi) begin
                                if (current_priv == PRIV_U) begin
                                    halt_illegal();
                                end else begin
                                    pc <= pc_seq;
                                    state <= ST_WFI;
                                end
                            end else if (system_ebreak) begin
                                state <= ST_HALT;
                            end else if (system_csr) begin
                                if (!csr_supported || !csr_priv_ok || (csr_read_only && csr_wen)) begin
                                    halt_illegal();
                                end else begin
                                    if (csr_wen) begin
                                        write_csr(csr_addr, csr_wdata);
                                    end
                                    issue_wb(rd, csr_rdata, pc_seq);
                                end
                            end else begin
                                halt_illegal();
                            end
                        end

                        default: begin
                            halt_illegal();
                        end
                    endcase
                end

                ST_PT_L2: begin
                    if (dmem_ready) begin
                        ptw_l2_pte_q <= dmem_rdata;
                        if (!sv39_pte_valid(dmem_rdata)) begin
                            enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q), ptw_vaddr_q, pc);
                        end else if (sv39_pte_leaf(dmem_rdata)) begin
                            if (!sv39_superpage_aligned(dmem_rdata, 2'd2) ||
                                !sv39_access_ok(dmem_rdata, current_priv, ptw_is_fetch_q, ptw_we_q, csr_mstatus)) begin
                                enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q), ptw_vaddr_q, pc);
                            end else begin
                                fill_tlb(ptw_is_fetch_q, ptw_vaddr_q, dmem_rdata, 2'd2);
                                if (ptw_is_fetch_q) begin
                                    fetch_paddr_q <= sv39_leaf_paddr(dmem_rdata, ptw_vaddr_q, 2'd2);
                                    fetch_pa_valid <= 1'b1;
                                end else begin
                                    data_paddr_q <= sv39_leaf_paddr(dmem_rdata, ptw_vaddr_q, 2'd2);
                                    data_pa_valid <= 1'b1;
                                end
                                state <= ptw_return_state_q;
                            end
                        end else begin
                            ptw_pte_addr_q <= sv39_pte_addr(dmem_rdata[53:10], ptw_vaddr_q, 2'd1);
                            state <= ST_PT_L1;
                        end
                    end
                end

                ST_PT_L1: begin
                    if (dmem_ready) begin
                        ptw_l1_pte_q <= dmem_rdata;
                        if (!sv39_pte_valid(dmem_rdata)) begin
                            enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q), ptw_vaddr_q, pc);
                        end else if (sv39_pte_leaf(dmem_rdata)) begin
                            if (!sv39_superpage_aligned(dmem_rdata, 2'd1) ||
                                !sv39_access_ok(dmem_rdata, current_priv, ptw_is_fetch_q, ptw_we_q, csr_mstatus)) begin
                                enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q), ptw_vaddr_q, pc);
                            end else begin
                                fill_tlb(ptw_is_fetch_q, ptw_vaddr_q, dmem_rdata, 2'd1);
                                if (ptw_is_fetch_q) begin
                                    fetch_paddr_q <= sv39_leaf_paddr(dmem_rdata, ptw_vaddr_q, 2'd1);
                                    fetch_pa_valid <= 1'b1;
                                end else begin
                                    data_paddr_q <= sv39_leaf_paddr(dmem_rdata, ptw_vaddr_q, 2'd1);
                                    data_pa_valid <= 1'b1;
                                end
                                state <= ptw_return_state_q;
                            end
                        end else begin
                            ptw_pte_addr_q <= sv39_pte_addr(dmem_rdata[53:10], ptw_vaddr_q, 2'd0);
                            state <= ST_PT_L0;
                        end
                    end
                end

                ST_PT_L0: begin
                    if (dmem_ready) begin
                        if (!sv39_pte_valid(dmem_rdata) ||
                            !sv39_pte_leaf(dmem_rdata) ||
                            !sv39_access_ok(dmem_rdata, current_priv, ptw_is_fetch_q, ptw_we_q, csr_mstatus)) begin
                            enter_trap(ptw_fault_cause(ptw_is_fetch_q, ptw_we_q), ptw_vaddr_q, pc);
                        end else begin
                            fill_tlb(ptw_is_fetch_q, ptw_vaddr_q, dmem_rdata, 2'd0);
                            if (ptw_is_fetch_q) begin
                                fetch_paddr_q <= sv39_leaf_paddr(dmem_rdata, ptw_vaddr_q, 2'd0);
                                fetch_pa_valid <= 1'b1;
                            end else begin
                                data_paddr_q <= sv39_leaf_paddr(dmem_rdata, ptw_vaddr_q, 2'd0);
                                data_pa_valid <= 1'b1;
                            end
                            state <= ptw_return_state_q;
                        end
                    end
                end

                ST_MEMORY: begin
                    if (dmem_ready) begin
                        if (mem_load_q) begin
                            wb_enable_q <= 1'b1;
                            wb_rd_q <= mem_rd_q;
                            wb_data_q <= load_data(mem_funct3_q, mem_addr_q[2:0], dmem_rdata);
                            state <= ST_WRITEBACK;
                        end else begin
                            if (mem_we_q && lr_reservation_valid &&
                                lr_reservation_addr[29:1] == mem_addr_q[31:3]) begin
                                lr_reservation_valid <= 1'b0;
                            end
                            pc <= pc_next_q;
                            state <= ST_FETCH;
                        end
                    end
                end

                ST_AMO_LOAD: begin
                    if (dmem_ready) begin
                        if (amo_lr) begin
                            lr_reservation_valid <= 1'b1;
                            lr_reservation_addr <= mem_addr_q[31:2];
                            wb_enable_q <= 1'b1;
                            wb_rd_q <= mem_rd_q;
                            wb_data_q <= amo_read_result(amo_width_w, mem_addr_q[2:0], dmem_rdata);
                            state <= ST_WRITEBACK;
                        end else if (amo_sc) begin
                            if (lr_reservation_valid && lr_reservation_addr == mem_addr_q[31:2]) begin
                                lr_reservation_valid <= 1'b0;
                                mem_we_q <= 1'b1;
                                mem_wdata_q <= store_data(amo_width_w ? 3'b010 : 3'b011,
                                                          mem_addr_q[2:0], rs2_data);
                                mem_wstrb_q <= amo_store_strobe(amo_width_w, mem_addr_q[2:0]);
                                amo_wb_data_q <= 64'd0;
                                state <= ST_AMO_STORE;
                            end else begin
                                lr_reservation_valid <= 1'b0;
                                wb_enable_q <= 1'b1;
                                wb_rd_q <= mem_rd_q;
                                wb_data_q <= 64'd1;
                                state <= ST_WRITEBACK;
                            end
                        end else begin
                            mem_we_q <= 1'b1;
                            mem_wdata_q <= amo_store_value(amo_funct5, amo_width_w,
                                                           mem_addr_q[2:0], dmem_rdata,
                                                           rs2_data);
                            mem_wstrb_q <= amo_store_strobe(amo_width_w, mem_addr_q[2:0]);
                            amo_wb_data_q <= amo_read_result(amo_width_w, mem_addr_q[2:0], dmem_rdata);
                            state <= ST_AMO_STORE;
                        end
                    end
                end

                ST_AMO_STORE: begin
                    if (dmem_ready) begin
                        if (lr_reservation_valid &&
                            lr_reservation_addr[29:1] == mem_addr_q[31:3]) begin
                            lr_reservation_valid <= 1'b0;
                        end
                        wb_enable_q <= 1'b1;
                        wb_rd_q <= mem_rd_q;
                        wb_data_q <= amo_wb_data_q;
                        state <= ST_WRITEBACK;
                    end
                end

                ST_WRITEBACK: begin
                    pc <= pc_next_q;
                    wb_enable_q <= 1'b0;
                    minstret_counter <= minstret_counter + 64'd1;
                    state <= ST_FETCH;
                end

                ST_WFI: begin
                    wb_enable_q <= 1'b0;
                    if (interrupt_pending) begin
                        enter_trap(interrupt_cause, 64'd0, pc);
                    end
                end

                ST_HALT: begin
                    wb_enable_q <= 1'b0;
                end

                default: begin
                    state <= ST_HALT;
                    illegal_instr <= 1'b1;
                end
            endcase
        end
    end
endmodule
