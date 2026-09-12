module tb_zx64_core;
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    zx64_core u_core (
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

    integer pcw;

    task automatic emit(input logic [31:0] inst);
        begin
            imem[pcw] = inst;
            pcw = pcw + 1;
        end
    endtask

    task automatic seek(input int byte_addr);
        begin
            pcw = byte_addr >> 2;
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

    initial begin
        irq_timer = 1'b0;
        irq_external = 1'b0;

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));      // addi  x1, x0, 256
        emit(enc_i(-12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, -1
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));        // sd    x2, 0(x1)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd3, 7'b0000011));        // ld    x3, 0(x1)
        emit(enc_s(12'sd8, 5'd2, 5'd1, 3'b010, 7'b0100011));        // sw    x2, 8(x1)
        emit(enc_i(12'sd8, 5'd1, 3'b110, 5'd4, 7'b0000011));        // lwu   x4, 8(x1)
        emit(enc_i(12'sd8, 5'd1, 3'b010, 5'd5, 7'b0000011));        // lw    x5, 8(x1)
        emit(enc_s(12'sd32, 5'd4, 5'd1, 3'b011, 7'b0100011));       // sd    x4, 32(x1)
        emit(enc_s(12'sd40, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 40(x1)
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd6, 7'b0010011));        // addi  x6, x0, 1
        emit(enc_i(12'sd40, 5'd6, 3'b001, 5'd6, 7'b0010011));       // slli  x6, x6, 40
        emit(enc_s(12'sd16, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 16(x1)
        emit(enc_i(12'sd16, 5'd1, 3'b011, 5'd7, 7'b0000011));       // ld    x7, 16(x1)
        emit(enc_r(7'b0000000, 5'd7, 5'd6, 3'b000, 5'd8, 7'b0110011)); // add x8, x6, x7
        emit(enc_s(12'sd24, 5'd8, 5'd1, 3'b011, 7'b0100011));       // sd    x8, 24(x1)
        emit(enc_i(12'sd1, 5'd2, 3'b000, 5'd9, 7'b0011011));        // addiw x9, x2, 1
        emit(enc_i(-12'sd1, 5'd0, 3'b000, 5'd10, 7'b0011011));      // addiw x10, x0, -1
        emit(enc_i(12'sd1, 5'd10, 3'b001, 5'd11, 7'b0011011));      // slliw x11, x10, 1
        emit(enc_i(12'sd1, 5'd11, 3'b101, 5'd12, 7'b0011011));      // srliw x12, x11, 1
        emit(enc_i(12'sh401, 5'd11, 3'b101, 5'd13, 7'b0011011));    // sraiw x13, x11, 1
        emit(enc_s(12'sd48, 5'd9, 5'd1, 3'b011, 7'b0100011));       // sd    x9, 48(x1)
        emit(enc_s(12'sd56, 5'd10, 5'd1, 3'b011, 7'b0100011));      // sd    x10, 56(x1)
        emit(enc_s(12'sd64, 5'd11, 5'd1, 3'b011, 7'b0100011));      // sd    x11, 64(x1)
        emit(enc_s(12'sd72, 5'd12, 5'd1, 3'b011, 7'b0100011));      // sd    x12, 72(x1)
        emit(enc_s(12'sd80, 5'd13, 5'd1, 3'b011, 7'b0100011));      // sd    x13, 80(x1)
        emit(enc_b(13'sd8, 5'd0, 5'd9, 3'b000, 7'b1100011));        // beq   x9, x0, +8
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd14, 7'b0010011));       // addi  x14, x0, 1
        emit(enc_i(12'sd2, 5'd0, 3'b000, 5'd14, 7'b0010011));       // addi  x14, x0, 2
        emit(enc_s(12'sd88, 5'd14, 5'd1, 3'b011, 7'b0100011));      // sd    x14, 88(x1)
        emit(enc_j(21'sd8, 5'd15, 7'b1101111));                     // jal   x15, +8
        emit(enc_i(12'sd3, 5'd0, 3'b000, 5'd14, 7'b0010011));       // addi  x14, x0, 3
        emit(enc_s(12'sd96, 5'd15, 5'd1, 3'b011, 7'b0100011));      // sd    x15, 96(x1)
        emit(enc_u(20'h80000, 5'd16, 7'b0110111));                  // lui   x16, 0x80000
        emit(enc_s(12'sd104, 5'd16, 5'd1, 3'b011, 7'b0100011));     // sd    x16, 104(x1)
        emit(enc_r(7'b0000000, 5'd10, 5'd10, 3'b000, 5'd17, 7'b0111011)); // addw x17, x10, x10
        emit(enc_r(7'b0100000, 5'd10, 5'd0, 3'b000, 5'd18, 7'b0111011));  // subw x18, x0, x10
        emit(enc_s(12'sd112, 5'd17, 5'd1, 3'b011, 7'b0100011));     // sd    x17, 112(x1)
        emit(enc_s(12'sd120, 5'd18, 5'd1, 3'b011, 7'b0100011));     // sd    x18, 120(x1)
        emit(enc_i(12'sd7, 5'd0, 3'b000, 5'd19, 7'b0010011));       // addi  x19, x0, 7
        emit(enc_i(-12'sd3, 5'd0, 3'b000, 5'd20, 7'b0010011));      // addi  x20, x0, -3
        emit(enc_r(7'b0000001, 5'd20, 5'd19, 3'b000, 5'd21, 7'b0110011)); // mul x21, x19, x20
        emit(enc_s(12'sd128, 5'd21, 5'd1, 3'b011, 7'b0100011));     // sd    x21, 128(x1)
        emit(enc_r(7'b0000001, 5'd19, 5'd21, 3'b100, 5'd22, 7'b0110011)); // div x22, x21, x19
        emit(enc_s(12'sd136, 5'd22, 5'd1, 3'b011, 7'b0100011));     // sd    x22, 136(x1)
        emit(enc_r(7'b0000001, 5'd19, 5'd21, 3'b110, 5'd23, 7'b0110011)); // rem x23, x21, x19
        emit(enc_s(12'sd144, 5'd23, 5'd1, 3'b011, 7'b0100011));     // sd    x23, 144(x1)
        emit(enc_r(7'b0000001, 5'd19, 5'd2, 3'b011, 5'd24, 7'b0110011));  // mulhu x24, x2, x19
        emit(enc_s(12'sd152, 5'd24, 5'd1, 3'b011, 7'b0100011));     // sd    x24, 152(x1)
        emit(enc_r(7'b0000001, 5'd10, 5'd10, 3'b000, 5'd25, 7'b0111011)); // mulw x25, x10, x10
        emit(enc_s(12'sd160, 5'd25, 5'd1, 3'b011, 7'b0100011));     // sd    x25, 160(x1)
        emit(32'h0010_0073);                                        // ebreak

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 500 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 core did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32, 64'hffff_ffff_ffff_ffff, "sd/ld");
        expect64(33, 64'h0000_0000_ffff_ffff, "sw");
        expect64(34, 64'h0000_0100_0000_0000, "slli64");
        expect64(35, 64'h0000_0200_0000_0000, "add64");
        expect64(36, 64'h0000_0000_ffff_ffff, "lwu");
        expect64(37, 64'hffff_ffff_ffff_ffff, "lw");
        expect64(38, 64'h0000_0000_0000_0000, "addiw");
        expect64(39, 64'hffff_ffff_ffff_ffff, "addiw sign");
        expect64(40, 64'hffff_ffff_ffff_fffe, "slliw");
        expect64(41, 64'h0000_0000_7fff_ffff, "srliw");
        expect64(42, 64'hffff_ffff_ffff_ffff, "sraiw");
        expect64(43, 64'h0000_0000_0000_0002, "branch");
        expect64(44, 64'h0000_0000_0000_0078, "jal link");
        expect64(45, 64'hffff_ffff_8000_0000, "lui sign");
        expect64(46, 64'hffff_ffff_ffff_fffe, "addw");
        expect64(47, 64'h0000_0000_0000_0001, "subw");
        expect64(48, 64'hffff_ffff_ffff_ffeb, "mul");
        expect64(49, 64'hffff_ffff_ffff_fffd, "div");
        expect64(50, 64'h0000_0000_0000_0000, "rem");
        expect64(51, 64'h0000_0000_0000_0006, "mulhu");
        expect64(52, 64'h0000_0000_0000_0001, "mulw");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));      // addi  x1, x0, 256
        emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 64
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                 // csrw  mtvec, x2
        emit(enc_csr(12'h301, 5'd0, 3'b010, 5'd3));                 // csrr  x3, misa
        emit(enc_s(12'sd0, 5'd3, 5'd1, 3'b011, 7'b0100011));        // sd    x3, 0(x1)
        emit(32'h0000_0073);                                        // ecall
        emit(enc_i(12'sh055, 5'd0, 3'b000, 5'd4, 7'b0010011));      // addi  x4, x0, 0x55
        emit(enc_s(12'sd24, 5'd4, 5'd1, 3'b011, 7'b0100011));       // sd    x4, 24(x1)
        emit(32'h0010_0073);                                        // ebreak
        pcw = 16;
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd5));                 // csrr  x5, mepc
        emit(enc_s(12'sd8, 5'd5, 5'd1, 3'b011, 7'b0100011));        // sd    x5, 8(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd6));                 // csrr  x6, mcause
        emit(enc_s(12'sd16, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 16(x1)
        emit(enc_i(12'sd4, 5'd5, 3'b000, 5'd5, 7'b0010011));        // addi  x5, x5, 4
        emit(enc_csr(12'h341, 5'd5, 3'b001, 5'd0));                 // csrw  mepc, x5
        emit(32'h3020_0073);                                        // mret

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 500 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 CSR/trap test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32, 64'h8000_0000_0004_1105, "misa");
        expect64(33, 64'h0000_0000_0000_0014, "ecall mepc");
        expect64(34, 64'h0000_0000_0000_000b, "ecall mcause");
        expect64(35, 64'h0000_0000_0000_0055, "mret return");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd256, 5'd0, 3'b000, 5'd1, 7'b0010011));      // addi  x1, x0, 256
        emit(enc_i(12'sd384, 5'd0, 3'b000, 5'd31, 7'b0010011));     // addi  x31, x0, 384
        emit(enc_i(12'sd5, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 5
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));        // sd    x2, 0(x1)
        emit(enc_amo(5'b00010, 5'd0, 5'd1, 3'b011, 5'd3));          // lr.d  x3, (x1)
        emit(enc_i(12'sd9, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 9
        emit(enc_amo(5'b00011, 5'd2, 5'd1, 3'b011, 5'd4));          // sc.d  x4, x2, (x1)
        emit(enc_amo(5'b00011, 5'd2, 5'd1, 3'b011, 5'd5));          // sc.d  x5, x2, (x1)
        emit(enc_i(12'sd3, 5'd0, 3'b000, 5'd6, 7'b0010011));        // addi  x6, x0, 3
        emit(enc_amo(5'b00000, 5'd6, 5'd1, 3'b011, 5'd7));          // amoadd.d x7, x6, (x1)
        emit(enc_amo(5'b00001, 5'd6, 5'd1, 3'b011, 5'd8));          // amoswap.d x8, x6, (x1)
        emit(enc_i(-12'sd4, 5'd0, 3'b000, 5'd9, 7'b0010011));       // addi  x9, x0, -4
        emit(enc_s(12'sd8, 5'd9, 5'd1, 3'b010, 7'b0100011));        // sw    x9, 8(x1)
        emit(enc_amo(5'b00010, 5'd0, 5'd1, 3'b010, 5'd10));         // lr.w  x10, (x1)
        emit(enc_i(12'sd8, 5'd1, 3'b000, 5'd11, 7'b0010011));       // addi  x11, x1, 8
        emit(enc_amo(5'b00010, 5'd0, 5'd11, 3'b010, 5'd12));        // lr.w  x12, (x11)
        emit(enc_i(12'sd7, 5'd0, 3'b000, 5'd13, 7'b0010011));       // addi  x13, x0, 7
        emit(enc_amo(5'b00011, 5'd13, 5'd11, 3'b010, 5'd14));       // sc.w  x14, x13, (x11)
        emit(enc_amo(5'b00000, 5'd13, 5'd11, 3'b010, 5'd15));       // amoadd.w x15, x13, (x11)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd16, 7'b0000011));       // ld    x16, 0(x1)
        emit(enc_i(12'sd8, 5'd1, 3'b011, 5'd17, 7'b0000011));       // ld    x17, 8(x1)
        emit(enc_s(12'sd0, 5'd3, 5'd31, 3'b011, 7'b0100011));       // sd    x3, 0(x31)
        emit(enc_s(12'sd8, 5'd4, 5'd31, 3'b011, 7'b0100011));       // sd    x4, 8(x31)
        emit(enc_s(12'sd16, 5'd5, 5'd31, 3'b011, 7'b0100011));      // sd    x5, 16(x31)
        emit(enc_s(12'sd24, 5'd7, 5'd31, 3'b011, 7'b0100011));      // sd    x7, 24(x31)
        emit(enc_s(12'sd32, 5'd8, 5'd31, 3'b011, 7'b0100011));      // sd    x8, 32(x31)
        emit(enc_s(12'sd40, 5'd16, 5'd31, 3'b011, 7'b0100011));     // sd    x16, 40(x31)
        emit(enc_s(12'sd48, 5'd10, 5'd31, 3'b011, 7'b0100011));     // sd    x10, 48(x31)
        emit(enc_s(12'sd56, 5'd12, 5'd31, 3'b011, 7'b0100011));     // sd    x12, 56(x31)
        emit(enc_s(12'sd64, 5'd14, 5'd31, 3'b011, 7'b0100011));     // sd    x14, 64(x31)
        emit(enc_s(12'sd72, 5'd15, 5'd31, 3'b011, 7'b0100011));     // sd    x15, 72(x31)
        emit(enc_s(12'sd80, 5'd17, 5'd31, 3'b011, 7'b0100011));     // sd    x17, 80(x31)
        emit(32'h0010_0073);                                        // ebreak

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 700 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 AMO test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(48, 64'h0000_0000_0000_0005, "lr.d old");
        expect64(49, 64'h0000_0000_0000_0000, "sc.d success");
        expect64(50, 64'h0000_0000_0000_0001, "sc.d failure");
        expect64(51, 64'h0000_0000_0000_0009, "amoadd.d old");
        expect64(52, 64'h0000_0000_0000_000c, "amoswap.d old");
        expect64(53, 64'h0000_0000_0000_0003, "final dword");
        expect64(54, 64'h0000_0000_0000_0003, "lr.w low old");
        expect64(55, 64'hffff_ffff_ffff_fffc, "lr.w high old");
        expect64(56, 64'h0000_0000_0000_0000, "sc.w success");
        expect64(57, 64'h0000_0000_0000_0007, "amoadd.w old");
        expect64(58, 64'h0000_0000_0000_000e, "final word");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd512, 5'd0, 3'b000, 5'd1, 7'b0010011));      // addi  x1, x0, 512
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 128
        emit(enc_csr(12'h105, 5'd2, 3'b001, 5'd0));                 // csrw  stvec, x2
        emit(enc_i(12'sd192, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 192
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                 // csrw  mtvec, x2
        emit(enc_i(12'sd512, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 1 << 9
        emit(enc_csr(12'h302, 5'd2, 3'b001, 5'd0));                 // csrw  medeleg, x2
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));    // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                 // csrw  mstatus, x3 (MPP=S)
        emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 64
        emit(enc_csr(12'h341, 5'd2, 3'b001, 5'd0));                 // csrw  mepc, x2
        emit(32'h3020_0073);                                        // mret

        pcw = 16;
        emit(enc_i(12'sd123, 5'd0, 3'b000, 5'd4, 7'b0010011));      // addi  x4, x0, 123
        emit(32'h0000_0073);                                        // ecall from S, delegated to S
        emit(enc_i(12'sd77, 5'd0, 3'b000, 5'd5, 7'b0010011));       // addi  x5, x0, 77
        emit(enc_s(12'sd24, 5'd5, 5'd1, 3'b011, 7'b0100011));       // sd    x5, 24(x1)
        emit(enc_csr(12'h100, 5'd0, 3'b010, 5'd9));                 // csrr  x9, sstatus
        emit(enc_s(12'sd32, 5'd9, 5'd1, 3'b011, 7'b0100011));       // sd    x9, 32(x1)
        emit(32'h1200_0073);                                        // sfence.vma x0, x0
        emit(32'h0010_0073);                                        // ebreak

        pcw = 32;
        emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd6));                 // csrr  x6, sepc
        emit(enc_s(12'sd0, 5'd6, 5'd1, 3'b011, 7'b0100011));        // sd    x6, 0(x1)
        emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd7));                 // csrr  x7, scause
        emit(enc_s(12'sd8, 5'd7, 5'd1, 3'b011, 7'b0100011));        // sd    x7, 8(x1)
        emit(enc_csr(12'h100, 5'd0, 3'b010, 5'd8));                 // csrr  x8, sstatus
        emit(enc_s(12'sd16, 5'd8, 5'd1, 3'b011, 7'b0100011));       // sd    x8, 16(x1)
        emit(enc_i(12'sd4, 5'd6, 3'b000, 5'd6, 7'b0010011));        // addi  x6, x6, 4
        emit(enc_csr(12'h141, 5'd6, 3'b001, 5'd0));                 // csrw  sepc, x6
        emit(32'h1020_0073);                                        // sret

        pcw = 48;
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd10));                // csrr  x10, mepc
        emit(enc_s(12'sd40, 5'd10, 5'd1, 3'b011, 7'b0100011));      // sd    x10, 40(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd11));                // csrr  x11, mcause
        emit(enc_s(12'sd48, 5'd11, 5'd1, 3'b011, 7'b0100011));      // sd    x11, 48(x1)
        emit(32'h0010_0073);                                        // ebreak

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 800 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 S-mode test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(64, 64'h0000_0000_0000_0044, "S ecall sepc");
        expect64(65, 64'h0000_0000_0000_0009, "S ecall scause");
        expect64(66, 64'h0000_0000_0000_0100, "S trap sstatus");
        expect64(67, 64'h0000_0000_0000_004d, "S sret return");
        expect64(68, 64'h0000_0000_0000_0020, "S post-sret sstatus");
        expect64(69, 64'h0000_0000_0000_0000, "unexpected M trap mepc");
        expect64(70, 64'h0000_0000_0000_0000, "unexpected M trap mcause");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        dmem[32'h1000 >> 3] = 64'h0000_0000_0000_0801;               // L2[0] -> PPN 2
        dmem[32'h2000 >> 3] = 64'h0000_0000_0000_0c01;               // L1[0] -> PPN 3
        dmem[32'h3000 >> 3] = 64'h0000_0000_0000_00cf;               // L0[0] -> PA 0, R/W/X/A/D
        dmem[(32'h3000 + 32) >> 3] = 64'h0000_0000_0000_14c7;        // L0[4] -> PA 0x5000, R/W/A/D
        dmem[(32'h3000 + 48) >> 3] = 64'h0000_0000_0000_0cc7;        // L0[6] -> PA 0x3000, R/W/A/D
        dmem[32'h5000 >> 3] = 64'h1122_3344_5566_7788;
        dmem[32'h6000 >> 3] = 64'h8877_6655_4433_2211;

        pcw = 0;
        emit(enc_i(12'sd768, 5'd0, 3'b000, 5'd31, 7'b0010011));     // addi  x31, x0, 768
        emit(enc_i(12'sd192, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 192
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                 // csrw  mtvec, x2
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, 1
        emit(enc_i(12'sd63, 5'd2, 3'b001, 5'd2, 7'b0010011));       // slli  x2, x2, 63
        emit(enc_i(12'sd1, 5'd2, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x2, 1
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                 // csrw  satp, x2
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));    // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                 // csrw  mstatus, x3 (MPP=S)
        emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 64
        emit(enc_csr(12'h341, 5'd2, 3'b001, 5'd0));                 // csrw  mepc, x2
        emit(32'h3020_0073);                                        // mret

        pcw = 16;
        emit(enc_u(20'h00004, 5'd1, 7'b0110111));                  // lui   x1, 0x4
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd5, 7'b0000011));        // ld    x5, 0(x1)
        emit(enc_s(12'sd8, 5'd5, 5'd1, 3'b011, 7'b0100011));        // sd    x5, 8(x1)
        emit(enc_i(12'sd99, 5'd0, 3'b000, 5'd6, 7'b0010011));       // addi  x6, x0, 99
        emit(enc_s(12'sd16, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 16(x1)
        emit(enc_csr(12'h180, 5'd0, 3'b010, 5'd7));                 // csrr  x7, satp
        emit(enc_s(12'sd24, 5'd7, 5'd1, 3'b011, 7'b0100011));       // sd    x7, 24(x1)
        emit(enc_u(20'h00002, 5'd8, 7'b0110111));                  // lui   x8, 0x2
        emit(enc_i(-12'sd1849, 5'd8, 3'b000, 5'd8, 7'b0010011));     // addi  x8, x8, -1849 -> PTE PA 0x6000
        emit(enc_u(20'h00006, 5'd9, 7'b0110111));                  // lui   x9, 0x6 (VA alias for L0 page)
        emit(enc_s(12'sd32, 5'd8, 5'd9, 3'b011, 7'b0100011));       // sd    x8, 32(x9), rewrite L0[4]
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd10, 7'b0000011));       // ld    x10, 0(x1), DTLB keeps old PA
        emit(enc_s(12'sd32, 5'd10, 5'd1, 3'b011, 7'b0100011));      // sd    x10, 32(x1)
        emit(32'h1200_0073);                                        // sfence.vma x0, x0
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd11, 7'b0000011));       // ld    x11, 0(x1), page-walk sees new PA
        emit(enc_s(12'sd40, 5'd11, 5'd1, 3'b011, 7'b0100011));      // sd    x11, 40(x1)
        emit(32'h0010_0073);                                        // ebreak

        pcw = 48;
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd10));                // csrr  x10, mcause
        emit(enc_s(12'sd0, 5'd10, 5'd31, 3'b011, 7'b0100011));      // sd    x10, 0(x31)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd11));                // csrr  x11, mtval
        emit(enc_s(12'sd8, 5'd11, 5'd31, 3'b011, 7'b0100011));      // sd    x11, 8(x31)
        emit(32'h0010_0073);                                        // ebreak

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 1800 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 Sv39 test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(32'h5000 >> 3, 64'h1122_3344_5566_7788, "Sv39 source");
        expect64(32'h5008 >> 3, 64'h1122_3344_5566_7788, "Sv39 translated load/store");
        expect64(32'h5010 >> 3, 64'h0000_0000_0000_0063, "Sv39 translated store");
        expect64(32'h5018 >> 3, 64'h8000_0000_0000_0001, "Sv39 satp read");
        expect64(32'h3020 >> 3, 64'h0000_0000_0000_18c7, "Sv39 PTE rewrite");
        expect64(32'h5020 >> 3, 64'h1122_3344_5566_7788, "Sv39 DTLB stale before sfence");
        expect64(32'h6028 >> 3, 64'h8877_6655_4433_2211, "Sv39 DTLB refill after sfence");
        expect64(32'h0300 >> 3, 64'h0000_0000_0000_0000, "Sv39 unexpected M trap cause");
        expect64(32'h0308 >> 3, 64'h0000_0000_0000_0000, "Sv39 unexpected M trap tval");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd1536, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 1536
        emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 64
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                 // csrw  mtvec, x2
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, MTIE
        emit(enc_csr(12'h304, 5'd2, 3'b001, 5'd0));                 // csrw  mie, x2
        emit(enc_i(12'sd8, 5'd0, 3'b000, 5'd2, 7'b0010011));        // addi  x2, x0, MIE
        emit(enc_csr(12'h300, 5'd2, 3'b001, 5'd0));                 // csrw  mstatus, x2
        emit(32'h1050_0073);                                        // wfi
        emit(enc_i(12'sd44, 5'd0, 3'b000, 5'd3, 7'b0010011));       // addi  x3, x0, 44
        emit(enc_s(12'sd24, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd    x3, 24(x1)
        emit(32'h0010_0073);                                        // ebreak

        pcw = 16;
        emit(enc_csr(12'h344, 5'd0, 3'b010, 5'd6));                 // csrr  x6, mip
        emit(enc_s(12'sd16, 5'd6, 5'd1, 3'b011, 7'b0100011));       // sd    x6, 16(x1)
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd4));                 // csrr  x4, mepc
        emit(enc_s(12'sd0, 5'd4, 5'd1, 3'b011, 7'b0100011));        // sd    x4, 0(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd5));                 // csrr  x5, mcause
        emit(enc_s(12'sd8, 5'd5, 5'd1, 3'b011, 7'b0100011));        // sd    x5, 8(x1)
        emit(32'h3020_0073);                                        // mret

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 300 && dbg_state[3:0] != 4'd11; cycle++) begin
            @(posedge clk);
        end
        if (dbg_state[3:0] != 4'd11) begin
            $fatal(1, "ZX64 M-timer test did not enter WFI pc=%016x instr=%08x state=%08x",
                   dbg_pc, dbg_instr, dbg_state);
        end
        irq_timer = 1'b1;
        repeat (4) @(posedge clk);
        irq_timer = 1'b0;

        for (int cycle = 0; cycle < 500 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 M-timer interrupt test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(192, 64'h0000_0000_0000_0020, "M timer mepc");
        expect64(193, 64'h8000_0000_0000_0007, "M timer mcause");
        expect64(194, 64'h0000_0000_0000_0080, "M timer mip");
        expect64(195, 64'h0000_0000_0000_002c, "M timer return");

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073; // ebreak
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pcw = 0;
        emit(enc_i(12'sd1792, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi  x1, x0, 1792
        emit(enc_i(12'sd128, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 128
        emit(enc_csr(12'h105, 5'd2, 3'b001, 5'd0));                 // csrw  stvec, x2
        emit(enc_i(12'sd192, 5'd0, 3'b000, 5'd2, 7'b0010011));      // addi  x2, x0, 192
        emit(enc_csr(12'h305, 5'd2, 3'b001, 5'd0));                 // csrw  mtvec, x2
        emit(enc_i(12'sd32, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, STIP
        emit(enc_csr(12'h303, 5'd2, 3'b001, 5'd0));                 // csrw  mideleg, x2
        emit(enc_csr(12'h104, 5'd2, 3'b001, 5'd0));                 // csrw  sie, x2
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd3, 7'b0010011));        // addi  x3, x0, 1
        emit(enc_i(12'sd11, 5'd3, 3'b001, 5'd3, 7'b0010011));       // slli  x3, x3, 11
        emit(enc_i(12'sd2, 5'd3, 3'b000, 5'd3, 7'b0010011));        // addi  x3, x3, SIE
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                 // csrw  mstatus, x3 (MPP=S,SIE=1)
        emit(enc_i(12'sd64, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 64
        emit(enc_csr(12'h341, 5'd2, 3'b001, 5'd0));                 // csrw  mepc, x2
        emit(32'h3020_0073);                                        // mret

        pcw = 16;
        emit(32'h1050_0073);                                        // wfi
        emit(enc_i(12'sd55, 5'd0, 3'b000, 5'd4, 7'b0010011));       // addi  x4, x0, 55
        emit(enc_s(12'sd24, 5'd4, 5'd1, 3'b011, 7'b0100011));       // sd    x4, 24(x1)
        emit(32'h0010_0073);                                        // ebreak

        pcw = 32;
        emit(enc_csr(12'h144, 5'd0, 3'b010, 5'd7));                 // csrr  x7, sip
        emit(enc_s(12'sd16, 5'd7, 5'd1, 3'b011, 7'b0100011));       // sd    x7, 16(x1)
        emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd5));                 // csrr  x5, sepc
        emit(enc_s(12'sd0, 5'd5, 5'd1, 3'b011, 7'b0100011));        // sd    x5, 0(x1)
        emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd6));                 // csrr  x6, scause
        emit(enc_s(12'sd8, 5'd6, 5'd1, 3'b011, 7'b0100011));        // sd    x6, 8(x1)
        emit(32'h1020_0073);                                        // sret

        pcw = 48;
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd8));                 // csrr  x8, mcause
        emit(enc_s(12'sd40, 5'd8, 5'd1, 3'b011, 7'b0100011));       // sd    x8, 40(x1)
        emit(32'h0010_0073);                                        // ebreak

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 400 && dbg_state[3:0] != 4'd11; cycle++) begin
            @(posedge clk);
        end
        if (dbg_state[3:0] != 4'd11) begin
            $fatal(1, "ZX64 S-timer test did not enter WFI pc=%016x instr=%08x state=%08x",
                   dbg_pc, dbg_instr, dbg_state);
        end
        irq_timer = 1'b1;
        repeat (4) @(posedge clk);
        irq_timer = 1'b0;

        for (int cycle = 0; cycle < 600 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 S-timer interrupt test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(224, 64'h0000_0000_0000_0044, "S timer sepc");
        expect64(225, 64'h8000_0000_0000_0005, "S timer scause");
        expect64(226, 64'h0000_0000_0000_0020, "S timer sip");
        expect64(227, 64'h0000_0000_0000_0037, "S timer return");
        expect64(229, 64'h0000_0000_0000_0000, "S timer unexpected M trap");

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

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 2000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 U-mode Sv39 test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(96, 64'h0000_0000_0000_100c, "U ecall sepc");
        expect64(97, 64'h0000_0000_0000_0008, "U ecall scause");
        expect64(100, 64'h0000_0000_0000_0000, "U unexpected M trap mtval");
        expect64(101, 64'h0000_0000_0000_0000, "U unexpected M trap mepc");
        expect64(99, 64'h0000_0000_0000_0000, "U unexpected M trap");
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

        reset_vector = 64'd0;
        soft_reset = 1'b0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 2000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 Sv39 SUM/MXR test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
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

        $display("tb_zx64_core: PASS");
        $finish;
    end
endmodule
