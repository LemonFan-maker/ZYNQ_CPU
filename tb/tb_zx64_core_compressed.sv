module tb_zx64_core_compressed;
    localparam int IMEM_WORDS = 128;
    localparam int DMEM_WORDS = 256;

    logic clk;
    logic rst_n;
    logic soft_reset;
    logic irq_timer;
    logic irq_external;
    logic [63:0] reset_vector;

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
    integer pch;

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

    function automatic logic [31:0] enc_i(input logic signed [11:0] imm,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_i = {imm[11:0], rs1, funct3, rd, opcode};
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

    function automatic logic [15:0] c_sdsp(input logic [4:0] rs2,
                                           input logic [8:0] imm);
        c_sdsp = {3'b111, imm[5:3], imm[8:6], rs2, 2'b10};
    endfunction

    function automatic logic [15:0] c_ld(input logic [2:0] rd,
                                         input logic [2:0] rs1,
                                         input logic [7:0] imm);
        c_ld = {3'b011, imm[5:3], rs1, imm[7:6], rd, 2'b00};
    endfunction

    function automatic logic [15:0] c_sd(input logic [2:0] rs2,
                                         input logic [2:0] rs1,
                                         input logic [7:0] imm);
        c_sd = {3'b111, imm[5:3], rs1, imm[7:6], rs2, 2'b00};
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

    initial begin
        rst_n = 1'b0;
        soft_reset = 1'b0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        reset_vector = 64'd0;

        for (int i = 0; i < IMEM_WORDS; i++) begin
            imem[i] = 32'h0010_0073;
        end
        for (int i = 0; i < DMEM_WORDS; i++) begin
            dmem[i] = 64'd0;
        end

        pch = 0;
        emit16(c_addi(5'd0, 6'sd0));                                      // c.nop
        emit32(enc_i(12'sd0, 5'd0, 3'b000, 5'd2, 7'b0010011));             // addi x2, x0, 0
        emit16(c_addi16sp(10'sd64));                                       // sp = 64
        emit16(c_li(5'd8, 6'sd11));                                        // x8 = 11
        emit16(c_sdsp(5'd8, 9'd0));                                        // [sp+0] = 11
        emit16(c_ldsp(5'd9, 9'd0));                                        // x9 = [sp+0]
        emit16(c_addi4spn(3'd2, 10'd16));                                  // x10 = sp + 16
        emit16(c_sd(3'd1, 3'd2, 8'd0));                                    // [x10] = x9
        emit16(c_ld(3'd3, 3'd2, 8'd0));                                    // x11 = [x10]
        emit16(c_sdsp(5'd11, 9'd8));                                       // [sp+8] = x11
        emit16(c_addiw(5'd11, 6'sd1));                                     // x11 = 12
        emit16(c_slli(5'd11, 6'd1));                                       // x11 = 24
        emit16(c_srli(3'd3, 6'd1));                                        // x11 = 12
        emit16(c_andi(3'd3, 6'sd15));                                      // x11 = 12
        emit16(c_sdsp(5'd11, 9'd24));                                      // [sp+24] = 12
        emit16(c_li(5'd12, 6'sd0));
        emit16(c_beqz(3'd4, 9'sd4));                                       // skip next c.li
        emit16(c_li(5'd13, 6'sd1));
        emit16(c_li(5'd13, 6'sd2));
        emit16(c_sdsp(5'd13, 9'd32));
        emit16(c_li(5'd14, 6'sd1));
        emit16(c_bnez(3'd6, 9'sd4));                                       // skip next c.li
        emit16(c_li(5'd15, 6'sd3));
        emit16(c_li(5'd15, 6'sd4));
        emit16(c_sdsp(5'd15, 9'd40));
        emit16(c_j(12'sd4));                                               // skip next c.li
        emit16(c_li(5'd15, 6'sd5));
        emit16(c_sdsp(5'd15, 9'd48));
        emit16(c_ebreak());

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 1000 && !halted; cycle++) begin
            @(posedge clk);
        end

        if (!halted || illegal_instr) begin
            $fatal(1, "ZX64 compressed test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   halted, illegal_instr, dbg_pc, dbg_instr, dbg_state);
        end

        expect64(8, 64'd11, "c.sdsp");
        expect64(9, 64'd11, "c.ldsp/c.sdsp");
        expect64(10, 64'd11, "c.addi4spn/c.sd/c.ld");
        expect64(11, 64'd12, "compressed arithmetic");
        expect64(12, 64'd2, "c.beqz");
        expect64(13, 64'd4, "c.bnez");
        expect64(14, 64'd4, "c.j");

        $display("tb_zx64_core_compressed: PASS");
        $finish;
    end
endmodule
