`include "cpu_defs.svh"

module zx32_core (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] reset_vector,
    input  logic        irq_timer,
    input  logic        irq_external,

    output logic        imem_valid,
    output logic [31:0] imem_addr,
    input  logic        imem_ready,
    input  logic [31:0] imem_rdata,

    output logic        dmem_valid,
    output logic        dmem_we,
    output logic [3:0]  dmem_wstrb,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic        dmem_ready,
    input  logic [31:0] dmem_rdata,

    output logic [31:0] dbg_core_state,
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_satp,
    output logic [31:0] dbg_stvec,
    output logic [31:0] dbg_sepc,
    output logic [31:0] dbg_scause,
    output logic [31:0] dbg_stval,
    output logic [31:0] dbg_req_vaddr,
    output logic [31:0] dbg_req_paddr,
    output logic [31:0] dbg_ptw_pte_addr,
    output logic [31:0] dbg_ptw_l1_pte,
    output logic [31:0] dbg_ptw_l0_pte
);
    localparam logic [31:0] DM_BASE            = 32'h1002_0000;
    localparam logic [31:0] DM_CTRL            = DM_BASE + 32'h0000;
    localparam logic [31:0] DM_STATUS          = DM_BASE + 32'h0004;
    localparam logic [31:0] DM_DDR_ADDR       = DM_BASE + 32'h0008;
    localparam logic [31:0] DM_LOCAL_ADDR     = DM_BASE + 32'h000c;
    localparam logic [31:0] DM_LENGTH_BYTES   = DM_BASE + 32'h0010;
    localparam logic [31:0] DM_TAG             = DM_BASE + 32'h0014;
    localparam logic [31:0] DM_STATUS_CLEAR    = 32'h0000_003c;
    localparam logic [31:0] DM_START_MM2S      = 32'h0000_0001;
    localparam logic [31:0] DM_START_S2MM      = 32'h0000_0002;
    localparam logic [31:0] DM_STATUS_MM2S_DONE = 32'h0000_0004;
    localparam logic [31:0] DM_STATUS_S2MM_DONE = 32'h0000_0008;
    localparam logic [31:0] DM_STATUS_MM2S_ERR  = 32'h0000_0010;
    localparam logic [31:0] DM_STATUS_S2MM_ERR  = 32'h0000_0020;
    localparam logic [11:0] CSR_MSTATUS         = 12'h300;
    localparam logic [11:0] CSR_MISA            = 12'h301;
    localparam logic [11:0] CSR_MEDELEG         = 12'h302;
    localparam logic [11:0] CSR_MIDELEG         = 12'h303;
    localparam logic [11:0] CSR_MIE             = 12'h304;
    localparam logic [11:0] CSR_MTVEC           = 12'h305;
    localparam logic [11:0] CSR_MCOUNTEREN      = 12'h306;
    localparam logic [11:0] CSR_SSTATUS         = 12'h100;
    localparam logic [11:0] CSR_SIE             = 12'h104;
    localparam logic [11:0] CSR_STVEC           = 12'h105;
    localparam logic [11:0] CSR_SCOUNTEREN      = 12'h106;
    localparam logic [11:0] CSR_SSCRATCH        = 12'h140;
    localparam logic [11:0] CSR_SEPC            = 12'h141;
    localparam logic [11:0] CSR_SCAUSE          = 12'h142;
    localparam logic [11:0] CSR_STVAL           = 12'h143;
    localparam logic [11:0] CSR_SIP             = 12'h144;
    localparam logic [11:0] CSR_SATP            = 12'h180;
    localparam logic [11:0] CSR_MSCRATCH        = 12'h340;
    localparam logic [11:0] CSR_MEPC            = 12'h341;
    localparam logic [11:0] CSR_MCAUSE          = 12'h342;
    localparam logic [11:0] CSR_MTVAL           = 12'h343;
    localparam logic [11:0] CSR_MIP             = 12'h344;
    localparam logic [11:0] CSR_MCYCLE          = 12'hb00;
    localparam logic [11:0] CSR_MINSTRET        = 12'hb02;
    localparam logic [11:0] CSR_MCYCLEH         = 12'hb80;
    localparam logic [11:0] CSR_MINSTRETH       = 12'hb82;
    localparam logic [11:0] CSR_CYCLE           = 12'hc00;
    localparam logic [11:0] CSR_TIME            = 12'hc01;
    localparam logic [11:0] CSR_INSTRET         = 12'hc02;
    localparam logic [11:0] CSR_CYCLEH          = 12'hc80;
    localparam logic [11:0] CSR_TIMEH           = 12'hc81;
    localparam logic [11:0] CSR_INSTRETH        = 12'hc82;
    localparam logic [11:0] CSR_MVENDORID       = 12'hf11;
    localparam logic [11:0] CSR_MARCHID         = 12'hf12;
    localparam logic [11:0] CSR_MIMPID          = 12'hf13;
    localparam logic [11:0] CSR_MHARTID         = 12'hf14;
    localparam logic [31:0] CSR_MISA_VALUE      = 32'h4004_1101; // RV32IMA + S-mode.
    localparam logic [31:0] SSTATUS_MASK        = 32'h000c_f122;
    localparam logic [31:0] MSTATUS_MIE         = 32'h0000_0008;
    localparam logic [31:0] MSTATUS_MPIE        = 32'h0000_0080;
    localparam logic [31:0] MSTATUS_MPP_MASK    = 32'h0000_1800;
    localparam logic [31:0] MSTATUS_SIE         = 32'h0000_0002;
    localparam logic [31:0] MSTATUS_SPIE        = 32'h0000_0020;
    localparam logic [31:0] MSTATUS_SPP         = 32'h0000_0100;
    localparam int          IRQ_S_TIMER         = 5;
    localparam int          IRQ_M_TIMER         = 7;
    localparam int          IRQ_S_EXT           = 9;
    localparam int          IRQ_M_EXT           = 11;
    localparam logic [31:0] MIP_STIP            = 32'h0000_0020;
    localparam logic [31:0] MIP_MTIP            = 32'h0000_0080;
    localparam logic [31:0] MIP_SEIP            = 32'h0000_0200;
    localparam logic [31:0] MIP_MEIP            = 32'h0000_0800;
    localparam logic [31:0] MCAUSE_ILLEGAL      = 32'd2;
    localparam logic [31:0] MCAUSE_BREAKPOINT   = 32'd3;
    localparam logic [31:0] MCAUSE_ECALL_U      = 32'd8;
    localparam logic [31:0] MCAUSE_ECALL_S      = 32'd9;
    localparam logic [31:0] MCAUSE_ECALL_M      = 32'd11;
    localparam logic [31:0] MCAUSE_INST_PAGE_FAULT  = 32'd12;
    localparam logic [31:0] MCAUSE_LOAD_PAGE_FAULT  = 32'd13;
    localparam logic [31:0] MCAUSE_STORE_PAGE_FAULT = 32'd15;
    localparam logic [31:0] MCAUSE_INTERRUPT    = 32'h8000_0000;
    localparam int          TLB_ENTRIES         = 8;

    typedef enum logic [1:0] {
        PRIV_U = 2'b00,
        PRIV_S = 2'b01,
        PRIV_M = 2'b11
    } priv_mode_t;

    typedef enum logic [4:0] {
        ST_RESET,
        ST_FETCH,
        ST_DECODE,
        ST_EXECUTE,
        ST_CUSTOM_LOAD,
        ST_CUSTOM_STORE,
        ST_CUSTOM_DM_CLEAR,
        ST_CUSTOM_DM_DDR,
        ST_CUSTOM_DM_LOCAL,
        ST_CUSTOM_DM_LEN,
        ST_CUSTOM_DM_TAG,
        ST_CUSTOM_DM_START,
        ST_CUSTOM_DM_WAIT,
        ST_PT_L1_REQ,
        ST_PT_L1_WAIT,
        ST_PT_L1_EVAL,
        ST_PT_L0_REQ,
        ST_PT_L0_WAIT,
        ST_PT_L0_EVAL,
        ST_PT_AD_REQ,
        ST_MULDIV,
        ST_AMO_LOAD,
        ST_AMO_CALC,
        ST_AMO_STORE,
        ST_MEMORY,
        ST_WRITEBACK
    } state_t;

    state_t state;

    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] instr_q;
    logic [31:0] decode_instr;
    logic [31:0] next_pc;
    logic [31:0] alu_y;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] op_rs1_data;
    logic [31:0] op_rs2_data;
    logic [31:0] op_rs1_q;
    logic [31:0] op_rs2_q;
    logic [31:0] wb_data;
    logic [31:0] load_word_q;
    logic [31:0] load_data;
    logic [31:0] muldiv_result_q;
    logic [31:0] div_dividend_q;
    logic [31:0] div_divisor_q;
    logic [31:0] div_quotient_q;
    logic [32:0] div_remainder_q;
    logic [5:0]  div_count_q;
    logic        div_quot_neg_q;
    logic        div_rem_neg_q;
    logic        div_return_rem_q;
    logic [32:0] div_step_rem_shift;
    logic [32:0] div_step_rem_next;
    logic [31:0] div_step_quot_next;
    logic [31:0] div_step_dividend_next;
    logic [31:0] div_step_signed_quot;
    logic [31:0] div_step_signed_rem;
    logic [31:0] amo_write_data;
    logic        amo_sc_success;
    logic        amo_lr;
    logic        amo_sc;
    logic        amo_supported;
    logic [4:0]  amo_funct5;
    logic        m_supported;
    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [6:0] opcode;
    logic       reg_wen;
    logic [4:0] rd_q;
    logic       illegal_instr;
    logic       regfile_wen;
    alu_op_t    alu_op;
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic       custom_xcpyw;
    logic       custom_xdm2s;
    logic       custom_xds2m;
    logic [31:0] req_vaddr;
    logic [31:0] req_paddr;
    logic [31:0] req_wdata;
    logic [3:0]  req_wstrb;
    logic        req_we;
    logic        req_is_fetch;
    logic        req_active;
    logic        req_pa_valid;
    logic [31:0] mem_addr_q;
    state_t      ptw_return_state;
    logic [31:0] ptw_pte_addr;
    logic [31:0] ptw_l1_pte;
    logic [31:0] ptw_l0_pte;
    logic [31:0] ptw_ad_pte;
    logic        ptw_leaf_superpage;
    logic [31:0] page_fault_cause;
    logic [31:0] page_fault_tval;
    logic        page_fault_pending;
    logic        translate_active;
    logic        system_sfence_vma;
    logic [TLB_ENTRIES-1:0] tlb_valid;
    logic [TLB_ENTRIES-1:0] tlb_global;
    logic [TLB_ENTRIES-1:0] tlb_r;
    logic [TLB_ENTRIES-1:0] tlb_w;
    logic [TLB_ENTRIES-1:0] tlb_x;
    logic [TLB_ENTRIES-1:0] tlb_u;
    logic [TLB_ENTRIES-1:0] tlb_a;
    logic [TLB_ENTRIES-1:0] tlb_d;
    logic [TLB_ENTRIES-1:0] tlb_superpage;
    logic [19:0] tlb_vpn [0:TLB_ENTRIES-1];
    logic [8:0]  tlb_asid [0:TLB_ENTRIES-1];
    logic [21:0] tlb_ppn [0:TLB_ENTRIES-1];
    logic [2:0]  tlb_replace_ptr;
    logic        tlb_lookup_hit;
    logic        tlb_lookup_fault;
    logic [31:0] tlb_lookup_paddr;
    logic        tlb_lookup_hit_q;
    logic        tlb_lookup_fault_q;
    logic [31:0] tlb_lookup_paddr_q;
    logic [31:0] dm_addr_q;
    logic [31:0] dm_len_q;
    logic [31:0] dm_status_q;
    logic        dm_is_s2mm;
    priv_mode_t  current_priv;
    logic [31:0] csr_mstatus;
    logic [31:0] csr_medeleg;
    logic [31:0] csr_mideleg;
    logic [31:0] csr_mie;
    logic [31:0] csr_mcounteren;
    logic [31:0] csr_mtvec;
    logic [31:0] csr_sie;
    logic [31:0] csr_scounteren;
    logic [31:0] csr_stvec;
    logic [31:0] csr_sscratch;
    logic [31:0] csr_sepc;
    logic [31:0] csr_scause;
    logic [31:0] csr_stval;
    logic [31:0] csr_sip;
    logic [31:0] csr_satp;
    logic [31:0] csr_mscratch;
    logic [31:0] csr_mepc;
    logic [31:0] csr_mcause;
    logic [31:0] csr_mtval;
    logic [31:0] csr_mip;
    logic [31:0] csr_mip_view;
    logic [31:0] csr_sip_view;
    logic [11:0] csr_addr;
    logic [31:0] csr_rdata;
    logic [31:0] csr_operand;
    logic [31:0] csr_wdata;
    logic        csr_supported;
    logic        csr_priv_ok;
    logic        csr_read_only;
    logic        csr_counter_access_ok;
    logic        csr_wen;
    logic        system_csr;
    logic        system_ecall;
    logic        system_ebreak;
    logic        system_mret;
    logic        system_sret;
    logic        system_wfi;
    logic [31:0] trap_cause;
    logic [31:0] trap_tval;
    logic        trap_to_s;
    logic        interrupt_to_s;
    logic        interrupt_to_m;
    logic [31:0] interrupt_cause;
    logic        lr_reservation_valid;
    logic [29:0] lr_reservation_addr;
    logic [63:0] mcycle_counter;
    logic [63:0] minstret_counter;

    function automatic logic [31:0] load_extend(
        input logic [31:0] word,
        input logic [1:0]  addr_lsb,
        input logic [2:0]  size
    );
        logic [7:0]  byte_data;
        logic [15:0] half_data;
        begin
            case (addr_lsb)
                2'b00: byte_data = word[7:0];
                2'b01: byte_data = word[15:8];
                2'b10: byte_data = word[23:16];
                default: byte_data = word[31:24];
            endcase

            half_data = addr_lsb[1] ? word[31:16] : word[15:0];

            case (size)
                3'b000: load_extend = {{24{byte_data[7]}}, byte_data};
                3'b001: load_extend = {{16{half_data[15]}}, half_data};
                3'b010: load_extend = word;
                3'b100: load_extend = {24'd0, byte_data};
                3'b101: load_extend = {16'd0, half_data};
                default: load_extend = 32'd0;
            endcase
        end
    endfunction

    function automatic logic [3:0] store_strobe(
        input logic [1:0] addr_lsb,
        input logic [2:0] size
    );
        begin
            case (size)
                3'b000: store_strobe = 4'b0001 << addr_lsb;
                3'b001: store_strobe = addr_lsb[1] ? 4'b1100 : 4'b0011;
                3'b010: store_strobe = 4'b1111;
                default: store_strobe = 4'b0000;
            endcase
        end
    endfunction

    function automatic logic [31:0] store_data(
        input logic [1:0]  addr_lsb,
        input logic [2:0]  size,
        input logic [31:0] data
    );
        begin
            case (size)
                3'b000: store_data = {4{data[7:0]}} << (8 * addr_lsb);
                3'b001: store_data = {2{data[15:0]}} << (16 * addr_lsb[1]);
                3'b010: store_data = data;
                default: store_data = 32'd0;
            endcase
        end
    endfunction

    function automatic logic [31:0] amo_result_word(
        input logic [4:0]  op,
        input logic [31:0] old_word,
        input logic [31:0] rs2_word
    );
        begin
            case (op)
                5'b00000: amo_result_word = old_word + rs2_word; // amoadd.w
                5'b00001: amo_result_word = rs2_word;            // amoswap.w
                5'b00100: amo_result_word = old_word ^ rs2_word; // amoxor.w
                5'b01000: amo_result_word = old_word | rs2_word; // amoor.w
                5'b01100: amo_result_word = old_word & rs2_word; // amoand.w
                5'b10000: amo_result_word = (signed'(old_word) < signed'(rs2_word)) ? old_word : rs2_word;
                5'b10100: amo_result_word = (signed'(old_word) > signed'(rs2_word)) ? old_word : rs2_word;
                5'b11000: amo_result_word = (old_word < rs2_word) ? old_word : rs2_word;
                5'b11100: amo_result_word = (old_word > rs2_word) ? old_word : rs2_word;
                default:  amo_result_word = old_word;
            endcase
        end
    endfunction

    function automatic logic [31:0] rv32_abs(
        input logic [31:0] value
    );
        begin
            rv32_abs = value[31] ? (~value + 32'd1) : value;
        end
    endfunction

    function automatic logic [31:0] rv32_negate_if(
        input logic [31:0] value,
        input logic        negate
    );
        begin
            rv32_negate_if = negate ? (~value + 32'd1) : value;
        end
    endfunction

    function automatic logic [31:0] rv32m_mul_result(
        input logic [2:0]  op,
        input logic [31:0] lhs,
        input logic [31:0] rhs
    );
        logic [63:0]        product_u;
        logic signed [63:0] lhs_s;
        logic signed [63:0] rhs_s;
        logic signed [63:0] product_s;
        begin
            product_u = {32'd0, lhs} * {32'd0, rhs};
            lhs_s = {{32{lhs[31]}}, lhs};
            rhs_s = {{32{rhs[31]}}, rhs};
            product_s = lhs_s * rhs_s;

            case (op)
                3'b000: rv32m_mul_result = product_u[31:0];
                3'b001: rv32m_mul_result = product_s[63:32];
                3'b010: begin
                    rhs_s = {32'd0, rhs};
                    product_s = lhs_s * rhs_s;
                    rv32m_mul_result = product_s[63:32];
                end
                3'b011: rv32m_mul_result = product_u[63:32];
                default: rv32m_mul_result = 32'd0;
            endcase
        end
    endfunction

    function automatic logic counter_access_ok(
        input logic [11:0] csr,
        input logic [1:0]  priv,
        input logic [31:0] mcounteren,
        input logic [31:0] scounteren
    );
        logic [4:0] counter_bit;
        logic       is_counter;
        begin
            is_counter = 1'b1;
            case (csr)
                CSR_CYCLE, CSR_CYCLEH:     counter_bit = 5'd0;
                CSR_TIME, CSR_TIMEH:       counter_bit = 5'd1;
                CSR_INSTRET, CSR_INSTRETH: counter_bit = 5'd2;
                default: begin
                    is_counter = 1'b0;
                    counter_bit = 5'd0;
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

    function automatic logic sv32_active(
        input logic [31:0] satp,
        input logic [1:0]  priv
    );
        begin
            sv32_active = satp[31] && (priv != PRIV_M);
        end
    endfunction

    function automatic logic [31:0] sv32_l1_pte_addr(
        input logic [31:0] satp,
        input logic [31:0] vaddr
    );
        begin
            sv32_l1_pte_addr = {satp[21:0], 12'b0} + {vaddr[31:22], 2'b00};
        end
    endfunction

    function automatic logic [31:0] sv32_l0_pte_addr(
        input logic [31:0] pte,
        input logic [31:0] vaddr
    );
        begin
            sv32_l0_pte_addr = {pte[31:10], 12'b0} + {vaddr[21:12], 2'b00};
        end
    endfunction

    function automatic logic [31:0] sv32_pte_set_ad(
        input logic [31:0] pte,
        input logic        is_store
    );
        begin
            sv32_pte_set_ad = pte | 32'h0000_0040 | (is_store ? 32'h0000_0080 : 32'd0);
        end
    endfunction

    function automatic logic sv32_tlb_access_ok(
        input logic [1:0]  priv,
        input logic [31:0] mstatus,
        input logic        is_fetch,
        input logic        we,
        input logic        r_ok,
        input logic        w_ok,
        input logic        x_ok,
        input logic        u_ok,
        input logic        a_ok,
        input logic        d_ok
    );
        begin
            sv32_tlb_access_ok = a_ok;
            if (sv32_tlb_access_ok) begin
                if (is_fetch) begin
                    sv32_tlb_access_ok = x_ok;
                end else if (we) begin
                    sv32_tlb_access_ok = w_ok && d_ok;
                end else begin
                    sv32_tlb_access_ok = r_ok;
                end
            end

            if (sv32_tlb_access_ok) begin
                if (priv == PRIV_U) begin
                    sv32_tlb_access_ok = u_ok;
                end else if (priv == PRIV_S && u_ok && (is_fetch || !mstatus[18])) begin
                    sv32_tlb_access_ok = 1'b0;
                end
            end
        end
    endfunction

    task automatic tlb_insert(
        input logic [31:0] vaddr,
        input logic [31:0] pte,
        input logic        superpage
    );
        int idx;
        begin
            idx = tlb_replace_ptr;
            tlb_valid[idx] <= 1'b1;
            tlb_global[idx] <= pte[5];
            tlb_r[idx] <= pte[1];
            tlb_w[idx] <= pte[2];
            tlb_x[idx] <= pte[3];
            tlb_u[idx] <= pte[4];
            tlb_a[idx] <= pte[6];
            tlb_d[idx] <= pte[7];
            tlb_superpage[idx] <= superpage;
            tlb_vpn[idx] <= vaddr[31:12];
            tlb_asid[idx] <= csr_satp[30:22];
            tlb_ppn[idx] <= pte[31:10];
            tlb_replace_ptr <= tlb_replace_ptr + 3'd1;
        end
    endtask

    function automatic logic tlb_vpn_match(
        input logic        superpage,
        input logic [19:0] entry_vpn,
        input logic [31:0] vaddr
    );
        begin
            if (superpage) begin
                tlb_vpn_match = (entry_vpn[19:10] == vaddr[31:22]);
            end else begin
                tlb_vpn_match = (entry_vpn == vaddr[31:12]);
            end
        end
    endfunction

    function automatic logic sfence_vma_match(
        input logic        superpage,
        input logic [19:0] entry_vpn,
        input logic [8:0]  entry_asid,
        input logic        entry_global,
        input logic [31:0] rs1_val,
        input logic [31:0] rs2_val
    );
        logic addr_match;
        logic asid_match;
        begin
            if (rs1_val == 32'd0) begin
                addr_match = 1'b1;
            end else begin
                addr_match = tlb_vpn_match(superpage, entry_vpn, rs1_val);
            end

            if (rs2_val == 32'd0) begin
                asid_match = 1'b1;
            end else begin
                asid_match = !entry_global && (entry_asid == rs2_val[8:0]);
            end

            sfence_vma_match = addr_match && asid_match;
        end
    endfunction

    assign decode_instr = (state == ST_DECODE || state == ST_EXECUTE) ? instr : instr_q;
    assign opcode = decode_instr[6:0];
    assign rd     = decode_instr[11:7];
    assign funct3 = decode_instr[14:12];
    assign rs1    = decode_instr[19:15];
    assign rs2    = decode_instr[24:20];
    assign funct7 = decode_instr[31:25];

    assign imm_i = {{20{decode_instr[31]}}, decode_instr[31:20]};
    assign imm_s = {{20{decode_instr[31]}}, decode_instr[31:25], decode_instr[11:7]};
    assign imm_b = {{19{decode_instr[31]}}, decode_instr[31], decode_instr[7], decode_instr[30:25], decode_instr[11:8], 1'b0};
    assign imm_u = {decode_instr[31:12], 12'd0};
    assign imm_j = {{11{decode_instr[31]}}, decode_instr[31], decode_instr[19:12], decode_instr[20], decode_instr[30:21], 1'b0};
    assign load_data = load_extend(load_word_q, mem_addr_q[1:0], funct3);
    assign amo_funct5 = decode_instr[31:27];
    assign amo_lr = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (amo_funct5 == 5'b00010) && (rs2 == 5'd0);
    assign amo_sc = (opcode == OPCODE_AMO) && (funct3 == 3'b010) && (amo_funct5 == 5'b00011);
    assign amo_supported = (opcode == OPCODE_AMO) && (funct3 == 3'b010) &&
                           (amo_lr || amo_sc ||
                            amo_funct5 == 5'b00000 || amo_funct5 == 5'b00001 ||
                            amo_funct5 == 5'b00100 || amo_funct5 == 5'b01000 ||
                            amo_funct5 == 5'b01100 || amo_funct5 == 5'b10000 ||
                            amo_funct5 == 5'b10100 || amo_funct5 == 5'b11000 ||
                            amo_funct5 == 5'b11100);
    assign m_supported = (opcode == OPCODE_OP) && (funct7 == 7'b0000001);
    assign div_step_rem_shift = {div_remainder_q[31:0], div_dividend_q[31]};
    assign div_step_dividend_next = {div_dividend_q[30:0], 1'b0};
    assign div_step_rem_next = (div_step_rem_shift >= {1'b0, div_divisor_q}) ?
                               (div_step_rem_shift - {1'b0, div_divisor_q}) :
                               div_step_rem_shift;
    assign div_step_quot_next = {div_quotient_q[30:0],
                                 (div_step_rem_shift >= {1'b0, div_divisor_q})};
    assign div_step_signed_quot = rv32_negate_if(div_step_quot_next, div_quot_neg_q);
    assign div_step_signed_rem = rv32_negate_if(div_step_rem_next[31:0], div_rem_neg_q);
    assign custom_xcpyw = (opcode == OPCODE_CUSTOM0) && (funct3 == 3'b000) && (funct7 == 7'b0000000);
    assign custom_xdm2s = (opcode == OPCODE_CUSTOM0) && (funct3 == 3'b001) && (funct7 == 7'b0000000);
    assign custom_xds2m = (opcode == OPCODE_CUSTOM0) && (funct3 == 3'b010) && (funct7 == 7'b0000000);
    assign csr_addr = decode_instr[31:20];
    assign system_csr = (opcode == OPCODE_SYSTEM) && (funct3 != 3'b000);
    assign system_ecall = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h000);
    assign system_ebreak = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h001);
    assign system_sret = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h102);
    assign system_mret = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h302);
    assign system_wfi = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (csr_addr == 12'h105);
    assign system_sfence_vma = (opcode == OPCODE_SYSTEM) && (funct3 == 3'b000) && (funct7 == 7'b0001001);
    assign amo_sc_success = lr_reservation_valid &&
                             (lr_reservation_addr == (req_pa_valid ? req_paddr[31:2] : mem_addr_q[31:2]));
    assign op_rs1_data = (state == ST_EXECUTE) ? rs1_data : op_rs1_q;
    assign op_rs2_data = (state == ST_EXECUTE) ? rs2_data : op_rs2_q;
    assign csr_operand = funct3[2] ? {27'd0, rs1} : op_rs1_data;
    assign csr_wen = system_csr && ((funct3 == 3'b001) || (funct3 == 3'b101) || (rs1 != 5'd0));
    assign trap_cause = page_fault_pending ? page_fault_cause :
                        illegal_instr ? MCAUSE_ILLEGAL :
                        (system_ebreak ? MCAUSE_BREAKPOINT :
                         (current_priv == PRIV_S ? MCAUSE_ECALL_S :
                          (current_priv == PRIV_U ? MCAUSE_ECALL_U : MCAUSE_ECALL_M)));
    assign trap_tval = page_fault_pending ? page_fault_tval :
                       illegal_instr ? decode_instr : 32'd0;
    assign trap_to_s = (current_priv != PRIV_M) && csr_medeleg[trap_cause[4:0]];
    assign csr_mip_view = csr_mip |
                          (irq_timer ? MIP_MTIP : 32'd0) |
                          ((irq_timer && csr_mideleg[IRQ_S_TIMER]) ? MIP_STIP : 32'd0) |
                          (irq_external ? MIP_MEIP : 32'd0) |
                          ((irq_external && csr_mideleg[IRQ_S_EXT]) ? MIP_SEIP : 32'd0);
    assign csr_sip_view = csr_sip |
                          ((irq_timer && csr_mideleg[IRQ_S_TIMER]) ? MIP_STIP : 32'd0) |
                          ((irq_external && csr_mideleg[IRQ_S_EXT]) ? MIP_SEIP : 32'd0);
    assign interrupt_cause = irq_timer && ((current_priv != PRIV_M) && csr_mideleg[IRQ_S_TIMER] &&
                                           csr_sie[IRQ_S_TIMER] && (current_priv != PRIV_S || csr_mstatus[1])) ?
                             (MCAUSE_INTERRUPT | 32'd5) :
                             (irq_timer && csr_mie[IRQ_M_TIMER] &&
                              (current_priv == PRIV_M ? csr_mstatus[3] : !csr_mideleg[IRQ_S_TIMER])) ?
                             (MCAUSE_INTERRUPT | 32'd7) :
                             (irq_external && ((current_priv != PRIV_M) && csr_mideleg[IRQ_S_EXT] &&
                                               csr_sie[IRQ_S_EXT] && (current_priv != PRIV_S || csr_mstatus[1])) ?
                              (MCAUSE_INTERRUPT | 32'd9) :
                              (irq_external && csr_mie[IRQ_M_EXT] &&
                               (current_priv == PRIV_M ? csr_mstatus[3] : !csr_mideleg[IRQ_S_EXT])) ?
                              (MCAUSE_INTERRUPT | 32'd11) : 32'd0);
    assign interrupt_to_s = (interrupt_cause == (MCAUSE_INTERRUPT | 32'd5)) ||
                            (interrupt_cause == (MCAUSE_INTERRUPT | 32'd9));
    assign interrupt_to_m = (interrupt_cause == (MCAUSE_INTERRUPT | 32'd7)) ||
                            (interrupt_cause == (MCAUSE_INTERRUPT | 32'd11));
    assign dbg_core_state = {16'd0,
                             current_priv,
                             state,
                             dmem_ready,
                             dmem_valid,
                             imem_ready,
                             imem_valid,
                             page_fault_pending,
                             req_we,
                             req_is_fetch,
                             req_pa_valid,
                             req_active};
    assign dbg_pc = pc;
    assign dbg_satp = csr_satp;
    assign dbg_stvec = csr_stvec;
    assign dbg_sepc = csr_sepc;
    assign dbg_scause = csr_scause;
    assign dbg_stval = csr_stval;
    assign dbg_req_vaddr = req_vaddr;
    assign dbg_req_paddr = req_paddr;
    assign dbg_ptw_pte_addr = ptw_pte_addr;
    assign dbg_ptw_l1_pte = ptw_l1_pte;
    assign dbg_ptw_l0_pte = ptw_l0_pte;

    always_comb begin
        tlb_lookup_hit = 1'b0;
        tlb_lookup_fault = 1'b0;
        tlb_lookup_paddr = 32'd0;

        if (translate_active && req_active && !req_pa_valid &&
            (state == ST_PT_L1_REQ || state == ST_PT_L0_REQ)) begin
            for (int i = 0; i < TLB_ENTRIES; i++) begin
                if (!tlb_lookup_hit && !tlb_lookup_fault && tlb_valid[i] &&
                    tlb_vpn_match(tlb_superpage[i], tlb_vpn[i], req_vaddr) &&
                    (tlb_global[i] || (tlb_asid[i] == csr_satp[30:22]))) begin
                    if (sv32_tlb_access_ok(current_priv, csr_mstatus, req_is_fetch, req_we,
                                           tlb_r[i], tlb_w[i], tlb_x[i], tlb_u[i], tlb_a[i], tlb_d[i])) begin
                        tlb_lookup_hit = 1'b1;
                        if (tlb_superpage[i]) begin
                            tlb_lookup_paddr = {tlb_ppn[i][19:10], req_vaddr[21:0]};
                        end else begin
                            tlb_lookup_paddr = {tlb_ppn[i], req_vaddr[11:0]};
                        end
                    end else begin
                        tlb_lookup_fault = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin
        csr_supported = 1'b1;
        csr_priv_ok = (current_priv >= csr_addr[9:8]);
        csr_read_only = (csr_addr[11:10] == 2'b11);
        csr_counter_access_ok = counter_access_ok(csr_addr, current_priv, csr_mcounteren, csr_scounteren);
        csr_priv_ok = csr_priv_ok && csr_counter_access_ok;
        case (csr_addr)
            CSR_SSTATUS: csr_rdata = csr_mstatus & SSTATUS_MASK;
            CSR_SIE:     csr_rdata = csr_sie;
            CSR_STVEC:   csr_rdata = csr_stvec;
            CSR_SCOUNTEREN: csr_rdata = csr_scounteren;
            CSR_SSCRATCH: csr_rdata = csr_sscratch;
            CSR_SEPC:    csr_rdata = csr_sepc;
            CSR_SCAUSE:  csr_rdata = csr_scause;
            CSR_STVAL:   csr_rdata = csr_stval;
            CSR_SIP:     csr_rdata = csr_sip_view;
            CSR_SATP:    csr_rdata = csr_satp;
            CSR_MSTATUS:  csr_rdata = csr_mstatus;
            CSR_MISA:     csr_rdata = CSR_MISA_VALUE;
            CSR_MEDELEG:  csr_rdata = csr_medeleg;
            CSR_MIDELEG:  csr_rdata = csr_mideleg;
            CSR_MIE:      csr_rdata = csr_mie;
            CSR_MCOUNTEREN: csr_rdata = csr_mcounteren;
            CSR_MTVEC:    csr_rdata = csr_mtvec;
            CSR_MSCRATCH: csr_rdata = csr_mscratch;
            CSR_MEPC:     csr_rdata = csr_mepc;
            CSR_MCAUSE:   csr_rdata = csr_mcause;
            CSR_MTVAL:    csr_rdata = csr_mtval;
            CSR_MIP:      csr_rdata = csr_mip_view;
            CSR_MCYCLE:   csr_rdata = mcycle_counter[31:0];
            CSR_MINSTRET: csr_rdata = minstret_counter[31:0];
            CSR_MCYCLEH:  csr_rdata = mcycle_counter[63:32];
            CSR_MINSTRETH: csr_rdata = minstret_counter[63:32];
            CSR_CYCLE:    csr_rdata = mcycle_counter[31:0];
            CSR_TIME:     csr_rdata = mcycle_counter[31:0];
            CSR_INSTRET:  csr_rdata = minstret_counter[31:0];
            CSR_CYCLEH:   csr_rdata = mcycle_counter[63:32];
            CSR_TIMEH:    csr_rdata = mcycle_counter[63:32];
            CSR_INSTRETH: csr_rdata = minstret_counter[63:32];
            CSR_MVENDORID: csr_rdata = 32'd0;
            CSR_MARCHID:  csr_rdata = 32'h0000_5a32;
            CSR_MIMPID:   csr_rdata = 32'd1;
            CSR_MHARTID:  csr_rdata = 32'd0;
            default: begin
                csr_rdata = 32'd0;
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

    regfile u_regfile (
        .clk(clk),
        .wen(regfile_wen),
        .waddr(rd_q),
        .wdata(wb_data),
        .raddr1(rs1),
        .rdata1(rs1_data),
        .raddr2(rs2),
        .rdata2(rs2_data)
    );

    alu u_alu (
        .op(alu_op),
        .a(alu_a),
        .b(alu_b),
        .y(alu_y)
    );

    always @* begin
        translate_active = sv32_active(csr_satp, current_priv);
        imem_valid   = (state == ST_FETCH) &&
                       (!translate_active || (req_active && req_is_fetch && req_pa_valid));
        imem_addr    = (req_active && req_is_fetch && req_pa_valid) ? req_paddr : pc;
        dmem_valid   = 1'b0;
        dmem_we      = 1'b0;
        dmem_wstrb   = 4'b0000;
        dmem_addr    = mem_addr_q;
        dmem_wdata   = op_rs2_data;
        reg_wen      = 1'b0;
        illegal_instr = 1'b0;
        next_pc      = pc + 32'd4;
        wb_data      = alu_y;
        alu_op       = ALU_ADD;
        alu_a        = op_rs1_data;
        alu_b        = op_rs2_data;

        case (opcode)
            OPCODE_LUI: begin
                reg_wen = 1'b1;
                wb_data = imm_u;
            end
            OPCODE_AUIPC: begin
                reg_wen = 1'b1;
                wb_data = pc + imm_u;
            end
            OPCODE_JAL: begin
                reg_wen = 1'b1;
                wb_data = pc + 32'd4;
                next_pc = pc + imm_j;
            end
            OPCODE_JALR: begin
                reg_wen = 1'b1;
                wb_data = pc + 32'd4;
                next_pc = (op_rs1_data + imm_i) & ~32'd1;
            end
            OPCODE_OP_IMM: begin
                reg_wen = 1'b1;
                alu_a = op_rs1_data;
                alu_b = imm_i;
                case (funct3)
                    3'b000: alu_op = ALU_ADD;
                    3'b010: alu_op = ALU_SLT;
                    3'b011: alu_op = ALU_SLTU;
                    3'b100: alu_op = ALU_XOR;
                    3'b110: alu_op = ALU_OR;
                    3'b111: alu_op = ALU_AND;
                    3'b001: alu_op = ALU_SLL;
                    3'b101: begin
                        if (funct7[5]) begin
                            alu_op = ALU_SRA;
                        end else begin
                            alu_op = ALU_SRL;
                        end
                    end
                    default: illegal_instr = 1'b1;
                endcase
            end
            OPCODE_OP: begin
                reg_wen = 1'b1;
                alu_a = op_rs1_data;
                alu_b = op_rs2_data;
                if (m_supported) begin
                    wb_data = muldiv_result_q;
                end else begin
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
                        default: illegal_instr = 1'b1;
                    endcase
                end
            end
            OPCODE_BRANCH: begin
                case (funct3)
                    3'b000: next_pc = (op_rs1_data == op_rs2_data) ? pc + imm_b : pc + 32'd4;
                    3'b001: next_pc = (op_rs1_data != op_rs2_data) ? pc + imm_b : pc + 32'd4;
                    3'b100: next_pc = (signed'(op_rs1_data) < signed'(op_rs2_data)) ? pc + imm_b : pc + 32'd4;
                    3'b101: next_pc = (signed'(op_rs1_data) >= signed'(op_rs2_data)) ? pc + imm_b : pc + 32'd4;
                    3'b110: next_pc = (op_rs1_data < op_rs2_data) ? pc + imm_b : pc + 32'd4;
                    3'b111: next_pc = (op_rs1_data >= op_rs2_data) ? pc + imm_b : pc + 32'd4;
                    default: illegal_instr = 1'b1;
                endcase
            end
            OPCODE_LOAD: begin
                reg_wen = 1'b1;
                wb_data = load_data;
                alu_a = op_rs1_data;
                alu_b = imm_i;
                alu_op = ALU_ADD;
                dmem_valid = (state == ST_MEMORY);
                dmem_we = 1'b0;
                if (funct3 == 3'b011 || funct3 == 3'b110 || funct3 == 3'b111) begin
                    illegal_instr = 1'b1;
                end
            end
            OPCODE_STORE: begin
                alu_a = op_rs1_data;
                alu_b = imm_s;
                alu_op = ALU_ADD;
                dmem_valid = (state == ST_MEMORY);
                dmem_we = 1'b1;
                dmem_wstrb = store_strobe(mem_addr_q[1:0], funct3);
                dmem_wdata = store_data(mem_addr_q[1:0], funct3, op_rs2_data);
                if (funct3 != 3'b000 && funct3 != 3'b001 && funct3 != 3'b010) begin
                    illegal_instr = 1'b1;
                end
            end
            OPCODE_AMO: begin
                reg_wen = 1'b1;
                alu_a = op_rs1_data;
                alu_b = 32'd0;
                alu_op = ALU_ADD;
                if (!amo_supported) begin
                    illegal_instr = 1'b1;
                end else if (amo_lr) begin
                    wb_data = load_word_q;
                end else if (amo_sc) begin
                    wb_data = load_word_q;
                end else begin
                    wb_data = load_word_q;
                end
            end
            OPCODE_MISC_MEM: begin
                if (funct3 != 3'b000 && funct3 != 3'b001) begin
                    illegal_instr = 1'b1;
                end
            end
            OPCODE_SYSTEM: begin
                if (system_csr) begin
                    reg_wen = 1'b1;
                    wb_data = csr_rdata;
                    if (!csr_supported || !csr_priv_ok || (csr_read_only && csr_wen)) begin
                        illegal_instr = 1'b1;
                    end
                end else if (system_sfence_vma) begin
                    if (current_priv == PRIV_U) begin
                        illegal_instr = 1'b1;
                    end
                end else if (!(system_ecall || system_ebreak || system_mret || system_sret ||
                               system_sfence_vma || system_wfi)) begin
                    illegal_instr = 1'b1;
                end
            end
            OPCODE_CUSTOM0: begin
                if (custom_xcpyw) begin
                    reg_wen = 1'b1;
                    wb_data = load_word_q;
                end else if (custom_xdm2s || custom_xds2m) begin
                    reg_wen = 1'b1;
                    wb_data = dm_status_q;
                end else begin
                    illegal_instr = 1'b1;
                end
            end
            default: begin
                illegal_instr = 1'b1;
            end
        endcase

        regfile_wen = (state == ST_WRITEBACK) &&
                      reg_wen &&
                      !page_fault_pending &&
                      !illegal_instr &&
                      !system_ecall &&
                      !system_ebreak &&
                      !system_mret &&
                      !system_sret &&
                      !system_sfence_vma &&
                      !system_wfi;

        if (state == ST_CUSTOM_LOAD) begin
            alu_a = op_rs1_data;
            alu_b = 32'd0;
            alu_op = ALU_ADD;
            dmem_valid = 1'b1;
            dmem_we = 1'b0;
            dmem_wstrb = 4'b0000;
        end else if (state == ST_CUSTOM_STORE) begin
            alu_a = op_rs2_data;
            alu_b = 32'd0;
            alu_op = ALU_ADD;
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_wstrb = 4'b1111;
            dmem_wdata = load_word_q;
        end else if (state == ST_AMO_LOAD) begin
            alu_a = op_rs1_data;
            alu_b = 32'd0;
            alu_op = ALU_ADD;
            dmem_valid = 1'b1;
            dmem_we = 1'b0;
            dmem_wstrb = 4'b0000;
        end else if (state == ST_AMO_STORE) begin
            alu_a = op_rs1_data;
            alu_b = 32'd0;
            alu_op = ALU_ADD;
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_wstrb = 4'b1111;
            dmem_wdata = amo_write_data;
        end else if (state == ST_CUSTOM_DM_CLEAR) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_addr = DM_STATUS;
            dmem_wdata = DM_STATUS_CLEAR;
            dmem_wstrb = 4'b1111;
        end else if (state == ST_CUSTOM_DM_DDR) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_addr = DM_DDR_ADDR;
            dmem_wdata = dm_addr_q;
            dmem_wstrb = 4'b1111;
        end else if (state == ST_CUSTOM_DM_LOCAL) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_addr = DM_LOCAL_ADDR;
            dmem_wdata = 32'd0;
            dmem_wstrb = 4'b1111;
        end else if (state == ST_CUSTOM_DM_LEN) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_addr = DM_LENGTH_BYTES;
            dmem_wdata = dm_len_q;
            dmem_wstrb = 4'b1111;
        end else if (state == ST_CUSTOM_DM_TAG) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_addr = DM_TAG;
            dmem_wdata = dm_is_s2mm ? 32'd2 : 32'd1;
            dmem_wstrb = 4'b1111;
        end else if (state == ST_CUSTOM_DM_START) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_addr = DM_CTRL;
            dmem_wdata = dm_is_s2mm ? DM_START_S2MM : DM_START_MM2S;
            dmem_wstrb = 4'b1111;
        end else if (state == ST_CUSTOM_DM_WAIT) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b0;
            dmem_addr = DM_STATUS;
        end

        if ((state == ST_PT_L1_WAIT || state == ST_PT_L0_WAIT) && !tlb_lookup_hit_q && !tlb_lookup_fault_q) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b0;
            dmem_wstrb = 4'b0000;
            dmem_addr = ptw_pte_addr;
            dmem_wdata = 32'd0;
        end else if (state == ST_PT_AD_REQ) begin
            dmem_valid = 1'b1;
            dmem_we = 1'b1;
            dmem_wstrb = 4'b1111;
            dmem_addr = ptw_pte_addr;
            dmem_wdata = ptw_ad_pte;
        end else if (translate_active && req_active && req_pa_valid && !req_is_fetch &&
                     (state == ST_MEMORY ||
                      state == ST_CUSTOM_LOAD ||
                      state == ST_CUSTOM_STORE ||
                      state == ST_AMO_LOAD ||
                      state == ST_AMO_STORE ||
                      state == ST_CUSTOM_DM_CLEAR ||
                      state == ST_CUSTOM_DM_DDR ||
                      state == ST_CUSTOM_DM_LOCAL ||
                      state == ST_CUSTOM_DM_LEN ||
                      state == ST_CUSTOM_DM_TAG ||
                      state == ST_CUSTOM_DM_START ||
                      state == ST_CUSTOM_DM_WAIT)) begin
            dmem_valid = 1'b1;
            dmem_we = req_we;
            dmem_wstrb = req_wstrb;
            dmem_addr = req_paddr;
            dmem_wdata = req_wdata;
        end else if (translate_active && !req_active &&
                     (state == ST_MEMORY ||
                      state == ST_CUSTOM_LOAD ||
                      state == ST_CUSTOM_STORE ||
                      state == ST_AMO_LOAD ||
                      state == ST_AMO_STORE ||
                      state == ST_CUSTOM_DM_CLEAR ||
                      state == ST_CUSTOM_DM_DDR ||
                      state == ST_CUSTOM_DM_LOCAL ||
                      state == ST_CUSTOM_DM_LEN ||
                      state == ST_CUSTOM_DM_TAG ||
                      state == ST_CUSTOM_DM_START ||
                      state == ST_CUSTOM_DM_WAIT)) begin
            dmem_valid = 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RESET;
            pc <= reset_vector;
            instr <= 32'd0;
            instr_q <= 32'd0;
            op_rs1_q <= 32'd0;
            op_rs2_q <= 32'd0;
            load_word_q <= 32'd0;
            muldiv_result_q <= 32'd0;
            div_dividend_q <= 32'd0;
            div_divisor_q <= 32'd0;
            div_quotient_q <= 32'd0;
            div_remainder_q <= 33'd0;
            div_count_q <= 6'd0;
            div_quot_neg_q <= 1'b0;
            div_rem_neg_q <= 1'b0;
            div_return_rem_q <= 1'b0;
            rd_q <= 5'd0;
            req_vaddr <= 32'd0;
            req_paddr <= 32'd0;
            req_wdata <= 32'd0;
            req_wstrb <= 4'd0;
            amo_write_data <= 32'd0;
            req_we <= 1'b0;
            req_is_fetch <= 1'b0;
            req_active <= 1'b0;
            req_pa_valid <= 1'b0;
            tlb_lookup_hit_q <= 1'b0;
            tlb_lookup_fault_q <= 1'b0;
            tlb_lookup_paddr_q <= 32'd0;
            mem_addr_q <= 32'd0;
            ptw_return_state <= ST_RESET;
            ptw_pte_addr <= 32'd0;
            ptw_l1_pte <= 32'd0;
            ptw_l0_pte <= 32'd0;
            ptw_ad_pte <= 32'd0;
            ptw_leaf_superpage <= 1'b0;
            page_fault_cause <= 32'd0;
            page_fault_tval <= 32'd0;
            page_fault_pending <= 1'b0;
            current_priv <= PRIV_M;
            csr_mstatus <= 32'h0000_1800;
            csr_medeleg <= 32'd0;
            csr_mideleg <= 32'd0;
            csr_mie <= 32'd0;
            csr_mcounteren <= 32'd0;
            csr_mtvec <= 32'd0;
            csr_sie <= 32'd0;
            csr_scounteren <= 32'd0;
            csr_stvec <= 32'd0;
            csr_sscratch <= 32'd0;
            csr_sepc <= 32'd0;
            csr_scause <= 32'd0;
            csr_stval <= 32'd0;
            csr_sip <= 32'd0;
            csr_satp <= 32'd0;
            csr_mscratch <= 32'd0;
            csr_mepc <= 32'd0;
            csr_mcause <= 32'd0;
            csr_mtval <= 32'd0;
            csr_mip <= 32'd0;
            mcycle_counter <= 64'd0;
            minstret_counter <= 64'd0;
            lr_reservation_valid <= 1'b0;
            lr_reservation_addr <= 30'd0;
            tlb_replace_ptr <= 3'd0;
            for (int i = 0; i < TLB_ENTRIES; i++) begin
                tlb_valid[i] <= 1'b0;
                tlb_global[i] <= 1'b0;
                tlb_r[i] <= 1'b0;
                tlb_w[i] <= 1'b0;
                tlb_x[i] <= 1'b0;
                tlb_u[i] <= 1'b0;
                tlb_a[i] <= 1'b0;
                tlb_d[i] <= 1'b0;
                tlb_superpage[i] <= 1'b0;
                tlb_vpn[i] <= 20'd0;
                tlb_asid[i] <= 9'd0;
                tlb_ppn[i] <= 22'd0;
            end
        end else begin
            mcycle_counter <= mcycle_counter + 64'd1;
            case (state)
                ST_RESET: begin
                    pc <= reset_vector;
                    state <= ST_FETCH;
                end
                ST_FETCH: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= pc;
                        req_paddr <= 32'd0;
                        req_wdata <= 32'd0;
                        req_wstrb <= 4'd0;
                        req_we <= 1'b0;
                        req_is_fetch <= 1'b1;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_FETCH;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, pc);
                        state <= ST_PT_L1_REQ;
                    end else if (imem_ready) begin
                        instr <= imem_rdata;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_DECODE;
                    end
                end
                ST_DECODE: begin
                    state <= ST_EXECUTE;
                end
                ST_EXECUTE: begin
                    instr_q <= instr;
                    op_rs1_q <= rs1_data;
                    op_rs2_q <= rs2_data;
                    rd_q <= rd;
                    if (opcode == OPCODE_CUSTOM0 && custom_xcpyw) begin
                        mem_addr_q <= rs1_data;
                        state <= ST_CUSTOM_LOAD;
                    end else if (opcode == OPCODE_CUSTOM0 && (custom_xdm2s || custom_xds2m)) begin
                        dm_addr_q <= rs1_data;
                        dm_len_q <= rs2_data;
                        dm_status_q <= 32'd0;
                        dm_is_s2mm <= custom_xds2m;
                        state <= ST_CUSTOM_DM_CLEAR;
                    end else if (m_supported) begin
                        if (funct3[2]) begin
                            if (rs2_data == 32'd0) begin
                                muldiv_result_q <= funct3[1] ? rs1_data : 32'hffff_ffff;
                                state <= ST_WRITEBACK;
                            end else if (!funct3[0] && (rs1_data == 32'h8000_0000) && (rs2_data == 32'hffff_ffff)) begin
                                muldiv_result_q <= funct3[1] ? 32'd0 : 32'h8000_0000;
                                state <= ST_WRITEBACK;
                            end else begin
                                div_dividend_q <= funct3[0] ? rs1_data : rv32_abs(rs1_data);
                                div_divisor_q <= funct3[0] ? rs2_data : rv32_abs(rs2_data);
                                div_quotient_q <= 32'd0;
                                div_remainder_q <= 33'd0;
                                div_count_q <= 6'd32;
                                div_quot_neg_q <= !funct3[0] && (rs1_data[31] ^ rs2_data[31]);
                                div_rem_neg_q <= !funct3[0] && rs1_data[31];
                                div_return_rem_q <= funct3[1];
                                state <= ST_MULDIV;
                            end
                        end else begin
                            muldiv_result_q <= rv32m_mul_result(funct3, rs1_data, rs2_data);
                            state <= ST_WRITEBACK;
                        end
                    end else if (amo_supported) begin
                        mem_addr_q <= rs1_data;
                        state <= ST_AMO_LOAD;
                    end else if (opcode == OPCODE_LOAD || opcode == OPCODE_STORE) begin
                        mem_addr_q <= alu_y;
                        state <= ST_MEMORY;
                    end else begin
                        state <= ST_WRITEBACK;
                    end
                end
                ST_CUSTOM_LOAD: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_LOAD;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        load_word_q <= dmem_rdata;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        mem_addr_q <= op_rs2_data;
                        state <= ST_CUSTOM_STORE;
                    end
                end
                ST_CUSTOM_STORE: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_STORE;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end
                end
                ST_CUSTOM_DM_CLEAR: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_DM_CLEAR;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        state <= ST_CUSTOM_DM_DDR;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                    end
                end
                ST_CUSTOM_DM_DDR: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_DM_DDR;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        state <= ST_CUSTOM_DM_LOCAL;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                    end
                end
                ST_CUSTOM_DM_LOCAL: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_DM_LOCAL;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        state <= ST_CUSTOM_DM_LEN;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                    end
                end
                ST_CUSTOM_DM_LEN: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_DM_LEN;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        state <= ST_CUSTOM_DM_TAG;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                    end
                end
                ST_CUSTOM_DM_TAG: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_DM_TAG;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        state <= ST_CUSTOM_DM_START;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                    end
                end
                ST_CUSTOM_DM_START: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_DM_START;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        state <= ST_CUSTOM_DM_WAIT;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                    end
                end
                ST_CUSTOM_DM_WAIT: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_CUSTOM_DM_WAIT;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        dm_status_q <= dmem_rdata;
                        if (dm_is_s2mm) begin
                            if (dmem_rdata[3] || dmem_rdata[5]) begin
                                state <= ST_WRITEBACK;
                            end
                        end else begin
                            if (dmem_rdata[2] || dmem_rdata[4]) begin
                                state <= ST_WRITEBACK;
                            end
                        end
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                    end
                end
                ST_MULDIV: begin
                    div_dividend_q <= div_step_dividend_next;
                    div_remainder_q <= div_step_rem_next;
                    div_quotient_q <= div_step_quot_next;
                    div_count_q <= div_count_q - 6'd1;
                    if (div_count_q == 6'd1) begin
                        muldiv_result_q <= div_return_rem_q ? div_step_signed_rem : div_step_signed_quot;
                        state <= ST_WRITEBACK;
                    end
                end
                ST_AMO_LOAD: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= op_rs1_data;
                        req_paddr <= 32'd0;
                        req_wdata <= op_rs2_data;
                        req_wstrb <= 4'hF;
                        req_we <= 1'b0;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_AMO_LOAD;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, op_rs1_data);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        load_word_q <= dmem_rdata;
                        if (amo_lr) begin
                            lr_reservation_valid <= 1'b1;
                            lr_reservation_addr <= (req_pa_valid ? req_paddr[31:2] : mem_addr_q[31:2]);
                            req_active <= 1'b0;
                            req_pa_valid <= 1'b0;
                            state <= ST_WRITEBACK;
                        end else if (amo_sc) begin
                            if (amo_sc_success) begin
                                load_word_q <= 32'd0;
                                amo_write_data <= op_rs2_data;
                                req_we <= 1'b1;
                                req_wdata <= op_rs2_data;
                                req_wstrb <= 4'hF;
                                state <= ST_AMO_STORE;
                            end else begin
                                load_word_q <= 32'd1;
                                lr_reservation_valid <= 1'b0;
                                req_active <= 1'b0;
                                req_pa_valid <= 1'b0;
                                state <= ST_WRITEBACK;
                            end
                        end else begin
                            state <= ST_AMO_CALC;
                        end
                    end
                end
                ST_AMO_CALC: begin
                    amo_write_data <= amo_result_word(amo_funct5, load_word_q, op_rs2_data);
                    req_we <= 1'b1;
                    req_wdata <= amo_result_word(amo_funct5, load_word_q, op_rs2_data);
                    req_wstrb <= 4'hF;
                    state <= ST_AMO_STORE;
                end
                ST_AMO_STORE: begin
                    if (dmem_ready) begin
                        lr_reservation_valid <= 1'b0;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end
                end
                ST_MEMORY: begin
                    if (translate_active && !req_active) begin
                        req_vaddr <= dmem_addr;
                        req_paddr <= 32'd0;
                        req_wdata <= dmem_wdata;
                        req_wstrb <= dmem_wstrb;
                        req_we <= dmem_we;
                        req_is_fetch <= 1'b0;
                        req_active <= 1'b1;
                        req_pa_valid <= 1'b0;
                        ptw_return_state <= ST_MEMORY;
                        ptw_pte_addr <= sv32_l1_pte_addr(csr_satp, dmem_addr);
                        state <= ST_PT_L1_REQ;
                    end else if (dmem_ready) begin
                        if (opcode == OPCODE_LOAD) begin
                            load_word_q <= dmem_rdata;
                        end else if (opcode == OPCODE_STORE) begin
                            lr_reservation_valid <= 1'b0;
                        end
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end
                end
                ST_PT_L1_REQ: begin
                    tlb_lookup_hit_q <= tlb_lookup_hit;
                    tlb_lookup_fault_q <= tlb_lookup_fault;
                    tlb_lookup_paddr_q <= tlb_lookup_paddr;
                    state <= ST_PT_L1_WAIT;
                end
                ST_PT_L1_WAIT: begin
                    if (tlb_lookup_hit_q) begin
                        req_paddr <= tlb_lookup_paddr_q;
                        req_pa_valid <= 1'b1;
                        state <= ptw_return_state;
                    end else if (tlb_lookup_fault_q) begin
                        page_fault_pending <= 1'b1;
                        page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                            req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                        page_fault_tval <= req_vaddr;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end else if (dmem_ready) begin
                        ptw_l1_pte <= dmem_rdata;
                        state <= ST_PT_L1_EVAL;
                    end
                end
                ST_PT_L1_EVAL: begin
                    if (!ptw_l1_pte[0] || (ptw_l1_pte[2] && !ptw_l1_pte[1])) begin
                        page_fault_pending <= 1'b1;
                        page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                            req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                        page_fault_tval <= req_vaddr;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end else if (ptw_l1_pte[1] || ptw_l1_pte[3]) begin
                        if (ptw_l1_pte[19:10] != 10'd0) begin
                            page_fault_pending <= 1'b1;
                            page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                                req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                            page_fault_tval <= req_vaddr;
                            req_active <= 1'b0;
                            req_pa_valid <= 1'b0;
                            state <= ST_WRITEBACK;
                        end else if ((req_is_fetch && !ptw_l1_pte[3]) ||
                                     (!req_is_fetch && req_we && !ptw_l1_pte[2]) ||
                                     (!req_is_fetch && !req_we && !ptw_l1_pte[1])) begin
                            page_fault_pending <= 1'b1;
                            page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                                req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                            page_fault_tval <= req_vaddr;
                            req_active <= 1'b0;
                            req_pa_valid <= 1'b0;
                            state <= ST_WRITEBACK;
                        end else if ((current_priv == PRIV_U && !ptw_l1_pte[4]) ||
                                     (current_priv == PRIV_S && ptw_l1_pte[4] &&
                                      (req_is_fetch || !csr_mstatus[18]))) begin
                            page_fault_pending <= 1'b1;
                            page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                                req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                            page_fault_tval <= req_vaddr;
                            req_active <= 1'b0;
                            req_pa_valid <= 1'b0;
                            state <= ST_WRITEBACK;
                        end else begin
                            req_paddr <= {ptw_l1_pte[29:20], req_vaddr[21:0]};
                            req_pa_valid <= 1'b1;
                            if (!ptw_l1_pte[6] || (req_we && !ptw_l1_pte[7])) begin
                                ptw_ad_pte <= sv32_pte_set_ad(ptw_l1_pte, req_we);
                                ptw_l1_pte <= sv32_pte_set_ad(ptw_l1_pte, req_we);
                                ptw_leaf_superpage <= 1'b1;
                                state <= ST_PT_AD_REQ;
                            end else begin
                                tlb_insert(req_vaddr, ptw_l1_pte, 1'b1);
                                state <= ptw_return_state;
                            end
                        end
                    end else begin
                        ptw_pte_addr <= sv32_l0_pte_addr(ptw_l1_pte, req_vaddr);
                        state <= ST_PT_L0_REQ;
                    end
                end
                ST_PT_L0_REQ: begin
                    tlb_lookup_hit_q <= tlb_lookup_hit;
                    tlb_lookup_fault_q <= tlb_lookup_fault;
                    tlb_lookup_paddr_q <= tlb_lookup_paddr;
                    state <= ST_PT_L0_WAIT;
                end
                ST_PT_L0_WAIT: begin
                    if (tlb_lookup_hit_q) begin
                        req_paddr <= tlb_lookup_paddr_q;
                        req_pa_valid <= 1'b1;
                        state <= ptw_return_state;
                    end else if (tlb_lookup_fault_q) begin
                        page_fault_pending <= 1'b1;
                        page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                            req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                        page_fault_tval <= req_vaddr;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end else if (dmem_ready) begin
                        ptw_l0_pte <= dmem_rdata;
                        state <= ST_PT_L0_EVAL;
                    end
                end
                ST_PT_L0_EVAL: begin
                    if (!ptw_l0_pte[0] || (ptw_l0_pte[2] && !ptw_l0_pte[1])) begin
                        page_fault_pending <= 1'b1;
                        page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                            req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                        page_fault_tval <= req_vaddr;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end else if (ptw_l0_pte[1] || ptw_l0_pte[3]) begin
                        if ((req_is_fetch && !ptw_l0_pte[3]) ||
                            (!req_is_fetch && req_we && !ptw_l0_pte[2]) ||
                            (!req_is_fetch && !req_we && !ptw_l0_pte[1])) begin
                            page_fault_pending <= 1'b1;
                            page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                                req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                            page_fault_tval <= req_vaddr;
                            req_active <= 1'b0;
                            req_pa_valid <= 1'b0;
                            state <= ST_WRITEBACK;
                        end else if ((current_priv == PRIV_U && !ptw_l0_pte[4]) ||
                                     (current_priv == PRIV_S && ptw_l0_pte[4] &&
                                      (req_is_fetch || !csr_mstatus[18]))) begin
                            page_fault_pending <= 1'b1;
                            page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                                req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                            page_fault_tval <= req_vaddr;
                            req_active <= 1'b0;
                            req_pa_valid <= 1'b0;
                            state <= ST_WRITEBACK;
                        end else begin
                            req_paddr <= {ptw_l0_pte[31:10], req_vaddr[11:0]};
                            req_pa_valid <= 1'b1;
                            if (!ptw_l0_pte[6] || (req_we && !ptw_l0_pte[7])) begin
                                ptw_ad_pte <= sv32_pte_set_ad(ptw_l0_pte, req_we);
                                ptw_l0_pte <= sv32_pte_set_ad(ptw_l0_pte, req_we);
                                ptw_leaf_superpage <= 1'b0;
                                state <= ST_PT_AD_REQ;
                            end else begin
                                tlb_insert(req_vaddr, ptw_l0_pte, 1'b0);
                                state <= ptw_return_state;
                            end
                        end
                    end else begin
                        page_fault_pending <= 1'b1;
                        page_fault_cause <= req_is_fetch ? MCAUSE_INST_PAGE_FAULT :
                                            req_we ? MCAUSE_STORE_PAGE_FAULT : MCAUSE_LOAD_PAGE_FAULT;
                        page_fault_tval <= req_vaddr;
                        req_active <= 1'b0;
                        req_pa_valid <= 1'b0;
                        state <= ST_WRITEBACK;
                    end
                end
                ST_PT_AD_REQ: begin
                    if (dmem_ready) begin
                        tlb_insert(req_vaddr, ptw_ad_pte, ptw_leaf_superpage);
                        state <= ptw_return_state;
                    end
                end
                ST_WRITEBACK: begin
                    if (illegal_instr || system_ecall || system_ebreak || page_fault_pending) begin
                        if (trap_to_s) begin
                            csr_sepc <= pc;
                            csr_scause <= trap_cause;
                            csr_stval <= trap_tval;
                            csr_mstatus[5] <= csr_mstatus[1];
                            csr_mstatus[1] <= 1'b0;
                            csr_mstatus[8] <= (current_priv == PRIV_S);
                            current_priv <= PRIV_S;
                            pc <= {csr_stvec[31:2], 2'b00};
                        end else begin
                            csr_mepc <= pc;
                            csr_mcause <= trap_cause;
                            csr_mtval <= trap_tval;
                            csr_mstatus[7] <= csr_mstatus[3];
                            csr_mstatus[3] <= 1'b0;
                            csr_mstatus[12:11] <= current_priv;
                            current_priv <= PRIV_M;
                            pc <= {csr_mtvec[31:2], 2'b00};
                        end
                        page_fault_pending <= 1'b0;
                    end else if (interrupt_cause != 32'd0) begin
                        if (interrupt_to_s) begin
                            csr_sepc <= next_pc;
                            csr_scause <= interrupt_cause;
                            csr_stval <= 32'd0;
                            csr_mstatus[5] <= csr_mstatus[1];
                            csr_mstatus[1] <= 1'b0;
                            csr_mstatus[8] <= (current_priv == PRIV_S);
                            current_priv <= PRIV_S;
                            pc <= {csr_stvec[31:2], 2'b00};
                        end else if (interrupt_to_m) begin
                            csr_mepc <= next_pc;
                            csr_mcause <= interrupt_cause;
                            csr_mtval <= 32'd0;
                            csr_mstatus[7] <= csr_mstatus[3];
                            csr_mstatus[3] <= 1'b0;
                            csr_mstatus[12:11] <= current_priv;
                            current_priv <= PRIV_M;
                            pc <= {csr_mtvec[31:2], 2'b00};
                        end
                    end else if (system_mret) begin
                        minstret_counter <= minstret_counter + 64'd1;
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
                    end else if (system_sret) begin
                        minstret_counter <= minstret_counter + 64'd1;
                        csr_mstatus[1] <= csr_mstatus[5];
                        csr_mstatus[5] <= 1'b1;
                        csr_mstatus[8] <= 1'b0;
                        if (csr_mstatus[8]) begin
                            current_priv <= PRIV_S;
                        end else begin
                            current_priv <= PRIV_U;
                        end
                        pc <= csr_sepc;
                    end else if (system_sfence_vma) begin
                        minstret_counter <= minstret_counter + 64'd1;
                        for (int i = 0; i < TLB_ENTRIES; i++) begin
                            if (tlb_valid[i] &&
                                sfence_vma_match(tlb_superpage[i], tlb_vpn[i], tlb_asid[i], tlb_global[i],
                                                 op_rs1_data, op_rs2_data)) begin
                                tlb_valid[i] <= 1'b0;
                            end
                        end
                        pc <= next_pc;
                    end else begin
                        minstret_counter <= minstret_counter + 64'd1;
                        if (system_csr && csr_wen) begin
                            case (csr_addr)
                                CSR_SSTATUS: csr_mstatus <= (csr_mstatus & ~SSTATUS_MASK) | (csr_wdata & SSTATUS_MASK);
                                CSR_SIE:     csr_sie <= csr_wdata;
                                CSR_STVEC:   csr_stvec <= {csr_wdata[31:2], 2'b00};
                                CSR_SCOUNTEREN: csr_scounteren <= csr_wdata;
                                CSR_SSCRATCH: csr_sscratch <= csr_wdata;
                                CSR_SEPC:    csr_sepc <= {csr_wdata[31:2], 2'b00};
                                CSR_SCAUSE:  csr_scause <= csr_wdata;
                                CSR_STVAL:   csr_stval <= csr_wdata;
                                CSR_SIP:     csr_sip <= csr_wdata;
                                CSR_SATP:    csr_satp <= csr_wdata;
                                CSR_MSTATUS:  csr_mstatus <= {csr_wdata[31:13], csr_wdata[12:11], csr_wdata[10:8], csr_wdata[7], csr_wdata[6:4], csr_wdata[3], csr_wdata[2:0]};
                                CSR_MEDELEG:  csr_medeleg <= csr_wdata;
                                CSR_MIDELEG:  csr_mideleg <= csr_wdata;
                                CSR_MIE:      csr_mie <= csr_wdata;
                                CSR_MCOUNTEREN: csr_mcounteren <= csr_wdata;
                                CSR_MTVEC:    csr_mtvec <= {csr_wdata[31:2], 2'b00};
                                CSR_MSCRATCH: csr_mscratch <= csr_wdata;
                                CSR_MEPC:     csr_mepc <= {csr_wdata[31:2], 2'b00};
                                CSR_MCAUSE:   csr_mcause <= csr_wdata;
                                CSR_MTVAL:    csr_mtval <= csr_wdata;
                                CSR_MIP:      csr_mip <= csr_wdata;
                                CSR_MCYCLE:   mcycle_counter[31:0] <= csr_wdata;
                                CSR_MCYCLEH:  mcycle_counter[63:32] <= csr_wdata;
                                CSR_MINSTRET: minstret_counter[31:0] <= csr_wdata;
                                CSR_MINSTRETH: minstret_counter[63:32] <= csr_wdata;
                                default: begin
                                end
                            endcase
                        end
                        pc <= next_pc;
                    end
                    state <= ST_FETCH;
                end
                default: begin
                    state <= ST_RESET;
                end
            endcase
        end
    end
endmodule
