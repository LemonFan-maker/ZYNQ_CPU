module tb_zx64_core5;
    localparam int IMEM_WORDS = 8192;
    localparam int DMEM_WORDS = 4096;

    logic clk;
    logic rst_n;
    logic soft_reset;
    logic [63:0] reset_vector;
    logic irq_timer;
    logic irq_external;

    logic        imem_valid;
    logic [31:0] imem_addr;
    logic        imem_ready;
    logic [31:0] imem_rdata;

    logic        dmem_valid;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [31:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic        dmem_ready;
    logic [63:0] dmem_rdata;

    logic        halted;
    logic        illegal_instr;
    logic [31:0] dbg_state;
    logic [63:0] dbg_pc;
    logic [31:0] dbg_instr;

    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [63:0] dmem [0:DMEM_WORDS-1];
    integer pcw;
    integer pch;
    integer ecall_pcw;
    integer s_ecall_pcw;
    integer illegal_pcw;
    integer irq_delay;
    logic seen_wfi;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    zx64_core5 u_core (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(soft_reset),
        .reset_vector(reset_vector),
        .irq_timer(irq_timer),
        .irq_external(irq_external),
        .imem_valid(imem_valid),
        .imem_addr(imem_addr),
        .imem_ready(imem_ready),
        .imem_rdata(imem_rdata),
        .dmem_valid(dmem_valid),
        .dmem_we(dmem_we),
        .dmem_wstrb(dmem_wstrb),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_ready(dmem_ready),
        .dmem_rdata(dmem_rdata),
        .halted(halted),
        .illegal_instr(illegal_instr),
        .dbg_state(dbg_state),
        .dbg_pc(dbg_pc),
        .dbg_instr(dbg_instr)
    );

    assign imem_ready = imem_valid;
    assign imem_rdata = imem[imem_addr[31:2]];
    assign dmem_ready = dmem_valid;
    assign dmem_rdata = dmem[dmem_addr[31:3]];

    always_ff @(posedge clk) begin
        if (dmem_valid && dmem_we && dmem_ready) begin
            if (dmem_wstrb[0]) dmem[dmem_addr[31:3]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) dmem[dmem_addr[31:3]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) dmem[dmem_addr[31:3]][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) dmem[dmem_addr[31:3]][31:24] <= dmem_wdata[31:24];
            if (dmem_wstrb[4]) dmem[dmem_addr[31:3]][39:32] <= dmem_wdata[39:32];
            if (dmem_wstrb[5]) dmem[dmem_addr[31:3]][47:40] <= dmem_wdata[47:40];
            if (dmem_wstrb[6]) dmem[dmem_addr[31:3]][55:48] <= dmem_wdata[55:48];
            if (dmem_wstrb[7]) dmem[dmem_addr[31:3]][63:56] <= dmem_wdata[63:56];
        end
    end

    function automatic logic [31:0] enc_r(input logic [6:0] funct7,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_i(input logic signed [11:0] imm,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_i = {imm[11:0], rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_s(input logic signed [11:0] imm,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [6:0] opcode);
        enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] enc_b(input logic signed [12:0] imm,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [6:0] opcode);
        enc_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] enc_u(input logic [19:0] imm20,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_u = {imm20, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_j(input logic signed [20:0] imm,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    function automatic logic [31:0] enc_csr(input logic [11:0] csr,
                                            input logic [4:0] rs1,
                                            input logic [2:0] funct3,
                                            input logic [4:0] rd);
        enc_csr = {csr, rs1, funct3, rd, 7'b1110011};
    endfunction

    function automatic logic [31:0] enc_amo(input logic [4:0] funct5,
                                            input logic [4:0] rs2,
                                            input logic [4:0] rs1,
                                            input logic [2:0] funct3,
                                            input logic [4:0] rd);
        enc_amo = {funct5, 1'b0, 1'b0, rs2, rs1, funct3, rd, 7'b0101111};
    endfunction

    function automatic logic [15:0] c_addi(input logic [4:0] rd,
                                           input logic signed [5:0] imm);
        c_addi = {3'b000, imm[5], rd, imm[4:0], 2'b01};
    endfunction

    function automatic logic [15:0] c_addiw(input logic [4:0] rd,
                                            input logic signed [5:0] imm);
        c_addiw = {3'b001, imm[5], rd, imm[4:0], 2'b01};
    endfunction

    function automatic logic [15:0] c_li(input logic [4:0] rd,
                                         input logic signed [5:0] imm);
        c_li = {3'b010, imm[5], rd, imm[4:0], 2'b01};
    endfunction

    function automatic logic [15:0] c_addi4spn(input logic [2:0] rdp,
                                               input logic [9:0] imm);
        c_addi4spn = {3'b000, imm[5:4], imm[9:6], imm[2], imm[3], rdp, 2'b00};
    endfunction

    function automatic logic [15:0] c_addi16sp(input logic signed [9:0] imm);
        c_addi16sp = {3'b011, imm[9], 5'd2, imm[4], imm[6], imm[8:7], imm[5], 2'b01};
    endfunction

    function automatic logic [15:0] c_ldsp(input logic [4:0] rd,
                                           input logic [8:0] imm);
        c_ldsp = {3'b011, imm[5], rd, imm[4:3], imm[8:6], 2'b10};
    endfunction

    function automatic logic [15:0] c_fldsp(input logic [4:0] rd,
                                            input logic [8:0] imm);
        c_fldsp = {3'b001, imm[5], rd, imm[4:3], imm[8:6], 2'b10};
    endfunction

    function automatic logic [15:0] c_sdsp(input logic [4:0] rs2,
                                           input logic [8:0] imm);
        c_sdsp = {3'b111, imm[5:3], imm[8:6], rs2, 2'b10};
    endfunction

    function automatic logic [15:0] c_fsdsp(input logic [4:0] rs2,
                                            input logic [8:0] imm);
        c_fsdsp = {3'b101, imm[5:3], imm[8:6], rs2, 2'b10};
    endfunction

    function automatic logic [15:0] c_ld(input logic [2:0] rd,
                                         input logic [2:0] rs1,
                                         input logic [7:0] imm);
        c_ld = {3'b011, imm[5:3], rs1, imm[7:6], rd, 2'b00};
    endfunction

    function automatic logic [15:0] c_fld(input logic [2:0] rd,
                                          input logic [2:0] rs1,
                                          input logic [7:0] imm);
        c_fld = {3'b001, imm[5:3], rs1, imm[7:6], rd, 2'b00};
    endfunction

    function automatic logic [15:0] c_sd(input logic [2:0] rs2,
                                         input logic [2:0] rs1,
                                         input logic [7:0] imm);
        c_sd = {3'b111, imm[5:3], rs1, imm[7:6], rs2, 2'b00};
    endfunction

    function automatic logic [15:0] c_fsd(input logic [2:0] rs2,
                                          input logic [2:0] rs1,
                                          input logic [7:0] imm);
        c_fsd = {3'b101, imm[5:3], rs1, imm[7:6], rs2, 2'b00};
    endfunction

    function automatic logic [15:0] c_slli(input logic [4:0] rd,
                                           input logic [5:0] shamt);
        c_slli = {3'b000, shamt[5], rd, shamt[4:0], 2'b10};
    endfunction

    function automatic logic [15:0] c_srli(input logic [2:0] rd,
                                           input logic [5:0] shamt);
        c_srli = {3'b100, shamt[5], 2'b00, rd, shamt[4:0], 2'b01};
    endfunction

    function automatic logic [15:0] c_andi(input logic [2:0] rd,
                                           input logic signed [5:0] imm);
        c_andi = {3'b100, imm[5], 2'b10, rd, imm[4:0], 2'b01};
    endfunction

    function automatic logic [15:0] c_beqz(input logic [2:0] rs1,
                                           input logic signed [8:0] imm);
        c_beqz = {3'b110, imm[8], imm[4:3], rs1, imm[7:6], imm[2:1], imm[5], 2'b01};
    endfunction

    function automatic logic [15:0] c_bnez(input logic [2:0] rs1,
                                           input logic signed [8:0] imm);
        c_bnez = {3'b111, imm[8], imm[4:3], rs1, imm[7:6], imm[2:1], imm[5], 2'b01};
    endfunction

    function automatic logic [15:0] c_j(input logic signed [11:0] imm);
        c_j = {3'b101, imm[11], imm[4], imm[9:8], imm[10], imm[6],
               imm[7], imm[3:1], imm[5], 2'b01};
    endfunction

    function automatic logic [15:0] c_ebreak;
        c_ebreak = 16'h9002;
    endfunction

    task automatic emit(input logic [31:0] inst);
        begin
            imem[pcw] = inst;
            pcw = pcw + 1;
        end
    endtask

    task automatic emit_nop;
        begin
            emit(enc_i(12'sd0, 5'd0, 3'b000, 5'd0, 7'b0010011));
        end
    endtask

    task automatic seek(input int byte_addr);
        begin
            pcw = byte_addr >> 2;
        end
    endtask

    task automatic emit16(input logic [15:0] inst);
        begin
            if (pch[0]) begin
                imem[pch >> 1][31:16] = inst;
            end else begin
                imem[pch >> 1][15:0] = inst;
            end
            pch = pch + 1;
        end
    endtask

    task automatic emit32(input logic [31:0] inst);
        begin
            emit16(inst[15:0]);
            emit16(inst[31:16]);
        end
    endtask

    task automatic expect64(input int idx, input logic [63:0] expected, input string label);
        begin
            if (dmem[idx] !== expected) begin
                $fatal(1, "%s expected dmem[%0d]=%016x got %016x pc=%016x instr=%08x state=%08x illegal=%0d",
                       label, idx, expected, dmem[idx], dbg_pc, dbg_instr, dbg_state, illegal_instr);
            end
        end
    endtask

    task automatic clear_memories;
        begin
            for (int i = 0; i < IMEM_WORDS; i++) begin
                imem[i] = 32'h0010_0073; // ebreak
            end
            for (int i = 0; i < DMEM_WORDS; i++) begin
                dmem[i] = 64'd0;
            end
        end
    endtask

    function automatic logic [31:0] enc_fp_r4(input logic [4:0] rs3,
                                             input logic [1:0] fmt,
                                             input logic [4:0] rs2,
                                             input logic [4:0] rs1,
                                             input logic [2:0] rm,
                                             input logic [4:0] rd,
                                             input logic [6:0] opcode);
        enc_fp_r4 = {rs3, fmt, rs2, rs1, rm, rd, opcode};
    endfunction

    task automatic pulse_soft_reset;
        begin
            irq_timer = 1'b0;
            irq_external = 1'b0;
            soft_reset = 1'b1;
            @(posedge clk);
            soft_reset = 1'b0;
        end
    endtask

    task automatic wait_for_halt(input int max_cycles, input string label);
        begin
            for (int cycle = 0; cycle < max_cycles && !halted; cycle++) begin
                @(posedge clk);
            end

            if (!halted || illegal_instr) begin
                $fatal(1, "%s did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                       label, halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
            end
        end
    endtask

    task automatic run_illegal_instr_trap(input logic [31:0] inst,
                                          input logic [63:0] resume_value,
                                          input string label);
        begin
            clear_memories();
            dmem[0] = 64'hfeed_face_cafe_beef;
            dmem[48] = 64'h1122_3344_5566_7788;

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 128
            emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                // csrw  mtvec, x2
            illegal_pcw = pcw;
            emit(inst);
            emit(enc_i(resume_value[11:0], 5'd0, 3'b000, 5'd3, 7'b0010011)); // addi x3, x0, resume
            emit(enc_s(12'sd0, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd    x3, 0(x1)
            emit(32'h0010_0073);                                       // ebreak

            pcw = 32;
            emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd4));                // csrr  x4, mepc
            emit(enc_s(12'sd8, 5'd4, 5'd1, 3'b011, 7'b0100011));       // sd    x4, 8(x1)
            emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd5));                // csrr  x5, mcause
            emit(enc_s(12'sd16, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 16(x1)
            emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd6));                // csrr  x6, mtval
            emit(enc_s(12'sd24, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 24(x1)
            emit(enc_i(12'sd4, 5'd4, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x4, 4
            emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                // csrw  mepc, x4
            emit(32'h3020_0073);                                       // mret

            pulse_soft_reset();
            wait_for_halt(500, label);

            expect64(0, 64'hfeed_face_cafe_beef, {label, " did not touch dmem[0]"});
            expect64(32, resume_value, {label, " resumed after mret"});
            expect64(33, 64'(illegal_pcw * 4), {label, " mepc"});
            expect64(34, 64'h0000_0000_0000_0002, {label, " mcause"});
            expect64(35, {32'd0, inst}, {label, " mtval"});
            expect64(48, 64'h1122_3344_5566_7788, {label, " did not touch sentinel dmem"});
        end
    endtask

    task automatic run_fpu_csr_substrate_test;
        begin
            clear_memories();

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_csr(12'h301, 5'd0, 3'b010, 5'd3));                // csrr  x3, misa
            emit(enc_s(12'sd0, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd    x3, 0(x1)
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit_nop();
            emit(enc_i(12'sd27, 5'd0, 3'b000, 5'd5, 7'b0010011));      // addi  x5, x0, 27
            emit(enc_csr(12'h001, 5'd5, 3'b001, 5'd0));                // csrw  fflags, x5
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd8, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 8(x1)
            emit(enc_i(12'sd5, 5'd0, 3'b000, 5'd5, 7'b0010011));       // addi  x5, x0, 5
            emit(enc_csr(12'h002, 5'd5, 3'b001, 5'd0));                // csrw  frm, x5
            emit_nop();
            emit(enc_csr(12'h002, 5'd0, 3'b010, 5'd6));                // csrr  x6, frm
            emit(enc_s(12'sd16, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 16(x1)
            emit(enc_i(12'sd165, 5'd0, 3'b000, 5'd5, 7'b0010011));     // addi  x5, x0, 0xa5
            emit(enc_csr(12'h003, 5'd5, 3'b001, 5'd0));                // csrw  fcsr, x5
            emit_nop();
            emit(enc_csr(12'h003, 5'd0, 3'b010, 5'd6));                // csrr  x6, fcsr
            emit(enc_s(12'sd24, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 24(x1)
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd6));                // csrr  x6, mstatus
            emit(enc_s(12'sd32, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 32(x1)
            emit(enc_csr(12'h100, 5'd0, 3'b010, 5'd6));                // csrr  x6, sstatus
            emit(enc_s(12'sd40, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 40(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(500, "ZX64 five-stage FPU CSR substrate test");

            expect64(32, 64'h8000_0000_0004_112d, "misa advertises RV64GC after F/D coverage");
            expect64(33, 64'h0000_0000_0000_001b, "fflags CSR write/read");
            expect64(34, 64'h0000_0000_0000_0005, "frm CSR write/read");
            expect64(35, 64'h0000_0000_0000_00a5, "fcsr CSR write/read");
            expect64(36, 64'h8000_0000_0000_6000, "mstatus FS dirty after FCSR write");
            expect64(37, 64'h8000_0000_0000_6000, "sstatus exposes FS dirty and SD");
        end
    endtask

    task automatic run_fpu_state_move_test;
        begin
            clear_memories();

            dmem[8] = 64'h1122_3344_5566_7788;
            dmem[9] = 64'h8877_6655_4433_2211;
            dmem[10] = 64'h0000_0000_4049_0fdb;
            dmem[11] = 64'h0000_0000_9abc_def0;

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_r(7'b1110001, 5'd0, 5'd1, 3'b000, 5'd5, 7'b1010011)); // fmv.x.d x5, f1
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)

            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd6, 7'b0000011));       // ld    x6, 8(x2)
            emit(enc_r(7'b1111001, 5'd0, 5'd6, 3'b000, 5'd2, 7'b1010011)); // fmv.d.x f2, x6
            emit(enc_s(12'sd8, 5'd2, 5'd1, 3'b011, 7'b0100111));       // fsd   f2, 8(x1)

            emit(enc_i(12'sd16, 5'd2, 3'b010, 5'd3, 7'b0000111));      // flw   f3, 16(x2)
            emit(enc_r(7'b1110001, 5'd0, 5'd3, 3'b000, 5'd7, 7'b1010011)); // fmv.x.d x7, f3
            emit(enc_s(12'sd16, 5'd7, 5'd1, 3'b011, 7'b0100011));      // sd    x7, 16(x1)

            emit(enc_i(12'sd24, 5'd2, 3'b011, 5'd8, 7'b0000011));      // ld    x8, 24(x2)
            emit(enc_r(7'b1111000, 5'd0, 5'd8, 3'b000, 5'd4, 7'b1010011)); // fmv.w.x f4, x8
            emit(enc_s(12'sd24, 5'd4, 5'd1, 3'b010, 7'b0100111));      // fsw   f4, 24(x1)

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd5, 7'b0000111));       // fld   f5, 0(x2)
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd6, 7'b0000111));       // fld   f6, 8(x2)
            emit(enc_r(7'b0010001, 5'd6, 5'd5, 3'b000, 5'd7, 7'b1010011)); // fsgnj.d f7, f5, f6
            emit(enc_r(7'b1110001, 5'd0, 5'd7, 3'b000, 5'd9, 7'b1010011)); // fmv.x.d x9, f7
            emit(enc_s(12'sd32, 5'd9, 5'd1, 3'b011, 7'b0100011));      // sd    x9, 32(x1)
            emit(enc_r(7'b0010001, 5'd6, 5'd5, 3'b001, 5'd8, 7'b1010011)); // fsgnjn.d f8, f5, f6
            emit(enc_r(7'b1110001, 5'd0, 5'd8, 3'b000, 5'd11, 7'b1010011)); // fmv.x.d x11, f8
            emit(enc_s(12'sd48, 5'd11, 5'd1, 3'b011, 7'b0100011));     // sd    x11, 48(x1)
            emit(enc_r(7'b0010001, 5'd6, 5'd5, 3'b010, 5'd8, 7'b1010011)); // fsgnjx.d f8, f5, f6
            emit(enc_r(7'b1110001, 5'd0, 5'd8, 3'b000, 5'd11, 7'b1010011)); // fmv.x.d x11, f8
            emit(enc_s(12'sd56, 5'd11, 5'd1, 3'b011, 7'b0100011));     // sd    x11, 56(x1)
            emit(enc_r(7'b0010000, 5'd4, 5'd3, 3'b001, 5'd8, 7'b1010011)); // fsgnjn.s f8, f3, f4
            emit(enc_r(7'b1110000, 5'd0, 5'd8, 3'b000, 5'd11, 7'b1010011)); // fmv.x.w x11, f8
            emit(enc_s(12'sd64, 5'd11, 5'd1, 3'b011, 7'b0100011));     // sd    x11, 64(x1)
            emit(enc_r(7'b0010000, 5'd4, 5'd3, 3'b010, 5'd8, 7'b1010011)); // fsgnjx.s f8, f3, f4
            emit(enc_r(7'b1110000, 5'd0, 5'd8, 3'b000, 5'd11, 7'b1010011)); // fmv.x.w x11, f8
            emit(enc_s(12'sd72, 5'd11, 5'd1, 3'b011, 7'b0100011));     // sd    x11, 72(x1)

            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd10));               // csrr  x10, mstatus
            emit(enc_s(12'sd40, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 40(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1000, "ZX64 five-stage FPU state move test");

            expect64(32, 64'h1122_3344_5566_7788, "FLD/FMV.X.D bit-preserving path");
            expect64(33, 64'h8877_6655_4433_2211, "FMV.D.X/FSD bit-preserving path");
            expect64(34, 64'hffff_ffff_4049_0fdb, "FLW NaN-boxing path");
            expect64(35, 64'h0000_0000_9abc_def0, "FMV.W.X/FSW low-word path");
            expect64(36, 64'h9122_3344_5566_7788, "FSGNJ.D sign injection path");
            expect64(37, 64'h8000_0000_0000_6000, "FPR write marks FS dirty");
            expect64(38, 64'h1122_3344_5566_7788, "FSGNJN.D sign injection path");
            expect64(39, 64'h9122_3344_5566_7788, "FSGNJX.D sign injection path");
            expect64(40, 64'h0000_0000_4049_0fdb, "FSGNJN.S/FMV.X.W sign injection path");
            expect64(41, 64'hffff_ffff_c049_0fdb, "FSGNJX.S/FMV.X.W sign injection path");
        end
    endtask

    task automatic run_fpu_compressed_mem_test;
        begin
            clear_memories();

            dmem[8] = 64'haaaa_bbbb_cccc_dddd;
            dmem[9] = 64'h0123_4567_89ab_cdef;

            pch = 0;
            emit32(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));  // addi  x1, x0, 256
            emit32(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));   // addi  sp, x0, 64
            emit32(enc_i(12'sd64, 5'd0, 3'b000, 5'd10, 7'b0010011));  // addi  x10, x0, 64
            emit32(enc_i(12'sd256, 5'd0, 3'b000, 5'd11, 7'b0010011)); // addi  x11, x0, 256
            emit32(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));    // addi  x4, x0, 1
            emit32(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));   // slli  x4, x4, 13 (FS=Initial)
            emit32(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));             // csrw  mstatus, x4
            emit32(enc_i(12'sd0, 5'd0, 3'b000, 5'd0, 7'b0010011));    // nop

            emit16(c_fld(3'd1, 3'd2, 8'd0));                          // c.fld   f9, 0(x10)
            emit16(c_fsd(3'd1, 3'd3, 8'd0));                          // c.fsd   f9, 0(x11)
            emit16(c_fldsp(5'd10, 9'd8));                             // c.fldsp f10, 8(sp)
            emit16(c_fsdsp(5'd10, 9'd16));                            // c.fsdsp f10, 16(sp)

            emit32(enc_csr(12'h300, 5'd0, 3'b010, 5'd12));            // csrr  x12, mstatus
            emit32(enc_s(12'sd8, 5'd12, 5'd1, 3'b011, 7'b0100011));   // sd    x12, 8(x1)
            emit16(c_ebreak());

            pulse_soft_reset();
            wait_for_halt(1000, "ZX64 five-stage compressed FPU memory test");

            expect64(32, 64'haaaa_bbbb_cccc_dddd, "C.FLD/C.FSD bit-preserving path");
            expect64(10, 64'h0123_4567_89ab_cdef, "C.FLDSP/C.FSDSP bit-preserving path");
            expect64(33, 64'h8000_0000_0000_6000, "compressed FPR load marks FS dirty");
        end
    endtask

    task automatic run_fpu_int_to_float_cvt_test;
        begin
            clear_memories();

            dmem[8] = 64'h0000_0000_0100_0001; // 2^24 + 1
            dmem[9] = 64'h0000_0000_ffff_ffff;

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit_nop();

            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd5, 7'b0010011));       // addi  x5, x0, 1
            emit(enc_r(7'b1101001, 5'd0, 5'd5, 3'b000, 5'd1, 7'b1010011)); // fcvt.d.w f1, x5, rne
            emit(enc_r(7'b1110001, 5'd0, 5'd1, 3'b000, 5'd6, 7'b1010011)); // fmv.x.d x6, f1
            emit(enc_s(12'sd0, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 0(x1)

            emit(enc_i(-12'sd2, 5'd0, 3'b000, 5'd5, 7'b0010011));      // addi  x5, x0, -2
            emit(enc_r(7'b1101001, 5'd0, 5'd5, 3'b000, 5'd2, 7'b1010011)); // fcvt.d.w f2, x5, rne
            emit(enc_r(7'b1110001, 5'd0, 5'd2, 3'b000, 5'd6, 7'b1010011)); // fmv.x.d x6, f2
            emit(enc_s(12'sd8, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 8(x1)

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd5, 7'b0000011));       // ld    x5, 0(x2)
            emit(enc_r(7'b1101000, 5'd3, 5'd5, 3'b011, 5'd3, 7'b1010011)); // fcvt.s.lu f3, x5, rup
            emit(enc_r(7'b1110000, 5'd0, 5'd3, 3'b000, 5'd6, 7'b1010011)); // fmv.x.w x6, f3
            emit(enc_s(12'sd16, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 16(x1)
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd24, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 24(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd5, 7'b0000011));       // ld    x5, 8(x2)
            emit(enc_r(7'b1101001, 5'd1, 5'd5, 3'b000, 5'd4, 7'b1010011)); // fcvt.d.wu f4, x5, rne
            emit(enc_r(7'b1110001, 5'd0, 5'd4, 3'b000, 5'd6, 7'b1010011)); // fmv.x.d x6, f4
            emit(enc_s(12'sd32, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 32(x1)
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd40, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 40(x1)

            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd7, 7'b0010011));       // addi  x7, x0, 1 (RTZ)
            emit(enc_csr(12'h002, 5'd7, 3'b001, 5'd0));                // csrw  frm, x7
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd5, 7'b0000011));       // ld    x5, 0(x2)
            emit(enc_r(7'b1101000, 5'd3, 5'd5, 3'b111, 5'd5, 7'b1010011)); // fcvt.s.lu f5, x5, dyn/rtz
            emit(enc_r(7'b1110000, 5'd0, 5'd5, 3'b000, 5'd6, 7'b1010011)); // fmv.x.w x6, f5
            emit(enc_s(12'sd48, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 48(x1)
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd56, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 56(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1200, "ZX64 five-stage FPU integer-to-float conversion test");

            expect64(32, 64'h3ff0_0000_0000_0000, "FCVT.D.W exact positive");
            expect64(33, 64'hc000_0000_0000_0000, "FCVT.D.W exact negative");
            expect64(34, 64'h0000_0000_4b80_0001, "FCVT.S.LU static RUP inexact rounding");
            expect64(35, 64'h0000_0000_0000_0001, "FCVT.S.LU static RUP sets NX");
            expect64(36, 64'h41ef_ffff_ffe0_0000, "FCVT.D.WU exact 32-bit unsigned");
            expect64(37, 64'h0000_0000_0000_0000, "FCVT.D.WU exact leaves fflags clear");
            expect64(38, 64'h0000_0000_4b80_0000, "FCVT.S.LU dynamic RTZ rounding");
            expect64(39, 64'h0000_0000_0000_0001, "FCVT.S.LU dynamic RTZ sets NX");
        end
    endtask

    task automatic run_fpu_float_to_int_cvt_test;
        begin
            clear_memories();

            dmem[8]  = 64'h3ff8_0000_0000_0000; // +1.5D
            dmem[9]  = 64'hc006_0000_0000_0000; // -2.75D
            dmem[10] = 64'h0000_0000_4060_0000; // +3.5S
            dmem[11] = 64'h0000_0000_bfc0_0000; // -1.5S
            dmem[12] = 64'h0000_0000_7fc0_0001; // qNaN.S
            dmem[13] = 64'h0000_0000_5380_0000; // +2^40S, overflows W

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit_nop();

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_r(7'b1100001, 5'd0, 5'd1, 3'b000, 5'd5, 7'b1010011)); // fcvt.w.d x5, f1, rne
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd8, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 8(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd2, 7'b0000111));       // fld   f2, 8(x2)
            emit(enc_r(7'b1100001, 5'd2, 5'd2, 3'b001, 5'd5, 7'b1010011)); // fcvt.l.d x5, f2, rtz
            emit(enc_s(12'sd16, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 16(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd24, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 24(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd16, 5'd2, 3'b010, 5'd3, 7'b0000111));      // flw   f3, 16(x2)
            emit(enc_r(7'b1100000, 5'd1, 5'd3, 3'b000, 5'd5, 7'b1010011)); // fcvt.wu.s x5, f3, rne
            emit(enc_s(12'sd32, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 32(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd40, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 40(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd24, 5'd2, 3'b010, 5'd4, 7'b0000111));      // flw   f4, 24(x2)
            emit(enc_r(7'b1100000, 5'd0, 5'd4, 3'b010, 5'd5, 7'b1010011)); // fcvt.w.s x5, f4, rdn
            emit(enc_s(12'sd48, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 48(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd56, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 56(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd32, 5'd2, 3'b010, 5'd5, 7'b0000111));      // flw   f5, 32(x2)
            emit(enc_r(7'b1100000, 5'd0, 5'd5, 3'b000, 5'd7, 7'b1010011)); // fcvt.w.s x7, qnan, rne
            emit(enc_s(12'sd64, 5'd7, 5'd1, 3'b011, 7'b0100011));      // sd    x7, 64(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd72, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 72(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd40, 5'd2, 3'b010, 5'd6, 7'b0000111));      // flw   f6, 40(x2)
            emit(enc_r(7'b1100000, 5'd0, 5'd6, 3'b000, 5'd7, 7'b1010011)); // fcvt.w.s x7, +2^40, rne
            emit(enc_s(12'sd80, 5'd7, 5'd1, 3'b011, 7'b0100011));      // sd    x7, 80(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd6));                // csrr  x6, fflags
            emit(enc_s(12'sd88, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 88(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1600, "ZX64 five-stage FPU float-to-integer conversion test");

            expect64(32, 64'h0000_0000_0000_0002, "FCVT.W.D RNE rounds 1.5 to even 2");
            expect64(33, 64'h0000_0000_0000_0001, "FCVT.W.D RNE sets NX");
            expect64(34, 64'hffff_ffff_ffff_fffe, "FCVT.L.D RTZ truncates -2.75");
            expect64(35, 64'h0000_0000_0000_0001, "FCVT.L.D RTZ sets NX");
            expect64(36, 64'h0000_0000_0000_0004, "FCVT.WU.S RNE rounds 3.5 to even 4");
            expect64(37, 64'h0000_0000_0000_0001, "FCVT.WU.S RNE sets NX");
            expect64(38, 64'hffff_ffff_ffff_fffe, "FCVT.W.S RDN floors -1.5");
            expect64(39, 64'h0000_0000_0000_0001, "FCVT.W.S RDN sets NX");
            expect64(40, 64'h0000_0000_7fff_ffff, "FCVT.W.S qNaN saturates");
            expect64(41, 64'h0000_0000_0000_0010, "FCVT.W.S qNaN sets NV");
            expect64(42, 64'h0000_0000_7fff_ffff, "FCVT.W.S overflow saturates");
            expect64(43, 64'h0000_0000_0000_0010, "FCVT.W.S overflow sets NV");
        end
    endtask

    task automatic run_fpu_addsub_test;
        begin
            clear_memories();

            dmem[8]  = 64'h3ff0_0000_0000_0000; // +1.0D
            dmem[9]  = 64'h4000_0000_0000_0000; // +2.0D
            dmem[10] = 64'h0000_0000_3fc0_0000; // +1.5S
            dmem[11] = 64'h0000_0000_4010_0000; // +2.25S
            dmem[12] = 64'h7ff0_0000_0000_0000; // +infD
            dmem[13] = 64'hfff0_0000_0000_0000; // -infD

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd2, 7'b0000111));       // fld   f2, 8(x2)
            emit(enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, 7'b1010011)); // fadd.d f3, f1, f2
            emit(enc_r(7'b1110001, 5'd0, 5'd3, 3'b000, 5'd5, 7'b1010011)); // fmv.x.d x5, f3
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)

            emit(enc_r(7'b0000101, 5'd2, 5'd1, 3'b000, 5'd4, 7'b1010011)); // fsub.d f4, f1, f2
            emit(enc_r(7'b1110001, 5'd0, 5'd4, 3'b000, 5'd5, 7'b1010011)); // fmv.x.d x5, f4
            emit(enc_s(12'sd8, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 8(x1)

            emit(enc_i(12'sd16, 5'd2, 3'b010, 5'd5, 7'b0000111));      // flw   f5, 16(x2)
            emit(enc_i(12'sd24, 5'd2, 3'b010, 5'd6, 7'b0000111));      // flw   f6, 24(x2)
            emit(enc_r(7'b0000000, 5'd6, 5'd5, 3'b000, 5'd7, 7'b1010011)); // fadd.s f7, f5, f6
            emit(enc_r(7'b1110000, 5'd0, 5'd7, 3'b000, 5'd8, 7'b1010011)); // fmv.x.w x8, f7
            emit(enc_s(12'sd16, 5'd8, 5'd1, 3'b011, 7'b0100011));      // sd    x8, 16(x1)

            emit(enc_r(7'b0000100, 5'd6, 5'd7, 3'b000, 5'd8, 7'b1010011)); // fsub.s f8, f7, f6
            emit(enc_r(7'b1110000, 5'd0, 5'd8, 3'b000, 5'd9, 7'b1010011)); // fmv.x.w x9, f8
            emit(enc_s(12'sd24, 5'd9, 5'd1, 3'b011, 7'b0100011));      // sd    x9, 24(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd32, 5'd2, 3'b011, 5'd9, 7'b0000111));      // fld   f9, +inf
            emit(enc_i(12'sd40, 5'd2, 3'b011, 5'd10, 7'b0000111));     // fld   f10, -inf
            emit(enc_r(7'b0000001, 5'd10, 5'd9, 3'b000, 5'd11, 7'b1010011)); // fadd.d inf + -inf
            emit(enc_r(7'b1110001, 5'd0, 5'd11, 3'b000, 5'd10, 7'b1010011)); // fmv.x.d x10, f11
            emit(enc_s(12'sd32, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 32(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd10));               // csrr  x10, fflags
            emit(enc_s(12'sd40, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 40(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1600, "ZX64 five-stage FPU add/sub test");

            expect64(32, 64'h4008_0000_0000_0000, "FADD.D exact normal");
            expect64(33, 64'hbff0_0000_0000_0000, "FSUB.D exact normal negative");
            expect64(34, 64'h0000_0000_4070_0000, "FADD.S exact normal");
            expect64(35, 64'h0000_0000_3fc0_0000, "FSUB.S exact normal");
            expect64(36, 64'h7ff8_0000_0000_0000, "FADD.D inf cancellation returns canonical NaN");
            expect64(37, 64'h0000_0000_0000_0010, "FADD.D inf cancellation sets NV");
        end
    endtask

    task automatic run_fpu_mul_test;
        begin
            clear_memories();

            dmem[8]  = 64'h4000_0000_0000_0000; // +2.0D
            dmem[9]  = 64'h4008_0000_0000_0000; // +3.0D
            dmem[10] = 64'h0000_0000_3fc0_0000; // +1.5S
            dmem[11] = 64'h0000_0000_4010_0000; // +2.25S
            dmem[12] = 64'h8000_0000_0000_0000; // -0.0D
            dmem[13] = 64'h7ff0_0000_0000_0000; // +infD

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd2, 7'b0000111));       // fld   f2, 8(x2)
            emit(enc_r(7'b0001001, 5'd2, 5'd1, 3'b000, 5'd3, 7'b1010011)); // fmul.d f3, f1, f2
            emit(enc_r(7'b1110001, 5'd0, 5'd3, 3'b000, 5'd5, 7'b1010011)); // fmv.x.d x5, f3
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)

            emit(enc_i(12'sd16, 5'd2, 3'b010, 5'd4, 7'b0000111));      // flw   f4, 16(x2)
            emit(enc_i(12'sd24, 5'd2, 3'b010, 5'd5, 7'b0000111));      // flw   f5, 24(x2)
            emit(enc_r(7'b0001000, 5'd5, 5'd4, 3'b000, 5'd6, 7'b1010011)); // fmul.s f6, f4, f5
            emit(enc_r(7'b1110000, 5'd0, 5'd6, 3'b000, 5'd7, 7'b1010011)); // fmv.x.w x7, f6
            emit(enc_s(12'sd8, 5'd7, 5'd1, 3'b011, 7'b0100011));       // sd    x7, 8(x1)

            emit(enc_i(12'sd32, 5'd2, 3'b011, 5'd7, 7'b0000111));      // fld   f7, -0.0D
            emit(enc_r(7'b0001001, 5'd1, 5'd7, 3'b000, 5'd8, 7'b1010011)); // fmul.d f8, -0.0, +2.0
            emit(enc_r(7'b1110001, 5'd0, 5'd8, 3'b000, 5'd8, 7'b1010011)); // fmv.x.d x8, f8
            emit(enc_s(12'sd16, 5'd8, 5'd1, 3'b011, 7'b0100011));      // sd    x8, 16(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd40, 5'd2, 3'b011, 5'd9, 7'b0000111));      // fld   f9, +infD
            emit(enc_r(7'b0001001, 5'd7, 5'd9, 3'b000, 5'd10, 7'b1010011)); // fmul.d +inf, -0
            emit(enc_r(7'b1110001, 5'd0, 5'd10, 3'b000, 5'd10, 7'b1010011)); // fmv.x.d x10, f10
            emit(enc_s(12'sd24, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 24(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd10));               // csrr  x10, fflags
            emit(enc_s(12'sd32, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 32(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1600, "ZX64 five-stage FPU multiply test");

            expect64(32, 64'h4018_0000_0000_0000, "FMUL.D exact normal");
            expect64(33, 64'h0000_0000_4058_0000, "FMUL.S exact normal");
            expect64(34, 64'h8000_0000_0000_0000, "FMUL.D signed zero");
            expect64(35, 64'h7ff8_0000_0000_0000, "FMUL.D inf times zero returns canonical NaN");
            expect64(36, 64'h0000_0000_0000_0010, "FMUL.D inf times zero sets NV");
        end
    endtask

    task automatic run_fpu_fp_to_fp_cvt_test;
        begin
            clear_memories();

            dmem[8]  = 64'h3ff8_0000_0000_0000; // +1.5D
            dmem[9]  = 64'h0000_0000_c010_0000; // -2.25S
            dmem[10] = 64'h3ff0_0000_1000_0000; // 1.0 + 2^-24, tie to even in S
            dmem[11] = 64'h7ff0_0000_0000_0001; // sNaN.D

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_r(7'b0100000, 5'd1, 5'd1, 3'b000, 5'd2, 7'b1010011)); // fcvt.s.d f2, f1
            emit(enc_r(7'b1110000, 5'd0, 5'd2, 3'b000, 5'd5, 7'b1010011)); // fmv.x.w x5, f2
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)

            emit(enc_i(12'sd8, 5'd2, 3'b010, 5'd3, 7'b0000111));       // flw   f3, 8(x2)
            emit(enc_r(7'b0100001, 5'd0, 5'd3, 3'b000, 5'd4, 7'b1010011)); // fcvt.d.s f4, f3
            emit(enc_r(7'b1110001, 5'd0, 5'd4, 3'b000, 5'd6, 7'b1010011)); // fmv.x.d x6, f4
            emit(enc_s(12'sd8, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 8(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd16, 5'd2, 3'b011, 5'd5, 7'b0000111));      // fld   f5, 16(x2)
            emit(enc_r(7'b0100000, 5'd1, 5'd5, 3'b000, 5'd6, 7'b1010011)); // fcvt.s.d f6, f5
            emit(enc_r(7'b1110000, 5'd0, 5'd6, 3'b000, 5'd7, 7'b1010011)); // fmv.x.w x7, f6
            emit(enc_s(12'sd16, 5'd7, 5'd1, 3'b011, 7'b0100011));      // sd    x7, 16(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd8));                // csrr  x8, fflags
            emit(enc_s(12'sd24, 5'd8, 5'd1, 3'b011, 7'b0100011));      // sd    x8, 24(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd24, 5'd2, 3'b011, 5'd7, 7'b0000111));      // fld   f7, sNaN.D
            emit(enc_r(7'b0100000, 5'd1, 5'd7, 3'b000, 5'd8, 7'b1010011)); // fcvt.s.d f8, f7
            emit(enc_r(7'b1110000, 5'd0, 5'd8, 3'b000, 5'd9, 7'b1010011)); // fmv.x.w x9, f8
            emit(enc_s(12'sd32, 5'd9, 5'd1, 3'b011, 7'b0100011));      // sd    x9, 32(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd10));               // csrr  x10, fflags
            emit(enc_s(12'sd40, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 40(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1600, "ZX64 five-stage FPU FP-to-FP conversion test");

            expect64(32, 64'h0000_0000_3fc0_0000, "FCVT.S.D exact normal");
            expect64(33, 64'hc002_0000_0000_0000, "FCVT.D.S exact normal");
            expect64(34, 64'h0000_0000_3f80_0000, "FCVT.S.D RNE tie to even");
            expect64(35, 64'h0000_0000_0000_0001, "FCVT.S.D inexact sets NX");
            expect64(36, 64'h0000_0000_7fc0_0000, "FCVT.S.D sNaN returns canonical NaN");
            expect64(37, 64'h0000_0000_0000_0010, "FCVT.S.D sNaN sets NV");
        end
    endtask

    task automatic run_fpu_divsqrt_test;
        begin
            clear_memories();

            dmem[8]  = 64'h4018_0000_0000_0000; // +6.0D
            dmem[9]  = 64'h4000_0000_0000_0000; // +2.0D
            dmem[10] = 64'h4022_0000_0000_0000; // +9.0D
            dmem[11] = 64'hc010_0000_0000_0000; // -4.0D
            dmem[12] = 64'h0000_0000_4110_0000; // +9.0S
            dmem[13] = 64'h0000_0000_4000_0000; // +2.0S
            dmem[14] = 64'h0000_0000_4010_0000; // +2.25S
            dmem[15] = 64'h0000_0000_0000_0000; // +0.0D

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd2, 7'b0000111));       // fld   f2, 8(x2)
            emit(enc_r(7'b0001101, 5'd2, 5'd1, 3'b000, 5'd3, 7'b1010011)); // fdiv.d f3, f1, f2
            emit(enc_r(7'b1110001, 5'd0, 5'd3, 3'b000, 5'd5, 7'b1010011)); // fmv.x.d x5, f3
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)

            emit(enc_i(12'sd32, 5'd2, 3'b010, 5'd4, 7'b0000111));      // flw   f4, 32(x2)
            emit(enc_i(12'sd40, 5'd2, 3'b010, 5'd5, 7'b0000111));      // flw   f5, 40(x2)
            emit(enc_r(7'b0001100, 5'd5, 5'd4, 3'b000, 5'd6, 7'b1010011)); // fdiv.s f6, f4, f5
            emit(enc_r(7'b1110000, 5'd0, 5'd6, 3'b000, 5'd7, 7'b1010011)); // fmv.x.w x7, f6
            emit(enc_s(12'sd8, 5'd7, 5'd1, 3'b011, 7'b0100011));       // sd    x7, 8(x1)

            emit(enc_i(12'sd16, 5'd2, 3'b011, 5'd8, 7'b0000111));      // fld   f8, 16(x2)
            emit(enc_r(7'b0101101, 5'd0, 5'd8, 3'b000, 5'd9, 7'b1010011)); // fsqrt.d f9, f8
            emit(enc_r(7'b1110001, 5'd0, 5'd9, 3'b000, 5'd10, 7'b1010011)); // fmv.x.d x10, f9
            emit(enc_s(12'sd16, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 16(x1)

            emit(enc_i(12'sd48, 5'd2, 3'b010, 5'd11, 7'b0000111));     // flw   f11, 48(x2)
            emit(enc_r(7'b0101100, 5'd0, 5'd11, 3'b000, 5'd12, 7'b1010011)); // fsqrt.s f12, f11
            emit(enc_r(7'b1110000, 5'd0, 5'd12, 3'b000, 5'd13, 7'b1010011)); // fmv.x.w x13, f12
            emit(enc_s(12'sd24, 5'd13, 5'd1, 3'b011, 7'b0100011));     // sd    x13, 24(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd56, 5'd2, 3'b011, 5'd14, 7'b0000111));     // fld   f14, 56(x2)
            emit(enc_r(7'b0001101, 5'd14, 5'd1, 3'b000, 5'd15, 7'b1010011)); // fdiv.d f15, f1, +0
            emit(enc_r(7'b1110001, 5'd0, 5'd15, 3'b000, 5'd16, 7'b1010011)); // fmv.x.d x16, f15
            emit(enc_s(12'sd32, 5'd16, 5'd1, 3'b011, 7'b0100011));     // sd    x16, 32(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd17));               // csrr  x17, fflags
            emit(enc_s(12'sd40, 5'd17, 5'd1, 3'b011, 7'b0100011));     // sd    x17, 40(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd24, 5'd2, 3'b011, 5'd18, 7'b0000111));     // fld   f18, -4.0D
            emit(enc_r(7'b0101101, 5'd0, 5'd18, 3'b000, 5'd19, 7'b1010011)); // fsqrt.d f19, -4.0
            emit(enc_r(7'b1110001, 5'd0, 5'd19, 3'b000, 5'd20, 7'b1010011)); // fmv.x.d x20, f19
            emit(enc_s(12'sd48, 5'd20, 5'd1, 3'b011, 7'b0100011));     // sd    x20, 48(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd21));               // csrr  x21, fflags
            emit(enc_s(12'sd56, 5'd21, 5'd1, 3'b011, 7'b0100011));     // sd    x21, 56(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(2200, "ZX64 five-stage FPU divide/sqrt test");

            expect64(32, 64'h4008_0000_0000_0000, "FDIV.D exact normal");
            expect64(33, 64'h0000_0000_4090_0000, "FDIV.S exact normal");
            expect64(34, 64'h4008_0000_0000_0000, "FSQRT.D exact normal");
            expect64(35, 64'h0000_0000_3fc0_0000, "FSQRT.S exact normal");
            expect64(36, 64'h7ff0_0000_0000_0000, "FDIV.D divide by zero returns infinity");
            expect64(37, 64'h0000_0000_0000_0008, "FDIV.D divide by zero sets DZ");
            expect64(38, 64'h7ff8_0000_0000_0000, "FSQRT.D negative normal returns canonical NaN");
            expect64(39, 64'h0000_0000_0000_0010, "FSQRT.D negative normal sets NV");
        end
    endtask

    task automatic run_fpu_fma_test;
        begin
            clear_memories();

            dmem[8]  = 64'h4000_0000_0000_0000; // +2.0D
            dmem[9]  = 64'h4008_0000_0000_0000; // +3.0D
            dmem[10] = 64'h4010_0000_0000_0000; // +4.0D
            dmem[11] = 64'h0000_0000_3fc0_0000; // +1.5S
            dmem[12] = 64'h0000_0000_4000_0000; // +2.0S
            dmem[13] = 64'h0000_0000_3f00_0000; // +0.5S
            dmem[14] = 64'h7ff0_0000_0000_0000; // +infD
            dmem[15] = 64'h0000_0000_0000_0000; // +0.0D

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd2, 7'b0000111));       // fld   f2, 8(x2)
            emit(enc_i(12'sd16, 5'd2, 3'b011, 5'd3, 7'b0000111));      // fld   f3, 16(x2)
            emit(enc_fp_r4(5'd3, 2'b01, 5'd2, 5'd1, 3'b000, 5'd4, 7'b1000011)); // fmadd.d
            emit(enc_r(7'b1110001, 5'd0, 5'd4, 3'b000, 5'd5, 7'b1010011)); // fmv.x.d x5, f4
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)
            emit(enc_fp_r4(5'd3, 2'b01, 5'd2, 5'd1, 3'b000, 5'd6, 7'b1000111)); // fmsub.d
            emit(enc_r(7'b1110001, 5'd0, 5'd6, 3'b000, 5'd7, 7'b1010011)); // fmv.x.d x7, f6
            emit(enc_s(12'sd8, 5'd7, 5'd1, 3'b011, 7'b0100011));       // sd    x7, 8(x1)
            emit(enc_fp_r4(5'd3, 2'b01, 5'd2, 5'd1, 3'b000, 5'd8, 7'b1001011)); // fnmsub.d
            emit(enc_r(7'b1110001, 5'd0, 5'd8, 3'b000, 5'd9, 7'b1010011)); // fmv.x.d x9, f8
            emit(enc_s(12'sd16, 5'd9, 5'd1, 3'b011, 7'b0100011));      // sd    x9, 16(x1)
            emit(enc_fp_r4(5'd3, 2'b01, 5'd2, 5'd1, 3'b000, 5'd10, 7'b1001111)); // fnmadd.d
            emit(enc_r(7'b1110001, 5'd0, 5'd10, 3'b000, 5'd11, 7'b1010011)); // fmv.x.d x11, f10
            emit(enc_s(12'sd24, 5'd11, 5'd1, 3'b011, 7'b0100011));     // sd    x11, 24(x1)

            emit(enc_i(12'sd24, 5'd2, 3'b010, 5'd12, 7'b0000111));     // flw   f12, 24(x2)
            emit(enc_i(12'sd32, 5'd2, 3'b010, 5'd13, 7'b0000111));     // flw   f13, 32(x2)
            emit(enc_i(12'sd40, 5'd2, 3'b010, 5'd14, 7'b0000111));     // flw   f14, 40(x2)
            emit(enc_fp_r4(5'd14, 2'b00, 5'd13, 5'd12, 3'b000, 5'd15, 7'b1000011)); // fmadd.s
            emit(enc_r(7'b1110000, 5'd0, 5'd15, 3'b000, 5'd16, 7'b1010011)); // fmv.x.w x16, f15
            emit(enc_s(12'sd32, 5'd16, 5'd1, 3'b011, 7'b0100011));     // sd    x16, 32(x1)
            emit(enc_fp_r4(5'd14, 2'b00, 5'd13, 5'd12, 3'b000, 5'd17, 7'b1000111)); // fmsub.s
            emit(enc_r(7'b1110000, 5'd0, 5'd17, 3'b000, 5'd18, 7'b1010011)); // fmv.x.w x18, f17
            emit(enc_s(12'sd40, 5'd18, 5'd1, 3'b011, 7'b0100011));     // sd    x18, 40(x1)
            emit(enc_fp_r4(5'd14, 2'b00, 5'd13, 5'd12, 3'b000, 5'd19, 7'b1001011)); // fnmsub.s
            emit(enc_r(7'b1110000, 5'd0, 5'd19, 3'b000, 5'd20, 7'b1010011)); // fmv.x.w x20, f19
            emit(enc_s(12'sd48, 5'd20, 5'd1, 3'b011, 7'b0100011));     // sd    x20, 48(x1)
            emit(enc_fp_r4(5'd14, 2'b00, 5'd13, 5'd12, 3'b000, 5'd21, 7'b1001111)); // fnmadd.s
            emit(enc_r(7'b1110000, 5'd0, 5'd21, 3'b000, 5'd22, 7'b1010011)); // fmv.x.w x22, f21
            emit(enc_s(12'sd56, 5'd22, 5'd1, 3'b011, 7'b0100011));     // sd    x22, 56(x1)

            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit(enc_i(12'sd48, 5'd2, 3'b011, 5'd23, 7'b0000111));     // fld   f23, +inf
            emit(enc_i(12'sd56, 5'd2, 3'b011, 5'd24, 7'b0000111));     // fld   f24, +0
            emit(enc_fp_r4(5'd3, 2'b01, 5'd24, 5'd23, 3'b000, 5'd25, 7'b1000011)); // fmadd.d inf*0+4
            emit(enc_r(7'b1110001, 5'd0, 5'd25, 3'b000, 5'd26, 7'b1010011)); // fmv.x.d x26, f25
            emit(enc_s(12'sd64, 5'd26, 5'd1, 3'b011, 7'b0100011));     // sd    x26, 64(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd27));               // csrr  x27, fflags
            emit(enc_s(12'sd72, 5'd27, 5'd1, 3'b011, 7'b0100011));     // sd    x27, 72(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(2600, "ZX64 five-stage FPU FMA test");

            expect64(32, 64'h4024_0000_0000_0000, "FMADD.D exact normal");
            expect64(33, 64'h4000_0000_0000_0000, "FMSUB.D exact normal");
            expect64(34, 64'hc000_0000_0000_0000, "FNMSUB.D exact normal");
            expect64(35, 64'hc024_0000_0000_0000, "FNMADD.D exact normal");
            expect64(36, 64'h0000_0000_4060_0000, "FMADD.S exact normal");
            expect64(37, 64'h0000_0000_4020_0000, "FMSUB.S exact normal");
            expect64(38, 64'hffff_ffff_c020_0000, "FNMSUB.S exact normal");
            expect64(39, 64'hffff_ffff_c060_0000, "FNMADD.S exact normal");
            expect64(40, 64'h7ff8_0000_0000_0000, "FMADD.D inf times zero returns canonical NaN");
            expect64(41, 64'h0000_0000_0000_0010, "FMADD.D inf times zero sets NV");
        end
    endtask

    task automatic run_fpu_class_compare_test;
        begin
            clear_memories();

            dmem[8]  = 64'h3ff0_0000_0000_0000; // +1.0D
            dmem[9]  = 64'hc000_0000_0000_0000; // -2.0D
            dmem[10] = 64'h7ff8_0000_0000_0001; // qNaN.D
            dmem[11] = 64'h7ff0_0000_0000_0001; // sNaN.D
            dmem[12] = 64'h0000_0000_8000_0000; // -0.0S

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit(enc_csr(12'h001, 5'd0, 3'b001, 5'd0));                // csrw  fflags, x0
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd2, 7'b0000111));       // fld   f2, 8(x2)
            emit(enc_i(12'sd16, 5'd2, 3'b011, 5'd3, 7'b0000111));      // fld   f3, 16(x2)
            emit(enc_i(12'sd24, 5'd2, 3'b011, 5'd4, 7'b0000111));      // fld   f4, 24(x2)
            emit(enc_i(12'sd32, 5'd2, 3'b010, 5'd5, 7'b0000111));      // flw   f5, 32(x2)

            emit(enc_r(7'b1110001, 5'd0, 5'd2, 3'b001, 5'd5, 7'b1010011)); // fclass.d x5, f2
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)
            emit(enc_r(7'b1010001, 5'd1, 5'd2, 3'b001, 5'd6, 7'b1010011)); // flt.d x6, f2, f1
            emit(enc_s(12'sd8, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 8(x1)
            emit(enc_r(7'b1010001, 5'd2, 5'd1, 3'b000, 5'd7, 7'b1010011)); // fle.d x7, f1, f2
            emit(enc_s(12'sd16, 5'd7, 5'd1, 3'b011, 7'b0100011));      // sd    x7, 16(x1)
            emit(enc_r(7'b1010001, 5'd1, 5'd1, 3'b010, 5'd8, 7'b1010011)); // feq.d x8, f1, f1
            emit(enc_s(12'sd24, 5'd8, 5'd1, 3'b011, 7'b0100011));      // sd    x8, 24(x1)

            emit(enc_r(7'b0010101, 5'd2, 5'd1, 3'b000, 5'd6, 7'b1010011)); // fmin.d f6, f1, f2
            emit(enc_r(7'b1110001, 5'd0, 5'd6, 3'b000, 5'd9, 7'b1010011)); // fmv.x.d x9, f6
            emit(enc_s(12'sd32, 5'd9, 5'd1, 3'b011, 7'b0100011));      // sd    x9, 32(x1)
            emit(enc_r(7'b0010101, 5'd2, 5'd1, 3'b001, 5'd7, 7'b1010011)); // fmax.d f7, f1, f2
            emit(enc_r(7'b1110001, 5'd0, 5'd7, 3'b000, 5'd10, 7'b1010011)); // fmv.x.d x10, f7
            emit(enc_s(12'sd40, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 40(x1)
            emit(enc_r(7'b1110000, 5'd0, 5'd5, 3'b001, 5'd11, 7'b1010011)); // fclass.s x11, f5
            emit(enc_s(12'sd48, 5'd11, 5'd1, 3'b011, 7'b0100011));     // sd    x11, 48(x1)

            emit(enc_r(7'b1010001, 5'd3, 5'd3, 3'b010, 5'd12, 7'b1010011)); // feq.d x12, qnan, qnan
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd13));               // csrr  x13, fflags
            emit(enc_s(12'sd56, 5'd13, 5'd1, 3'b011, 7'b0100011));     // sd    x13, 56(x1)

            emit(enc_r(7'b1010001, 5'd1, 5'd3, 3'b001, 5'd14, 7'b1010011)); // flt.d x14, qnan, f1
            emit(enc_s(12'sd64, 5'd14, 5'd1, 3'b011, 7'b0100011));     // sd    x14, 64(x1)
            emit(enc_r(7'b0010101, 5'd1, 5'd4, 3'b000, 5'd8, 7'b1010011)); // fmin.d f8, snan, f1
            emit(enc_r(7'b1110001, 5'd0, 5'd8, 3'b000, 5'd15, 7'b1010011)); // fmv.x.d x15, f8
            emit(enc_s(12'sd72, 5'd15, 5'd1, 3'b011, 7'b0100011));     // sd    x15, 72(x1)
            emit_nop();
            emit_nop();
            emit(enc_csr(12'h001, 5'd0, 3'b010, 5'd16));               // csrr  x16, fflags
            emit(enc_s(12'sd80, 5'd16, 5'd1, 3'b011, 7'b0100011));     // sd    x16, 80(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1200, "ZX64 five-stage FPU class/compare test");

            expect64(32, 64'h0000_0000_0000_0002, "FCLASS.D negative normal");
            expect64(33, 64'h0000_0000_0000_0001, "FLT.D ordered comparison");
            expect64(34, 64'h0000_0000_0000_0000, "FLE.D ordered comparison");
            expect64(35, 64'h0000_0000_0000_0001, "FEQ.D ordered comparison");
            expect64(36, 64'hc000_0000_0000_0000, "FMIN.D ordered result");
            expect64(37, 64'h3ff0_0000_0000_0000, "FMAX.D ordered result");
            expect64(38, 64'h0000_0000_0000_0008, "FCLASS.S negative zero");
            expect64(39, 64'h0000_0000_0000_0000, "FEQ.D quiet NaN leaves fflags clear");
            expect64(40, 64'h0000_0000_0000_0000, "FLT.D quiet NaN comparison result");
            expect64(41, 64'h3ff0_0000_0000_0000, "FMIN.D signaling NaN returns numeric operand");
            expect64(42, 64'h0000_0000_0000_0010, "NaN comparisons accrue invalid flag");
        end
    endtask

    task automatic run_fpu_fs_dirty_access_test;
        begin
            clear_memories();

            dmem[8]  = 64'h3ff0_0000_0000_0000; // +1.0D
            dmem[9]  = 64'h4000_0000_0000_0000; // +2.0D
            dmem[10] = 64'h0000_0000_4049_0fdb; // +3.141592S

            pcw = 0;
            emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
            emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 64
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 1
            emit(enc_i(12'sd13, 5'd4, 3'b001, 5'd4, 7'b0010011));      // slli  x4, x4, 13 (FS=Initial)
            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4
            emit_nop();

            emit(enc_i(12'sd0, 5'd2, 3'b011, 5'd1, 7'b0000111));       // fld   f1, 0(x2)
            emit(enc_i(12'sd8, 5'd2, 3'b011, 5'd2, 7'b0000111));       // fld   f2, 8(x2)
            emit(enc_i(12'sd16, 5'd2, 3'b010, 5'd3, 7'b0000111));      // flw   f3, 16(x2)
            emit_nop();

            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4 (FS=Initial)
            emit_nop();
            emit(enc_s(12'sd0, 5'd1, 5'd0, 3'b011, 7'b0100111));       // fsd   f1, 0(x0)
            emit_nop();
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd5));                // csrr  x5, mstatus
            emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 0(x1)

            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4 (FS=Initial)
            emit_nop();
            emit(enc_s(12'sd8, 5'd3, 5'd0, 3'b010, 7'b0100111));       // fsw   f3, 8(x0)
            emit_nop();
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd5));                // csrr  x5, mstatus
            emit(enc_s(12'sd8, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 8(x1)

            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4 (FS=Initial)
            emit_nop();
            emit(enc_r(7'b1110001, 5'd0, 5'd1, 3'b000, 5'd6, 7'b1010011)); // fmv.x.d x6, f1
            emit_nop();
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd5));                // csrr  x5, mstatus
            emit(enc_s(12'sd16, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 16(x1)

            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4 (FS=Initial)
            emit_nop();
            emit(enc_r(7'b1110001, 5'd0, 5'd1, 3'b001, 5'd7, 7'b1010011)); // fclass.d x7, f1
            emit_nop();
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd5));                // csrr  x5, mstatus
            emit(enc_s(12'sd24, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 24(x1)

            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4 (FS=Initial)
            emit_nop();
            emit(enc_r(7'b1010001, 5'd1, 5'd1, 3'b010, 5'd8, 7'b1010011)); // feq.d x8, f1, f1
            emit_nop();
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd5));                // csrr  x5, mstatus
            emit(enc_s(12'sd32, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 32(x1)

            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4 (FS=Initial)
            emit_nop();
            emit(enc_r(7'b1010001, 5'd2, 5'd1, 3'b001, 5'd9, 7'b1010011)); // flt.d x9, f1, f2
            emit_nop();
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd5));                // csrr  x5, mstatus
            emit(enc_s(12'sd40, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 40(x1)

            emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                // csrw  mstatus, x4 (FS=Initial)
            emit_nop();
            emit(enc_r(7'b1010001, 5'd2, 5'd1, 3'b000, 5'd10, 7'b1010011)); // fle.d x10, f1, f2
            emit_nop();
            emit(enc_csr(12'h300, 5'd0, 3'b010, 5'd5));                // csrr  x5, mstatus
            emit(enc_s(12'sd48, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 48(x1)
            emit(32'h0010_0073);                                       // ebreak

            pulse_soft_reset();
            wait_for_halt(1200, "ZX64 five-stage FPU FS dirty access test");

            expect64(32, 64'h8000_0000_0000_6000, "FSD marks FS dirty from Initial");
            expect64(33, 64'h8000_0000_0000_6000, "FSW marks FS dirty from Initial");
            expect64(34, 64'h8000_0000_0000_6000, "FMV.X.D marks FS dirty from Initial");
            expect64(35, 64'h8000_0000_0000_6000, "FCLASS.D marks FS dirty from Initial");
            expect64(36, 64'h8000_0000_0000_6000, "FEQ.D marks FS dirty from Initial");
            expect64(37, 64'h8000_0000_0000_6000, "FLT.D marks FS dirty from Initial");
            expect64(38, 64'h8000_0000_0000_6000, "FLE.D marks FS dirty from Initial");
        end
    endtask

    initial begin
        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b0;
        reset_vector = 64'd0;

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));      // addi  x1, x0, 256
        emit(enc_i(12'sd5, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 5
        emit(enc_i(12'sd7, 5'd2, 3'b000, 5'd3, 7'b0010011));        // addi  x3, x2, 7
        emit(enc_r(7'b0000000, 5'd2, 5'd3, 3'b000, 5'd4, 7'b0110011)); // add x4, x3, x2
        emit(enc_s(12'sd0, 5'd4, 5'd1, 3'b011, 7'b0100011));        // sd    x4, 0(x1)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd5, 7'b0000011));        // ld    x5, 0(x1)
        emit(enc_r(7'b0000000, 5'd2, 5'd5, 3'b000, 5'd6, 7'b0110011)); // add x6, x5, x2
        emit(enc_s(12'sd8, 5'd6, 5'd1, 3'b011, 7'b0100011));        // sd    x6, 8(x1)
        emit(enc_b(13'sd8, 5'd0, 5'd6, 3'b000, 7'b1100011));        // beq   x6, x0, +8
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd7, 7'b0010011));        // addi  x7, x0, 1
        emit(enc_b(13'sd8, 5'd7, 5'd7, 3'b000, 7'b1100011));        // beq   x7, x7, +8
        emit(enc_i(12'sd99, 5'd0, 3'b000, 5'd8, 7'b0010011));       // flushed
        emit(enc_j(21'sd8, 5'd9, 7'b1101111));                      // jal   x9, +8
        emit(enc_i(12'sd99, 5'd0, 3'b000, 5'd10, 7'b0010011));      // flushed
        emit(enc_s(12'sd16, 5'd9, 5'd1, 3'b011, 7'b0100011));       // sd    x9, 16(x1)
        emit(enc_u(20'h12345, 5'd12, 7'b0110111));                  // lui   x12, 0x12345
        emit(enc_s(12'sd24, 5'd12, 5'd1, 3'b011, 7'b0100011));      // sd    x12, 24(x1)
        emit(enc_i(-12'sd1, 5'd0, 3'b000, 5'd13, 7'b0011011));      // addiw x13, x0, -1
        emit(enc_s(12'sd32, 5'd13, 5'd1, 3'b011, 7'b0100011));      // sd    x13, 32(x1)
        emit(enc_i(12'sd1, 5'd13, 3'b001, 5'd14, 7'b0011011));      // slliw x14, x13, 1
        emit(enc_s(12'sd40, 5'd14, 5'd1, 3'b011, 7'b0100011));      // sd    x14, 40(x1)
        emit(enc_i(12'sd1, 5'd14, 3'b101, 5'd15, 7'b0011011));      // srliw x15, x14, 1
        emit(enc_s(12'sd48, 5'd15, 5'd1, 3'b011, 7'b0100011));      // sd    x15, 48(x1)
        emit(enc_i(12'sh401, 5'd14, 3'b101, 5'd16, 7'b0011011));    // sraiw x16, x14, 1
        emit(enc_s(12'sd56, 5'd16, 5'd1, 3'b011, 7'b0100011));      // sd    x16, 56(x1)
        emit(enc_r(7'b0000000, 5'd13, 5'd13, 3'b000, 5'd17, 7'b0111011)); // addw x17, x13, x13
        emit(enc_s(12'sd64, 5'd17, 5'd1, 3'b011, 7'b0100011));      // sd    x17, 64(x1)
        emit(enc_r(7'b0100000, 5'd13, 5'd0, 3'b000, 5'd18, 7'b0111011)); // subw x18, x0, x13
        emit(enc_s(12'sd72, 5'd18, 5'd1, 3'b011, 7'b0100011));      // sd    x18, 72(x1)
        emit(enc_r(7'b0000000, 5'd2, 5'd18, 3'b001, 5'd19, 7'b0111011)); // sllw x19, x18, x2
        emit(enc_s(12'sd80, 5'd19, 5'd1, 3'b011, 7'b0100011));      // sd    x19, 80(x1)
        emit(enc_r(7'b0000000, 5'd2, 5'd13, 3'b101, 5'd20, 7'b0111011)); // srlw x20, x13, x2
        emit(enc_s(12'sd88, 5'd20, 5'd1, 3'b011, 7'b0100011));      // sd    x20, 88(x1)
        emit(enc_r(7'b0100000, 5'd2, 5'd13, 3'b101, 5'd21, 7'b0111011)); // sraw x21, x13, x2
        emit(enc_s(12'sd96, 5'd21, 5'd1, 3'b011, 7'b0100011));      // sd    x21, 96(x1)
        emit(enc_i(12'sd6, 5'd0, 3'b000, 5'd22, 7'b0010011));       // addi  x22, x0, 6
        emit(enc_i(12'sd7, 5'd0, 3'b000, 5'd23, 7'b0010011));       // addi  x23, x0, 7
        emit(enc_r(7'b0000001, 5'd23, 5'd22, 3'b000, 5'd24, 7'b0110011)); // mul x24, x22, x23
        emit(enc_s(12'sd104, 5'd24, 5'd1, 3'b011, 7'b0100011));     // sd    x24, 104(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd13, 3'b001, 5'd25, 7'b0110011)); // mulh x25, x13, x22
        emit(enc_s(12'sd112, 5'd25, 5'd1, 3'b011, 7'b0100011));     // sd    x25, 112(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd13, 3'b010, 5'd25, 7'b0110011)); // mulhsu x25, x13, x22
        emit(enc_s(12'sd120, 5'd25, 5'd1, 3'b011, 7'b0100011));     // sd    x25, 120(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd13, 3'b011, 5'd25, 7'b0110011)); // mulhu x25, x13, x22
        emit(enc_s(12'sd128, 5'd25, 5'd1, 3'b011, 7'b0100011));     // sd    x25, 128(x1)
        emit(enc_i(-12'sd42, 5'd0, 3'b000, 5'd26, 7'b0010011));     // addi  x26, x0, -42
        emit(enc_i(12'sd43, 5'd0, 3'b000, 5'd27, 7'b0010011));      // addi  x27, x0, 43
        emit(enc_r(7'b0000001, 5'd22, 5'd26, 3'b100, 5'd28, 7'b0110011)); // div x28, x26, x22
        emit(enc_s(12'sd136, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 136(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd26, 3'b110, 5'd28, 7'b0110011)); // rem x28, x26, x22
        emit(enc_s(12'sd144, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 144(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd27, 3'b101, 5'd28, 7'b0110011)); // divu x28, x27, x22
        emit(enc_s(12'sd152, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 152(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd27, 3'b111, 5'd28, 7'b0110011)); // remu x28, x27, x22
        emit(enc_s(12'sd160, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 160(x1)
        emit(enc_r(7'b0000001, 5'd0, 5'd22, 3'b100, 5'd28, 7'b0110011)); // div x28, x22, x0
        emit(enc_s(12'sd168, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 168(x1)
        emit(enc_r(7'b0000001, 5'd0, 5'd22, 3'b110, 5'd28, 7'b0110011)); // rem x28, x22, x0
        emit(enc_s(12'sd176, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 176(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd13, 3'b000, 5'd28, 7'b0111011)); // mulw x28, x13, x22
        emit(enc_s(12'sd184, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 184(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd26, 3'b100, 5'd28, 7'b0111011)); // divw x28, x26, x22
        emit(enc_s(12'sd192, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 192(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd13, 3'b101, 5'd28, 7'b0111011)); // divuw x28, x13, x22
        emit(enc_s(12'sd200, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 200(x1)
        emit(enc_r(7'b0000001, 5'd22, 5'd13, 3'b111, 5'd28, 7'b0111011)); // remuw x28, x13, x22
        emit(enc_s(12'sd208, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 208(x1)
        emit(enc_u(20'h80000, 5'd30, 7'b0110111));                  // lui   x30, 0x80000
        emit(enc_r(7'b0000001, 5'd13, 5'd30, 3'b100, 5'd28, 7'b0111011)); // divw x28, x30, x13
        emit(enc_s(12'sd216, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 216(x1)
        emit(enc_r(7'b0000001, 5'd13, 5'd30, 3'b110, 5'd28, 7'b0111011)); // remw x28, x30, x13
        emit(enc_s(12'sd224, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 224(x1)
        emit(enc_i(12'sd512, 5'd1, 3'b000, 5'd29, 7'b0010011));     // addi  x29, x1, 512
        emit(enc_i(12'sd5, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 5
        emit(enc_s(12'sd0, 5'd2, 5'd29, 3'b011, 7'b0100011));       // sd    x2, 0(x29)
        emit(enc_amo(5'b00010, 5'd0, 5'd29, 3'b011, 5'd3));         // lr.d  x3, (x29)
        emit(enc_i(12'sd9, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 9
        emit(enc_amo(5'b00011, 5'd2, 5'd29, 3'b011, 5'd4));         // sc.d  x4, x2, (x29)
        emit(enc_amo(5'b00011, 5'd2, 5'd29, 3'b011, 5'd5));         // sc.d  x5, x2, (x29)
        emit(enc_i(12'sd3, 5'd0, 3'b000, 5'd6, 7'b0010011));        // addi  x6, x0, 3
        emit(enc_amo(5'b00000, 5'd6, 5'd29, 3'b011, 5'd7));         // amoadd.d x7, x6, (x29)
        emit(enc_amo(5'b00001, 5'd6, 5'd29, 3'b011, 5'd8));         // amoswap.d x8, x6, (x29)
        emit(enc_i(-12'sd4, 5'd0, 3'b000, 5'd9, 7'b0010011));       // addi  x9, x0, -4
        emit(enc_s(12'sd8, 5'd9, 5'd29, 3'b010, 7'b0100011));       // sw    x9, 8(x29)
        emit(enc_amo(5'b00010, 5'd0, 5'd29, 3'b010, 5'd10));        // lr.w  x10, (x29)
        emit(enc_i(12'sd8, 5'd29, 3'b000, 5'd11, 7'b0010011));      // addi  x11, x29, 8
        emit(enc_amo(5'b00010, 5'd0, 5'd11, 3'b010, 5'd12));        // lr.w  x12, (x11)
        emit(enc_i(12'sd7, 5'd0, 3'b000, 5'd13, 7'b0010011));       // addi  x13, x0, 7
        emit(enc_amo(5'b00011, 5'd13, 5'd11, 3'b010, 5'd14));       // sc.w  x14, x13, (x11)
        emit(enc_amo(5'b00000, 5'd13, 5'd11, 3'b010, 5'd15));       // amoadd.w x15, x13, (x11)
        emit(enc_i(12'sd0, 5'd29, 3'b011, 5'd16, 7'b0000011));      // ld    x16, 0(x29)
        emit(enc_i(12'sd8, 5'd29, 3'b011, 5'd17, 7'b0000011));      // ld    x17, 8(x29)
        emit(enc_i(12'sd16, 5'd29, 3'b000, 5'd18, 7'b0010011));     // addi  x18, x29, 16
        emit(enc_i(12'sd10, 5'd0, 3'b000, 5'd19, 7'b0010011));      // addi  x19, x0, 10
        emit(enc_s(12'sd0, 5'd19, 5'd18, 3'b011, 7'b0100011));      // sd    x19, 0(x18)
        emit(enc_i(12'sd6, 5'd0, 3'b000, 5'd19, 7'b0010011));       // addi  x19, x0, 6
        emit(enc_amo(5'b01000, 5'd19, 5'd18, 3'b011, 5'd20));       // amoor.d x20, x19, (x18)
        emit(enc_amo(5'b01100, 5'd19, 5'd18, 3'b011, 5'd21));       // amoand.d x21, x19, (x18)
        emit(enc_amo(5'b00100, 5'd19, 5'd18, 3'b011, 5'd22));       // amoxor.d x22, x19, (x18)
        emit(enc_i(12'sd0, 5'd18, 3'b011, 5'd23, 7'b0000011));      // ld    x23, 0(x18)
        emit(enc_i(12'sd24, 5'd29, 3'b000, 5'd18, 7'b0010011));     // addi  x18, x29, 24
        emit(enc_i(-12'sd3, 5'd0, 3'b000, 5'd19, 7'b0010011));      // addi  x19, x0, -3
        emit(enc_s(12'sd0, 5'd19, 5'd18, 3'b011, 7'b0100011));      // sd    x19, 0(x18)
        emit(enc_i(12'sd2, 5'd0, 3'b000, 5'd24, 7'b0010011));       // addi  x24, x0, 2
        emit(enc_amo(5'b10000, 5'd24, 5'd18, 3'b011, 5'd25));       // amomin.d x25, x24, (x18)
        emit(enc_amo(5'b10100, 5'd24, 5'd18, 3'b011, 5'd26));       // amomax.d x26, x24, (x18)
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd24, 7'b0010011));       // addi  x24, x0, 1
        emit(enc_amo(5'b11000, 5'd24, 5'd18, 3'b011, 5'd27));       // amominu.d x27, x24, (x18)
        emit(enc_i(12'sd5, 5'd0, 3'b000, 5'd24, 7'b0010011));       // addi  x24, x0, 5
        emit(enc_amo(5'b11100, 5'd24, 5'd18, 3'b011, 5'd28));       // amomaxu.d x28, x24, (x18)
        emit(enc_i(12'sd0, 5'd18, 3'b011, 5'd30, 7'b0000011));      // ld    x30, 0(x18)
        emit(enc_s(12'sd304, 5'd3, 5'd1, 3'b011, 7'b0100011));      // sd    x3, 304(x1)
        emit(enc_s(12'sd312, 5'd4, 5'd1, 3'b011, 7'b0100011));      // sd    x4, 312(x1)
        emit(enc_s(12'sd320, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 320(x1)
        emit(enc_s(12'sd328, 5'd7, 5'd1, 3'b011, 7'b0100011));      // sd    x7, 328(x1)
        emit(enc_s(12'sd336, 5'd8, 5'd1, 3'b011, 7'b0100011));      // sd    x8, 336(x1)
        emit(enc_s(12'sd344, 5'd16, 5'd1, 3'b011, 7'b0100011));     // sd    x16, 344(x1)
        emit(enc_s(12'sd352, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 352(x1)
        emit(enc_s(12'sd360, 5'd12, 5'd1, 3'b011, 7'b0100011));     // sd    x12, 360(x1)
        emit(enc_s(12'sd368, 5'd14, 5'd1, 3'b011, 7'b0100011));     // sd    x14, 368(x1)
        emit(enc_s(12'sd376, 5'd15, 5'd1, 3'b011, 7'b0100011));     // sd    x15, 376(x1)
        emit(enc_s(12'sd384, 5'd17, 5'd1, 3'b011, 7'b0100011));     // sd    x17, 384(x1)
        emit(enc_s(12'sd392, 5'd20, 5'd1, 3'b011, 7'b0100011));     // sd    x20, 392(x1)
        emit(enc_s(12'sd400, 5'd21, 5'd1, 3'b011, 7'b0100011));     // sd    x21, 400(x1)
        emit(enc_s(12'sd408, 5'd22, 5'd1, 3'b011, 7'b0100011));     // sd    x22, 408(x1)
        emit(enc_s(12'sd416, 5'd23, 5'd1, 3'b011, 7'b0100011));     // sd    x23, 416(x1)
        emit(enc_s(12'sd424, 5'd25, 5'd1, 3'b011, 7'b0100011));     // sd    x25, 424(x1)
        emit(enc_s(12'sd432, 5'd26, 5'd1, 3'b011, 7'b0100011));     // sd    x26, 432(x1)
        emit(enc_s(12'sd440, 5'd27, 5'd1, 3'b011, 7'b0100011));     // sd    x27, 440(x1)
        emit(enc_s(12'sd448, 5'd28, 5'd1, 3'b011, 7'b0100011));     // sd    x28, 448(x1)
        emit(enc_s(12'sd456, 5'd30, 5'd1, 3'b011, 7'b0100011));     // sd    x30, 456(x1)
        emit(enc_i(12'sd1536, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 1536
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                 // csrw  mtvec, x2
        emit(enc_csr(12'h301, 5'd0, 3'b010, 5'd3));                 // csrr  x3, misa
        emit(enc_s(12'sd232, 5'd3, 5'd1, 3'b011, 7'b0100011));      // sd    x3, 232(x1)
        ecall_pcw = pcw;
        emit(32'h0000_0073);                                        // ecall
        emit(enc_i(12'sh055, 5'd0, 3'b000, 5'd4, 7'b0010011));      // addi  x4, x0, 0x55
        emit(enc_s(12'sd256, 5'd4, 5'd1, 3'b011, 7'b0100011));      // sd    x4, 256(x1)
        emit(enc_i(12'sd1792, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 1792
        emit(enc_csr(12'h105, 5'd2, 3'b001, 5'd0));                 // csrw  stvec, x2
        emit(enc_i(12'sd512, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 1 << 9
        emit(enc_csr(12'h302, 5'd2, 3'b001, 5'd0));                 // csrw  medeleg, x2
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                   // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));    // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                 // csrw  mstatus, x3 (MPP=S)
        emit(enc_i(12'sd1024, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 1024
        emit(enc_csr(12'h341, 5'd2, 3'b001, 5'd0));                 // csrw  mepc, x2
        emit(32'h3020_0073);                                        // mret to S-mode
        emit(32'h0010_0073);                                        // ebreak
        pcw = 256;
        emit(enc_i(12'sd77, 5'd0, 3'b000, 5'd7, 7'b0010011));       // addi  x7, x0, 77
        s_ecall_pcw = pcw;
        emit(32'h0000_0073);                                        // ecall from S, delegated to S
        emit(enc_i(12'sd99, 5'd0, 3'b000, 5'd8, 7'b0010011));       // addi  x8, x0, 99
        emit(enc_s(12'sd288, 5'd8, 5'd1, 3'b011, 7'b0100011));      // sd    x8, 288(x1)
        emit(enc_csr(12'h100, 5'd0, 3'b010, 5'd9));                 // csrr  x9, sstatus
        emit(enc_s(12'sd296, 5'd9, 5'd1, 3'b011, 7'b0100011));      // sd    x9, 296(x1)
        emit(32'h0010_0073);                                        // ebreak
        pcw = 384;
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd5));                 // csrr  x5, mepc
        emit(enc_s(12'sd240, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 240(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd6));                 // csrr  x6, mcause
        emit(enc_s(12'sd248, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 248(x1)
        emit(enc_i(12'sd4, 5'd5, 3'b000, 5'd5, 7'b0010011));        // addi  x5, x5, 4
        emit(enc_csr(12'h341, 5'd5, 3'b001, 5'd0));                 // csrw  mepc, x5
        emit(32'h3020_0073);                                        // mret
        pcw = 448;
        emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd10));                // csrr  x10, sepc
        emit(enc_s(12'sd264, 5'd10, 5'd1, 3'b011, 7'b0100011));     // sd    x10, 264(x1)
        emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd11));                // csrr  x11, scause
        emit(enc_s(12'sd272, 5'd11, 5'd1, 3'b011, 7'b0100011));     // sd    x11, 272(x1)
        emit(enc_csr(12'h100, 5'd0, 3'b010, 5'd12));                // csrr  x12, sstatus
        emit(enc_s(12'sd280, 5'd12, 5'd1, 3'b011, 7'b0100011));     // sd    x12, 280(x1)
        emit(enc_i(12'sd4, 5'd10, 3'b000, 5'd10, 7'b0010011));      // addi  x10, x10, 4
        emit(enc_csr(12'h141, 5'd10, 3'b001, 5'd0));                // csrw  sepc, x10
        emit(32'h1020_0073);                                        // sret

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 2200 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage core did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32, 64'd17, "forwarded store");
        expect64(33, 64'd22, "load-use stall");
        expect64(34, 64'd52, "jal link and flush");
        expect64(35, 64'h0000_0000_1234_5000, "lui");
        expect64(36, 64'hffff_ffff_ffff_ffff, "addiw sign extend");
        expect64(37, 64'hffff_ffff_ffff_fffe, "slliw sign extend");
        expect64(38, 64'h0000_0000_7fff_ffff, "srliw zero high result");
        expect64(39, 64'hffff_ffff_ffff_ffff, "sraiw sign extend");
        expect64(40, 64'hffff_ffff_ffff_fffe, "addw sign extend");
        expect64(41, 64'h0000_0000_0000_0001, "subw sign extend");
        expect64(42, 64'h0000_0000_0000_0020, "sllw");
        expect64(43, 64'h0000_0000_07ff_ffff, "srlw");
        expect64(44, 64'hffff_ffff_ffff_ffff, "sraw");
        expect64(45, 64'h0000_0000_0000_002a, "mul");
        expect64(46, 64'hffff_ffff_ffff_ffff, "mulh");
        expect64(47, 64'hffff_ffff_ffff_ffff, "mulhsu");
        expect64(48, 64'h0000_0000_0000_0005, "mulhu");
        expect64(49, 64'hffff_ffff_ffff_fff9, "div");
        expect64(50, 64'h0000_0000_0000_0000, "rem");
        expect64(51, 64'h0000_0000_0000_0007, "divu");
        expect64(52, 64'h0000_0000_0000_0001, "remu");
        expect64(53, 64'hffff_ffff_ffff_ffff, "div by zero");
        expect64(54, 64'h0000_0000_0000_0006, "rem by zero");
        expect64(55, 64'hffff_ffff_ffff_fffa, "mulw");
        expect64(56, 64'hffff_ffff_ffff_fff9, "divw");
        expect64(57, 64'h0000_0000_2aaa_aaaa, "divuw");
        expect64(58, 64'h0000_0000_0000_0003, "remuw");
        expect64(59, 64'hffff_ffff_8000_0000, "divw overflow");
        expect64(60, 64'h0000_0000_0000_0000, "remw overflow");
        expect64(61, 64'h8000_0000_0004_112d, "misa");
        expect64(62, 64'(ecall_pcw * 4), "ecall mepc");
        expect64(63, 64'h0000_0000_0000_000b, "ecall mcause");
        expect64(64, 64'h0000_0000_0000_0055, "mret return");
        expect64(65, 64'(s_ecall_pcw * 4), "S ecall sepc");
        expect64(66, 64'h0000_0000_0000_0009, "S ecall scause");
        expect64(67, 64'h0000_0000_0000_0100, "S trap sstatus");
        expect64(68, 64'h0000_0000_0000_0063, "S sret return");
        expect64(69, 64'h0000_0000_0000_0020, "S post-sret sstatus");
        expect64(70, 64'h0000_0000_0000_0005, "lr.d old");
        expect64(71, 64'h0000_0000_0000_0000, "sc.d success");
        expect64(72, 64'h0000_0000_0000_0001, "sc.d failure");
        expect64(73, 64'h0000_0000_0000_0009, "amoadd.d old");
        expect64(74, 64'h0000_0000_0000_000c, "amoswap.d old");
        expect64(75, 64'h0000_0000_0000_0003, "AMO final dword");
        expect64(76, 64'h0000_0000_0000_0003, "lr.w low old");
        expect64(77, 64'hffff_ffff_ffff_fffc, "lr.w high old");
        expect64(78, 64'h0000_0000_0000_0000, "sc.w success");
        expect64(79, 64'h0000_0000_0000_0007, "amoadd.w old");
        expect64(80, 64'h0000_0000_0000_000e, "AMO final word");
        expect64(81, 64'h0000_0000_0000_000a, "amoor.d old");
        expect64(82, 64'h0000_0000_0000_000e, "amoand.d old");
        expect64(83, 64'h0000_0000_0000_0006, "amoxor.d old");
        expect64(84, 64'h0000_0000_0000_0000, "AMO bitwise final");
        expect64(85, 64'hffff_ffff_ffff_fffd, "amomin.d old");
        expect64(86, 64'hffff_ffff_ffff_fffd, "amomax.d old");
        expect64(87, 64'h0000_0000_0000_0002, "amominu.d old");
        expect64(88, 64'h0000_0000_0000_0001, "amomaxu.d old");
        expect64(89, 64'h0000_0000_0000_0005, "AMO minmax final");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));      // addi  x1, x0, 256
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 128
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                 // csrw  mtvec, x2
        emit(32'h1200_0073);                                        // sfence.vma x0, x0
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd3, 7'b0010011));      // addi  x3, x0, MTIE
        emit(enc_csr(12'h304, 5'd3, 3'b001, 5'd0));                 // csrw  mie, x3
        emit(enc_i(12'sd8, 5'd0, 3'b000, 5'd3, 7'b0010011));        // addi  x3, x0, MIE
        emit(enc_csr(12'h300, 5'd3, 3'b010, 5'd0));                 // csrs  mstatus, x3
        emit(32'h1050_0073);                                        // wfi
        emit(enc_i(12'sh044, 5'd0, 3'b000, 5'd4, 7'b0010011));      // addi  x4, x0, 0x44
        emit(enc_s(12'sd0, 5'd4, 5'd1, 3'b011, 7'b0100011));        // sd    x4, 0(x1)
        emit(32'h0010_0073);                                        // ebreak
        pcw = 32;
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd5));                 // csrr  x5, mepc
        emit(enc_s(12'sd8, 5'd5, 5'd1, 3'b011, 7'b0100011));        // sd    x5, 8(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd6));                 // csrr  x6, mcause
        emit(enc_s(12'sd16, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 16(x1)
        emit(32'h3020_0073);                                        // mret

        irq_timer = 1'b0;
        irq_external = 1'b0;
        seen_wfi = 1'b0;
        irq_delay = 0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 500 && !halted; cycle++) begin
            @(posedge clk);
            if (dbg_pc == 64'd36 || dbg_instr == 32'h1050_0073) begin
                seen_wfi = 1'b1;
            end
            if (seen_wfi && !irq_timer) begin
                irq_delay = irq_delay + 1;
                if (irq_delay == 4) begin
                    irq_timer = 1'b1;
                end
            end
            if (dbg_pc == 64'd128) begin
                irq_timer = 1'b0;
            end
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage WFI/IRQ test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32, 64'h0000_0000_0000_0044, "WFI IRQ return marker");
        expect64(33, 64'h0000_0000_0000_0024, "WFI timer mepc");
        expect64(34, 64'h8000_0000_0000_0007, "WFI timer mcause");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        dmem[0] = 64'h0000_0000_0000_00cf;                           // 1GiB identity RWXAD leaf
        pcw = 0;
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));          // addi  x2, x0, 1
        emit(enc_i(12'sh03f, 5'd2, 3'b001, 5'd2, 7'b0010011));        // slli  x2, x2, 63
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                   // csrw  satp, x2
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                     // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));      // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                   // csrw  mstatus, x3 (MPP=S)
        emit(enc_u(20'h00001, 5'd4, 7'b0110111));                     // lui   x4, 0x1
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                   // csrw  mepc, x4
        emit(32'h3020_0073);                                          // mret to S-mode under Sv39
        pcw = 1024;
        emit(enc_u(20'h00004, 5'd1, 7'b0110111));                     // lui   x1, 0x4
        emit(enc_i(12'sh05a, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 0x5a
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));          // sd    x2, 0(x1)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd3, 7'b0000011));          // ld    x3, 0(x1)
        emit(enc_s(12'sd8, 5'd3, 5'd1, 3'b011, 7'b0100011));          // sd    x3, 8(x1)
        emit(32'h1200_0073);                                          // sfence.vma x0, x0
        emit(32'h0010_0073);                                          // ebreak

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 800 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage Sv39 test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(2048, 64'h0000_0000_0000_005a, "Sv39 translated store");
        expect64(2049, 64'h0000_0000_0000_005a, "Sv39 translated load");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        dmem[0] = 64'h0000_0000_0000_0401;                            // root[0] -> PA 0x1000
        dmem[512] = 64'h0000_0000_0000_0801;                          // l1[0] -> PA 0x2000
        dmem[1025] = 64'h0000_0000_0000_0ccf;                         // va 0x1000 -> pa 0x3000
        pcw = 0;
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));          // addi  x2, x0, 1
        emit(enc_i(12'sh03f, 5'd2, 3'b001, 5'd2, 7'b0010011));        // slli  x2, x2, 63
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                   // csrw  satp, x2
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                     // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));      // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                   // csrw  mstatus, x3 (MPP=S)
        emit(enc_u(20'h00001, 5'd4, 7'b0110111));                     // lui   x4, 0x1
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                   // csrw  mepc, x4
        emit(32'h3020_0073);                                          // mret to VA 0x1000
        pcw = 3072;
        emit(enc_u(20'h00001, 5'd1, 7'b0110111));                     // lui   x1, 0x1
        emit(enc_i(12'sd128, 5'd1, 3'b000, 5'd1, 7'b0010011));        // addi  x1, x1, 128
        emit(enc_i(12'sh06b, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 0x6b
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));          // sd    x2, 0(x1)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd3, 7'b0000011));          // ld    x3, 0(x1)
        emit(enc_s(12'sd8, 5'd3, 5'd1, 3'b011, 7'b0100011));          // sd    x3, 8(x1)
        emit(32'h0010_0073);                                          // ebreak

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 1000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage Sv39 non-identity test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(1552, 64'h0000_0000_0000_006b, "Sv39 non-identity store");
        expect64(1553, 64'h0000_0000_0000_006b, "Sv39 non-identity load");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        dmem[0] = 64'h0000_0000_0000_00cf;                            // 1GiB identity RWXAD leaf
        pcw = 0;
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 128
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                   // csrw  mtvec, x2
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));          // addi  x2, x0, 1
        emit(enc_i(12'sh03f, 5'd2, 3'b001, 5'd2, 7'b0010011));        // slli  x2, x2, 63
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                   // csrw  satp, x2
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                     // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));      // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                   // csrw  mstatus, x3 (MPP=S)
        emit(enc_u(20'h00001, 5'd4, 7'b0110111));                     // lui   x4, 0x1
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                   // csrw  mepc, x4
        emit(32'h3020_0073);                                          // mret to S-mode
        pcw = 32;
        emit(enc_u(20'h00005, 5'd1, 7'b0110111));                     // lui   x1, 0x5
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd2));                   // csrr  x2, mepc
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));          // sd    x2, 0(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd3));                   // csrr  x3, mcause
        emit(enc_s(12'sd8, 5'd3, 5'd1, 3'b011, 7'b0100011));          // sd    x3, 8(x1)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd4));                   // csrr  x4, mtval
        emit(enc_s(12'sd16, 5'd4, 5'd1, 3'b011, 7'b0100011));         // sd    x4, 16(x1)
        emit(32'h0010_0073);                                          // ebreak
        pcw = 1024;
        emit(enc_u(20'h40000, 5'd1, 7'b0110111));                     // lui   x1, 0x40000
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd2, 7'b0000011));          // ld    x2, 0(x1)
        emit(32'h0010_0073);                                          // should not execute

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 1000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage Sv39 page fault test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(2560, 64'h0000_0000_0000_1004, "Sv39 load page fault mepc");
        expect64(2561, 64'h0000_0000_0000_000d, "Sv39 load page fault mcause");
        expect64(2562, 64'h0000_0000_4000_0000, "Sv39 load page fault mtval");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        dmem[0] = 64'h0000_0000_0000_00cf;                            // 1GiB identity RWXAD leaf
        pcw = 0;
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));          // addi  x2, x0, 1
        emit(enc_i(12'sh03f, 5'd2, 3'b001, 5'd2, 7'b0010011));        // slli  x2, x2, 63
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                   // csrw  satp, x2
        emit(enc_u(20'h00002, 5'd3, 7'b0110111));                     // lui   x3, 0x2
        emit(enc_csr(12'h105, 5'd3, 3'b001, 5'd0));                   // csrw  stvec, x3
        emit(enc_csr(12'h302, 5'd3, 3'b001, 5'd0));                   // csrw  medeleg, x3
        emit(enc_u(20'h00001, 5'd4, 7'b0110111));                     // lui   x4, 0x1
        emit(enc_i(-12'sd2048, 5'd4, 3'b000, 5'd4, 7'b0010011));      // addi  x4, x4, -2048
        emit(enc_csr(12'h300, 5'd4, 3'b001, 5'd0));                   // csrw  mstatus, x4 (MPP=S)
        emit(enc_u(20'h00001, 5'd5, 7'b0110111));                     // lui   x5, 0x1
        emit(enc_csr(12'h341, 5'd5, 3'b001, 5'd0));                   // csrw  mepc, x5
        emit(32'h3020_0073);                                          // mret to S-mode
        pcw = 1024;
        emit(enc_u(20'h40000, 5'd1, 7'b0110111));                     // lui   x1, 0x40000
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd2, 7'b0000011));          // ld    x2, 0(x1)
        emit(32'h0010_0073);                                          // should not execute
        pcw = 2048;
        emit(enc_u(20'h00005, 5'd1, 7'b0110111));                     // lui   x1, 0x5
        emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd2));                   // csrr  x2, sepc
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));          // sd    x2, 0(x1)
        emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd3));                   // csrr  x3, scause
        emit(enc_s(12'sd8, 5'd3, 5'd1, 3'b011, 7'b0100011));          // sd    x3, 8(x1)
        emit(enc_csr(12'h143, 5'd0, 3'b010, 5'd4));                   // csrr  x4, stval
        emit(enc_s(12'sd16, 5'd4, 5'd1, 3'b011, 7'b0100011));         // sd    x4, 16(x1)
        emit(32'h0010_0073);                                          // ebreak

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 1000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage Sv39 delegated page fault test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(2560, 64'h0000_0000_0000_1004, "Sv39 delegated load page fault sepc");
        expect64(2561, 64'h0000_0000_0000_000d, "Sv39 delegated load page fault scause");
        expect64(2562, 64'h0000_0000_4000_0000, "Sv39 delegated load page fault stval");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        dmem[32'h4000 >> 3] = 64'h0000_0000_0000_1401;              // L2[0] -> PPN 5
        dmem[32'h5000 >> 3] = 64'h0000_0000_0000_1801;              // L1[0] -> PPN 6
        dmem[32'h6000 >> 3] = 64'h0000_0000_0000_00cf;              // L0[0] -> PA 0x0000, S R/W/X/A/D
        dmem[(32'h6000 + 8) >> 3] = 64'h0000_0000_0000_04db;        // L0[1] -> PA 0x1000, U R/X/A/D
        dmem[(32'h6000 + 16) >> 3] = 64'h0000_0000_0000_1cd7;       // L0[2] -> PA 0x7000, U R/W/A/D

        pcw = 0;
        emit(enc_i(12'sd384, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 384
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                // csrw  mtvec, x2
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 1
        emit(enc_i(12'sd63, 5'd2, 3'b001, 5'd2, 7'b0010011));      // slli  x2, x2, 63
        emit(enc_i(12'sd4, 5'd2, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x2, 4
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                // csrw  satp, x2
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 1
        emit(enc_i(12'sd8, 5'd2, 3'b001, 5'd2, 7'b0010011));       // slli  x2, x2, 8
        emit(enc_csr(12'h302, 5'd2, 3'b001, 5'd0));                // csrw  medeleg, x2 (U ecall)
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));   // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                // csrw  mstatus, x3 (MPP=S)
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 128
        emit(enc_csr(12'h341, 5'd2, 3'b001, 5'd0));                // csrw  mepc, x2
        emit(32'h3020_0073);                                       // mret

        seek(32'h0080);
        emit(enc_i(12'sd768, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 768
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 256
        emit(enc_csr(12'h105, 5'd2, 3'b001, 5'd0));                // csrw  stvec, x2
        emit(enc_csr(12'h100, 5'd0, 3'b001, 5'd0));                // csrw  sstatus, x0 (SPP=0)
        emit(enc_u(20'h00001, 5'd2, 7'b0110111));                  // lui   x2, 0x1
        emit(enc_csr(12'h141, 5'd2, 3'b001, 5'd0));                // csrw  sepc, x2
        emit(32'h1020_0073);                                       // sret to U

        seek(32'h0100);
        emit(enc_i(12'sd768, 5'd0, 3'b000, 5'd31, 7'b0010011));    // addi  x31, x0, 768
        emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd3));                // csrr  x3, sepc
        emit(enc_s(12'sd0, 5'd3, 5'd31, 3'b011, 7'b0100011));      // sd    x3, 0(x31)
        emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd4));                // csrr  x4, scause
        emit(enc_s(12'sd8, 5'd4, 5'd31, 3'b011, 7'b0100011));      // sd    x4, 8(x31)
        emit(enc_csr(12'h100, 5'd0, 3'b010, 5'd5));                // csrr  x5, sstatus
        emit(enc_s(12'sd16, 5'd5, 5'd31, 3'b011, 7'b0100011));     // sd    x5, 16(x31)
        emit(enc_i(12'sd4, 5'd3, 3'b000, 5'd3, 7'b0010011));       // addi  x3, x3, 4
        emit(enc_csr(12'h141, 5'd3, 3'b001, 5'd0));                // csrw  sepc, x3
        emit(32'h1020_0073);                                       // sret back to U

        seek(32'h0180);
        emit(enc_i(12'sd768, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 768
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd3));                // csrr  x3, mcause
        emit(enc_s(12'sd24, 5'd3, 5'd1, 3'b011, 7'b0100011));      // sd    x3, 24(x1)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd4));                // csrr  x4, mtval
        emit(enc_s(12'sd32, 5'd4, 5'd1, 3'b011, 7'b0100011));      // sd    x4, 32(x1)
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd5));                // csrr  x5, mepc
        emit(enc_s(12'sd40, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 40(x1)
        emit(32'h0010_0073);                                       // ebreak

        seek(32'h1000);
        emit(enc_u(20'h00002, 5'd1, 7'b0110111));                  // lui   x1, 0x2
        emit(enc_i(12'sd90, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 90
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));       // sd    x2, 0(x1)
        emit(32'h0000_0073);                                       // ecall from U
        emit(enc_i(12'sd51, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 51
        emit(enc_s(12'sd8, 5'd2, 5'd1, 3'b011, 7'b0100011));       // sd    x2, 8(x1)
        emit(32'h0010_0073);                                       // ebreak

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 2000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage U-mode Sv39 test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(96, 64'h0000_0000_0000_100c, "U ecall sepc");
        expect64(97, 64'h0000_0000_0000_0008, "U ecall scause");
        expect64(99, 64'h0000_0000_0000_0000, "U unexpected M trap");
        expect64(100, 64'h0000_0000_0000_0000, "U unexpected M trap mtval");
        expect64(101, 64'h0000_0000_0000_0000, "U unexpected M trap mepc");
        expect64(32'h7000 >> 3, 64'h0000_0000_0000_005a, "U page store before ecall");
        expect64(32'h7008 >> 3, 64'h0000_0000_0000_0033, "U page store after sret");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        dmem[32'h1000 >> 3] = 64'h8877_6655_4433_2211;              // Backing data for MXR read.
        dmem[32'h7000 >> 3] = 64'h0123_4567_89ab_cdef;              // Backing data for SUM read.
        dmem[32'h4000 >> 3] = 64'h0000_0000_0000_1401;              // L2[0] -> PPN 5
        dmem[32'h5000 >> 3] = 64'h0000_0000_0000_1801;              // L1[0] -> PPN 6
        dmem[32'h6000 >> 3] = 64'h0000_0000_0000_00cf;              // L0[0] -> PA 0x0000, S R/W/X/A/D
        dmem[(32'h6000 + 8) >> 3] = 64'h0000_0000_0000_04d9;        // L0[1] -> PA 0x1000, U X/A/D
        dmem[(32'h6000 + 16) >> 3] = 64'h0000_0000_0000_1cd7;       // L0[2] -> PA 0x7000, U R/W/A/D

        pcw = 0;
        emit(enc_i(12'sd384, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 384
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                // csrw  mtvec, x2
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 1
        emit(enc_i(12'sd63, 5'd2, 3'b001, 5'd2, 7'b0010011));      // slli  x2, x2, 63
        emit(enc_i(12'sd4, 5'd2, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x2, 4
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                // csrw  satp, x2
        emit(enc_u(20'h00008, 5'd2, 7'b0110111));                  // lui   x2, 0x8
        emit(enc_i(12'sd256, 5'd2, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x2, 0x100
        emit(enc_csr(12'h302, 5'd2, 3'b001, 5'd0));                // csrw  medeleg, x2 (U ecall + store page fault)
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));   // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                // csrw  mstatus, x3 (MPP=S)
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 128
        emit(enc_csr(12'h341, 5'd2, 3'b001, 5'd0));                // csrw  mepc, x2
        emit(32'h3020_0073);                                       // mret

        seek(32'h0080);
        emit(enc_i(12'sd768, 5'd0, 3'b000, 5'd31, 7'b0010011));    // addi  x31, x0, 768
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 256
        emit(enc_csr(12'h105, 5'd2, 3'b001, 5'd0));                // csrw  stvec, x2
        emit(enc_u(20'h000c0, 5'd2, 7'b0110111));                  // lui   x2, 0xc0 (SUM|MXR)
        emit(enc_csr(12'h100, 5'd2, 3'b001, 5'd0));                // csrw  sstatus, x2
        emit(enc_u(20'h00002, 5'd3, 7'b0110111));                  // lui   x3, 0x2
        emit(enc_i(12'sd0, 5'd3, 3'b011, 5'd4, 7'b0000011));       // ld    x4, 0(x3)
        emit(enc_s(12'sd0, 5'd4, 5'd31, 3'b011, 7'b0100011));      // sd    x4, 0(x31)
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        emit(enc_i(12'sd0, 5'd3, 3'b011, 5'd5, 7'b0000011));       // ld    x5, 0(x3)
        emit(enc_s(12'sd8, 5'd5, 5'd31, 3'b011, 7'b0100011));      // sd    x5, 8(x31)
        emit(enc_csr(12'h100, 5'd0, 3'b001, 5'd0));                // csrw  sstatus, x0
        emit(enc_u(20'h00001, 5'd2, 7'b0110111));                  // lui   x2, 0x1
        emit(enc_csr(12'h141, 5'd2, 3'b001, 5'd0));                // csrw  sepc, x2
        emit(32'h1020_0073);                                       // sret to U

        seek(32'h0100);
        emit(enc_i(12'sd768, 5'd0, 3'b000, 5'd31, 7'b0010011));    // addi  x31, x0, 768
        emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd3));                // csrr  x3, sepc
        emit(enc_s(12'sd16, 5'd3, 5'd31, 3'b011, 7'b0100011));     // sd    x3, 16(x31)
        emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd4));                // csrr  x4, scause
        emit(enc_s(12'sd24, 5'd4, 5'd31, 3'b011, 7'b0100011));     // sd    x4, 24(x31)
        emit(enc_csr(12'h143, 5'd0, 3'b010, 5'd5));                // csrr  x5, stval
        emit(enc_s(12'sd32, 5'd5, 5'd31, 3'b011, 7'b0100011));     // sd    x5, 32(x31)
        emit(enc_i(12'sd4, 5'd3, 3'b000, 5'd3, 7'b0010011));       // addi  x3, x3, 4
        emit(enc_csr(12'h141, 5'd3, 3'b001, 5'd0));                // csrw  sepc, x3
        emit(32'h1020_0073);                                       // sret back to U

        seek(32'h0180);
        emit(enc_i(12'sd768, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 768
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd3));                // csrr  x3, mcause
        emit(enc_s(12'sd40, 5'd3, 5'd1, 3'b011, 7'b0100011));      // sd    x3, 40(x1)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd4));                // csrr  x4, mtval
        emit(enc_s(12'sd48, 5'd4, 5'd1, 3'b011, 7'b0100011));      // sd    x4, 48(x1)
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd5));                // csrr  x5, mepc
        emit(enc_s(12'sd56, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 56(x1)
        emit(32'h0010_0073);                                       // ebreak

        seek(32'h1000);
        emit(enc_i(12'sd102, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 102
        emit(enc_s(12'sd0, 5'd2, 5'd0, 3'b011, 7'b0100011));       // sd    x2, 0(x0)
        emit(32'h0010_0073);                                       // ebreak after S trap return

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 2000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage Sv39 SUM/MXR test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(96, 64'h0123_4567_89ab_cdef, "Sv39 SUM S-load from U data");
        expect64(97, 64'h8877_6655_4433_2211, "Sv39 MXR S-load from U execute page");
        expect64(98, 64'h0000_0000_0000_1004, "Sv39 delegated U store fault sepc");
        expect64(99, 64'h0000_0000_0000_000f, "Sv39 delegated U store fault scause");
        expect64(100, 64'h0000_0000_0000_0000, "Sv39 delegated U store fault stval");
        expect64(101, 64'h0000_0000_0000_0000, "Sv39 SUM/MXR unexpected M trap");
        expect64(102, 64'h0000_0000_0000_0000, "Sv39 SUM/MXR unexpected M trap tval");
        expect64(103, 64'h0000_0000_0000_0000, "Sv39 SUM/MXR unexpected M trap mepc");

        clear_memories();

        dmem[32'h4000 >> 3] = 64'h0000_0000_0000_1401;              // L2[0] -> PPN 5
        dmem[32'h5000 >> 3] = 64'h0000_0000_0000_1801;              // L1[0] -> PPN 6
        dmem[(32'h6000 + (1 * 8)) >> 3] = 64'h0000_0000_0000_04cf;  // VA 0x1000 -> PA 0x1000
        for (int i = 0; i < 16; i++) begin
            dmem[(32'h6000 + ((16 + i) * 8)) >> 3] = 64'h0000_0000_0000_1ccf; // VA page -> PA 0x7000
        end

        pcw = 0;
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 1
        emit(enc_i(12'sd63, 5'd2, 3'b001, 5'd2, 7'b0010011));      // slli  x2, x2, 63
        emit(enc_i(12'sd4, 5'd2, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x2, 4
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                // csrw  satp, x2
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));   // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                // csrw  mstatus, x3 (MPP=S)
        emit(enc_u(20'h00001, 5'd4, 7'b0110111));                  // lui   x4, 0x1
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                // csrw  mepc, x4
        emit(32'h3020_0073);                                       // mret to S-mode under Sv39

        seek(32'h1000);
        emit(enc_u(20'h00010, 5'd1, 7'b0110111));                  // lui   x1, 0x10
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        for (int i = 0; i < 16; i++) begin
            emit(enc_i(i + 12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011)); // addi x2, x0, marker
            emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));   // sd    x2, 0(x1)
            if (i != 15) begin
                emit(enc_r(7'b0000000, 5'd3, 5'd1, 3'b000, 5'd1, 7'b0110011)); // add x1, x1, x3
            end
        end
        emit(32'h0010_0073);                                       // ebreak

        pulse_soft_reset();
        wait_for_halt(3000, "ZX64 five-stage Sv39 16-entry DTLB coverage test");

        expect64(32'h7000 >> 3, 64'h0000_0000_0000_004f, "Sv39 16-entry DTLB final store");
        for (int i = 0; i < 16; i++) begin
            if (!u_core.dtlb_valid[i]) begin
                $fatal(1, "Sv39 16-entry DTLB expected valid slot %0d", i);
            end
            if (u_core.dtlb_vpn_tags[i] !== 27'(i + 16)) begin
                $fatal(1, "Sv39 16-entry DTLB slot %0d expected vpn tag %07x got %07x",
                       i, 27'(i + 16), u_core.dtlb_vpn_tags[i]);
            end
            if (u_core.dtlb_levels[i] !== 2'd0) begin
                $fatal(1, "Sv39 16-entry DTLB slot %0d expected level 0 got %0d",
                       i, u_core.dtlb_levels[i]);
            end
        end

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 128
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                // csrw  mtvec, x2
        illegal_pcw = pcw;
        emit(32'h0000_0053);                                       // unsupported OP-FP opcode
        emit(enc_i(12'sd119, 5'd0, 3'b000, 5'd3, 7'b0010011));     // addi  x3, x0, 119
        emit(enc_s(12'sd0, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd    x3, 0(x1)
        emit(32'h0010_0073);                                       // ebreak
        pcw = 32;
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd4));                // csrr  x4, mepc
        emit(enc_s(12'sd8, 5'd4, 5'd1, 3'b011, 7'b0100011));       // sd    x4, 8(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd5));                // csrr  x5, mcause
        emit(enc_s(12'sd16, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 16(x1)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd6));                // csrr  x6, mtval
        emit(enc_s(12'sd24, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 24(x1)
        emit(enc_i(12'sd4, 5'd4, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x4, 4
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                // csrw  mepc, x4
        emit(32'h3020_0073);                                       // mret

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 500 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage illegal trap test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32, 64'h0000_0000_0000_0077, "illegal trap resumed after mret");
        expect64(33, 64'(illegal_pcw * 4), "illegal trap mepc");
        expect64(34, 64'h0000_0000_0000_0002, "illegal trap mcause");
        expect64(35, 64'h0000_0000_0000_0053, "illegal trap mtval");

        run_fpu_csr_substrate_test();
        run_fpu_state_move_test();
        run_fpu_compressed_mem_test();
        run_fpu_int_to_float_cvt_test();
        run_fpu_float_to_int_cvt_test();
        run_fpu_addsub_test();
        run_fpu_mul_test();
        run_fpu_fp_to_fp_cvt_test();
        run_fpu_divsqrt_test();
        run_fpu_fma_test();
        run_fpu_class_compare_test();
        run_fpu_fs_dirty_access_test();
        run_illegal_instr_trap(enc_csr(12'h001, 5'd0, 3'b001, 5'd0),
                               64'h0000_0000_0000_005e, "FFLAGS CSR with FS=Off illegal trap");
        run_illegal_instr_trap(enc_csr(12'h002, 5'd0, 3'b001, 5'd0),
                               64'h0000_0000_0000_005f, "FRM CSR with FS=Off illegal trap");
        run_illegal_instr_trap(enc_csr(12'h003, 5'd0, 3'b010, 5'd3),
                               64'h0000_0000_0000_0060, "FCSR CSR with FS=Off illegal trap");
        run_illegal_instr_trap(enc_i(12'sd0, 5'd0, 3'b011, 5'd1, 7'b0000111),
                               64'h0000_0000_0000_0061, "FP LOAD illegal trap");
        run_illegal_instr_trap(enc_s(12'sd0, 5'd1, 5'd0, 3'b011, 7'b0100111),
                               64'h0000_0000_0000_0062, "FP STORE illegal trap");
        run_illegal_instr_trap(enc_fp_r4(5'd0, 2'b01, 5'd0, 5'd0, 3'b000, 5'd0, 7'b1000011),
                               64'h0000_0000_0000_0063, "FP MADD with FS=Off illegal trap");
        run_illegal_instr_trap(enc_fp_r4(5'd0, 2'b01, 5'd0, 5'd0, 3'b000, 5'd0, 7'b1000111),
                               64'h0000_0000_0000_0064, "FP MSUB with FS=Off illegal trap");
        run_illegal_instr_trap(enc_fp_r4(5'd0, 2'b01, 5'd0, 5'd0, 3'b000, 5'd0, 7'b1001011),
                               64'h0000_0000_0000_0065, "FP NMSUB with FS=Off illegal trap");
        run_illegal_instr_trap(enc_fp_r4(5'd0, 2'b01, 5'd0, 5'd0, 3'b000, 5'd0, 7'b1001111),
                               64'h0000_0000_0000_0066, "FP NMADD with FS=Off illegal trap");
        run_illegal_instr_trap(32'h0000_0053,
                               64'h0000_0000_0000_0067, "FP OP illegal trap");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 128
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                // csrw  mtvec, x2
        illegal_pcw = pcw;
        emit(enc_i(12'sd257, 5'd0, 3'b000, 5'd7, 7'b0010011));     // addi  x7, x0, 257
        emit(enc_i(12'sd0, 5'd7, 3'b011, 5'd3, 7'b0000011));       // ld    x3, 0(x7), misaligned
        emit(enc_i(12'sd85, 5'd0, 3'b000, 5'd3, 7'b0010011));      // addi  x3, x0, 85
        emit(enc_s(12'sd0, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd    x3, 0(x1)
        emit(32'h0010_0073);                                       // ebreak
        pcw = 32;
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd4));                // csrr  x4, mepc
        emit(enc_s(12'sd8, 5'd4, 5'd1, 3'b011, 7'b0100011));       // sd    x4, 8(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd5));                // csrr  x5, mcause
        emit(enc_s(12'sd16, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 16(x1)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd6));                // csrr  x6, mtval
        emit(enc_s(12'sd24, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 24(x1)
        emit(enc_i(12'sd4, 5'd4, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x4, 4
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                // csrw  mepc, x4
        emit(32'h3020_0073);                                       // mret

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 500 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage misaligned load trap test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32, 64'h0000_0000_0000_0055, "misaligned load trap resumed after mret");
        expect64(33, 64'(illegal_pcw * 4 + 4), "misaligned load trap mepc");
        expect64(34, 64'h0000_0000_0000_0004, "misaligned load trap mcause");
        expect64(35, 64'h0000_0000_0000_0101, "misaligned load trap mtval");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 256
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 128
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                // csrw  mtvec, x2
        illegal_pcw = pcw;
        emit(enc_csr(12'hf11, 5'd0, 3'b001, 5'd0));                // csrw  mvendorid, x0, read-only CSR
        emit(enc_i(12'sd51, 5'd0, 3'b000, 5'd3, 7'b0010011));      // addi  x3, x0, 51
        emit(enc_s(12'sd0, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd    x3, 0(x1)
        emit(32'h0010_0073);                                       // ebreak
        pcw = 32;
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd4));                // csrr  x4, mepc
        emit(enc_s(12'sd8, 5'd4, 5'd1, 3'b011, 7'b0100011));       // sd    x4, 8(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd5));                // csrr  x5, mcause
        emit(enc_s(12'sd16, 5'd5, 5'd1, 3'b011, 7'b0100011));      // sd    x5, 16(x1)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd6));                // csrr  x6, mtval
        emit(enc_s(12'sd24, 5'd6, 5'd1, 3'b011, 7'b0100011));      // sd    x6, 24(x1)
        emit(enc_i(12'sd4, 5'd4, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x4, 4
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                // csrw  mepc, x4
        emit(32'h3020_0073);                                       // mret

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 500 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage read-only CSR trap test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32, 64'h0000_0000_0000_0033, "read-only CSR trap resumed after mret");
        expect64(33, 64'(illegal_pcw * 4), "read-only CSR trap mepc");
        expect64(34, 64'h0000_0000_0000_0002, "read-only CSR trap mcause");
        expect64(35, 64'h0000_0000_f110_1073, "read-only CSR trap mtval");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pch = 0;
        emit16(c_addi(5'd0, 6'sd0));                                  // c.nop
        emit32(enc_i(12'sd0, 5'd0, 3'b000, 5'd2, 7'b0010011));         // crossing addi x2, x0, 0
        emit16(c_addi16sp(10'sd64));                                   // sp = 64
        emit16(c_li(5'd8, 6'sd11));                                    // x8 = 11
        emit16(c_sdsp(5'd8, 9'd0));                                    // [sp+0] = 11
        emit16(c_ldsp(5'd9, 9'd0));                                    // x9 = [sp+0]
        emit16(c_addi4spn(3'd2, 10'd16));                              // x10 = sp + 16
        emit16(c_sd(3'd1, 3'd2, 8'd0));                                // [x10] = x9
        emit16(c_ld(3'd3, 3'd2, 8'd0));                                // x11 = [x10]
        emit16(c_sdsp(5'd11, 9'd8));                                   // [sp+8] = x11
        emit16(c_addiw(5'd11, 6'sd1));                                 // x11 = 12
        emit16(c_slli(5'd11, 6'd1));                                   // x11 = 24
        emit16(c_srli(3'd3, 6'd1));                                    // x11 = 12
        emit16(c_andi(3'd3, 6'sd15));                                  // x11 = 12
        emit16(c_sdsp(5'd11, 9'd24));                                  // [sp+24] = 12
        emit16(c_li(5'd12, 6'sd0));
        emit16(c_beqz(3'd4, 9'sd4));                                   // skip next c.li
        emit16(c_li(5'd13, 6'sd1));
        emit16(c_li(5'd13, 6'sd2));
        emit16(c_sdsp(5'd13, 9'd32));
        emit16(c_li(5'd14, 6'sd1));
        emit16(c_bnez(3'd6, 9'sd4));                                   // skip next c.li
        emit16(c_li(5'd15, 6'sd3));
        emit16(c_li(5'd15, 6'sd4));
        emit16(c_sdsp(5'd15, 9'd40));
        emit16(c_j(12'sd4));                                           // skip next c.li
        emit16(c_li(5'd15, 6'sd5));
        emit16(c_sdsp(5'd15, 9'd48));
        emit16(c_ebreak());

        irq_timer = 1'b0;
        irq_external = 1'b0;
        soft_reset = 1'b1;
        @(posedge clk);
        soft_reset = 1'b0;

        for (int cycle = 0; cycle < 1000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 five-stage compressed test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(8, 64'd11, "c.sdsp");
        expect64(9, 64'd11, "c.ldsp/c.sdsp");
        expect64(10, 64'd11, "c.addi4spn/c.sd/c.ld");
        expect64(11, 64'd12, "compressed arithmetic");
        expect64(12, 64'd2, "c.beqz");
        expect64(13, 64'd4, "c.bnez");
        expect64(14, 64'd4, "c.j");

        $display("tb_zx64_core5: PASS");
        $finish;
    end
endmodule
