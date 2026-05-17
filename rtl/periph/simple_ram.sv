module simple_ram #(
    parameter int WORDS = 1024
) (
    input  logic        clk,

    input  logic        imem_valid,
    input  logic [31:0] imem_addr,
    output logic        imem_ready,
    output logic [31:0] imem_rdata,

    input  logic        dmem_valid,
    input  logic        dmem_we,
    input  logic [3:0]  dmem_wstrb,
    input  logic [31:0] dmem_addr,
    input  logic [31:0] dmem_wdata,
    output logic        dmem_ready,
    output logic [31:0] dmem_rdata
);
    localparam int ADDR_BITS = $clog2(WORDS);

    logic [31:0] mem [0:WORDS-1];
    logic        imem_pending = 1'b0;
    logic        dmem_pending = 1'b0;
    integer      init_i;

    initial begin
        for (init_i = 0; init_i < WORDS; init_i = init_i + 1) begin
            mem[init_i] = 32'd0;
        end

        // Boot ROM: wait for a PS-written mailbox in TX scratch, then make the
        // PL CPU program DataMover for DDR->RX scratch, copy RX->TX, TX->DDR.
        mem[0]  = 32'h1002_00b7; // lui  x1, 0x10020     ; DataMover MMIO
        mem[1]  = 32'h2001_0137; // lui  x2, 0x20010     ; TX scratch/mailbox
        mem[2]  = 32'h2000_01b7; // lui  x3, 0x20000     ; RX scratch
        mem[3]  = 32'h4350_5237; // lui  x4, 0x43505
        mem[4]  = 32'h5212_0213; // addi x4, x4, 0x521  ; start magic CPU!
        mem[5]  = 32'h1110_0293; // addi x5, x0, 0x111  ; alive/waiting
        mem[6]  = 32'h3e51_2823; // sw   x5, 1008(x2)
        mem[7]  = 32'h3e01_2283; // lw   x5, 992(x2)
        mem[8]  = 32'hfe42_9ee3; // bne  x5, x4, -4
        mem[9]  = 32'h3e41_2303; // lw   x6, 996(x2)    ; src DDR addr
        mem[10] = 32'h3e81_2383; // lw   x7, 1000(x2)   ; dst DDR addr
        mem[11] = 32'h3ec1_2403; // lw   x8, 1004(x2)   ; byte length
        mem[12] = 32'h03c0_0293; // addi x5, x0, 0x3c
        mem[13] = 32'h0050_a223; // sw   x5, 4(x1)      ; clear done/err
        mem[14] = 32'h0060_a423; // sw   x6, 8(x1)
        mem[15] = 32'h0000_a623; // sw   x0, 12(x1)
        mem[16] = 32'h0080_a823; // sw   x8, 16(x1)
        mem[17] = 32'h0010_0293; // addi x5, x0, 1
        mem[18] = 32'h0050_aa23; // sw   x5, 20(x1)     ; tag 1
        mem[19] = 32'h0050_a023; // sw   x5, 0(x1)      ; start MM2S
        mem[20] = 32'h0040_a483; // lw   x9, 4(x1)
        mem[21] = 32'h3e91_2a23; // sw   x9, 1012(x2)   ; MM2S status
        mem[22] = 32'h0104_f513; // andi x10, x9, 0x10
        mem[23] = 32'h0805_1063; // bne  x10, x0, fail
        mem[24] = 32'h0044_f513; // andi x10, x9, 0x4
        mem[25] = 32'hfe05_06e3; // beq  x10, x0, poll_mm2s
        mem[26] = 32'h0001_8593; // addi x11, x3, 0
        mem[27] = 32'h0001_0613; // addi x12, x2, 0
        mem[28] = 32'h0004_0693; // addi x13, x8, 0
        mem[29] = 32'h0000_0793; // addi x15, x0, 0
        mem[30] = 32'h0005_a703; // lw   x14, 0(x11)
        mem[31] = 32'h00e6_2023; // sw   x14, 0(x12)
        mem[32] = 32'h0045_8593; // addi x11, x11, 4
        mem[33] = 32'h0046_0613; // addi x12, x12, 4
        mem[34] = 32'hffc6_8693; // addi x13, x13, -4
        mem[35] = 32'h0017_8793; // addi x15, x15, 1
        mem[36] = 32'hfe06_94e3; // bne  x13, x0, copy_loop
        mem[37] = 32'h3ef1_2e23; // sw   x15, 1020(x2)  ; copied words
        mem[38] = 32'h03c0_0293; // addi x5, x0, 0x3c
        mem[39] = 32'h0050_a223; // sw   x5, 4(x1)
        mem[40] = 32'h0070_a423; // sw   x7, 8(x1)
        mem[41] = 32'h0000_a623; // sw   x0, 12(x1)
        mem[42] = 32'h0080_a823; // sw   x8, 16(x1)
        mem[43] = 32'h0020_0293; // addi x5, x0, 2
        mem[44] = 32'h0050_aa23; // sw   x5, 20(x1)     ; tag 2
        mem[45] = 32'h0050_a023; // sw   x5, 0(x1)      ; start S2MM
        mem[46] = 32'h0040_a483; // lw   x9, 4(x1)
        mem[47] = 32'h3e91_2c23; // sw   x9, 1016(x2)   ; S2MM status
        mem[48] = 32'h0204_f513; // andi x10, x9, 0x20
        mem[49] = 32'h0005_1c63; // bne  x10, x0, fail
        mem[50] = 32'h0084_f513; // andi x10, x9, 0x8
        mem[51] = 32'hfe05_06e3; // beq  x10, x0, poll_s2mm
        mem[52] = 32'h2220_0293; // addi x5, x0, 0x222  ; pass
        mem[53] = 32'h3e51_2823; // sw   x5, 1008(x2)
        mem[54] = 32'h0000_006f; // jal  x0, 0
        mem[55] = 32'h3330_0293; // addi x5, x0, 0x333  ; fail
        mem[56] = 32'h3e51_2823; // sw   x5, 1008(x2)
        mem[57] = 32'h0000_006f; // jal  x0, 0
    end

    assign imem_ready = imem_pending;
    assign dmem_ready = dmem_pending;

    always_ff @(posedge clk) begin
        if (imem_pending) begin
            imem_pending <= 1'b0;
        end else if (imem_valid) begin
            imem_rdata <= mem[imem_addr[ADDR_BITS+1:2]];
            imem_pending <= 1'b1;
        end

        if (dmem_pending) begin
            dmem_pending <= 1'b0;
        end else if (dmem_valid) begin
            dmem_rdata <= mem[dmem_addr[ADDR_BITS+1:2]];
            if (dmem_we) begin
                if (dmem_wstrb[0]) mem[dmem_addr[ADDR_BITS+1:2]][7:0]   <= dmem_wdata[7:0];
                if (dmem_wstrb[1]) mem[dmem_addr[ADDR_BITS+1:2]][15:8]  <= dmem_wdata[15:8];
                if (dmem_wstrb[2]) mem[dmem_addr[ADDR_BITS+1:2]][23:16] <= dmem_wdata[23:16];
                if (dmem_wstrb[3]) mem[dmem_addr[ADDR_BITS+1:2]][31:24] <= dmem_wdata[31:24];
            end
            dmem_pending <= 1'b1;
        end
    end
endmodule
