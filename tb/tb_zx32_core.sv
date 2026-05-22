module tb_zx32_core;
    localparam int SV32_ROOT_IDX = 1024;
    localparam int SV32_L0_IDX = 2048;
    localparam int SV32_CODE_IDX = 3072;
    localparam int SV32_DATA_IDX = 4096;
    localparam int SV32_NEW_DATA_IDX = 5120;

    logic clk;
    logic rst_n;
    logic [31:0] reset_vector;
    logic        irq_timer;
    logic        irq_external;

    logic        imem_valid;
    logic [31:0] imem_addr;
    logic        imem_ready;
    logic [31:0] imem_rdata;
    logic        dmem_valid;
    logic        dmem_we;
    logic [3:0]  dmem_wstrb;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic        dmem_ready;
    logic [31:0] dmem_rdata;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    zx32_core u_core (
        .clk(clk),
        .rst_n(rst_n),
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
        .dmem_rdata(dmem_rdata)
    );

    simple_ram #(.WORDS(8192)) u_ram (
        .clk(clk),
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
        .dmem_rdata(dmem_rdata)
    );

    initial begin
        bit super_asid1_valid;
        bit super_asid2_valid;

        reset_vector = 32'd0;
        irq_external = 1'b0;

        u_ram.mem[0]  = 32'h0400_0093; // addi x1, x0, 64
        u_ram.mem[1]  = 32'hfff0_0113; // addi x2, x0, -1
        u_ram.mem[2]  = 32'h0020_a023; // sw   x2, 0(x1)
        u_ram.mem[3]  = 32'h0000_c183; // lbu  x3, 0(x1)
        u_ram.mem[4]  = 32'h0030_a223; // sw   x3, 4(x1)
        u_ram.mem[5]  = 32'h0000_8203; // lb   x4, 0(x1)
        u_ram.mem[6]  = 32'h0040_a423; // sw   x4, 8(x1)
        u_ram.mem[7]  = 32'h07f0_0293; // addi x5, x0, 127
        u_ram.mem[8]  = 32'h0050_80a3; // sb   x5, 1(x1)
        u_ram.mem[9]  = 32'h0000_d303; // lhu  x6, 0(x1)
        u_ram.mem[10] = 32'h0060_a623; // sw   x6, 12(x1)
        u_ram.mem[11] = 32'hf800_0393; // addi x7, x0, -128
        u_ram.mem[12] = 32'h0070_8123; // sb   x7, 2(x1)
        u_ram.mem[13] = 32'h0020_8403; // lb   x8, 2(x1)
        u_ram.mem[14] = 32'h0080_a823; // sw   x8, 16(x1)
        u_ram.mem[15] = 32'h0000_006f; // jal  x0, 0

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (180) @(posedge clk);

        if (u_ram.mem[16] !== 32'hff80_7fff) begin
            $fatal(1, "expected mem[16] = ff807fff, got %08x", u_ram.mem[16]);
        end
        if (u_ram.mem[17] !== 32'h0000_00ff) begin
            $fatal(1, "expected mem[17] = 000000ff, got %08x", u_ram.mem[17]);
        end
        if (u_ram.mem[18] !== 32'hffff_ffff) begin
            $fatal(1, "expected mem[18] = ffffffff, got %08x", u_ram.mem[18]);
        end
        if (u_ram.mem[19] !== 32'h0000_7fff) begin
            $fatal(1, "expected mem[19] = 00007fff, got %08x", u_ram.mem[19]);
        end
        if (u_ram.mem[20] !== 32'hffff_ff80) begin
            $fatal(1, "expected mem[20] = ffffff80, got %08x", u_ram.mem[20]);
        end

        u_ram.mem[0]  = 32'h0400_0093; // addi x1, x0, 64
        u_ram.mem[1]  = 32'h0440_0113; // addi x2, x0, 68
        u_ram.mem[2]  = 32'h0020_820b; // xcpyw x4, x1, x2
        u_ram.mem[3]  = 32'h0000_006f; // jal  x0, 0
        u_ram.mem[16] = 32'h1234_5678;
        u_ram.mem[17] = 32'h0000_0000;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (60) @(posedge clk);

        if (u_ram.mem[17] !== 32'h1234_5678) begin
            $fatal(1, "expected mem[17] = 12345678, got %08x", u_ram.mem[17]);
        end
        if (u_core.u_regfile.regs[4] !== 32'h1234_5678) begin
            $fatal(1, "expected x4 = 12345678, got %08x", u_core.u_regfile.regs[4]);
        end

        u_ram.mem[0]  = 32'h0000_006f; // jal  x0, 0
        u_ram.mem[1]  = 32'h0500_0093; // addi x1, x0, 80
        u_ram.mem[2]  = 32'h05a0_0113; // addi x2, x0, 0x5a
        u_ram.mem[3]  = 32'h0020_a023; // sw   x2, 0(x1)
        u_ram.mem[4]  = 32'h0000_006f; // jal  x0, 0
        u_ram.mem[20] = 32'h0000_0000;

        reset_vector = 32'd4;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (60) @(posedge clk);

        if (u_ram.mem[20] !== 32'h0000_005a) begin
            $fatal(1, "expected reset-vector mem[20] = 0000005a, got %08x", u_ram.mem[20]);
        end

        u_ram.mem[0]  = 32'h0200_0093; // addi x1, x0, 0x20
        u_ram.mem[1]  = 32'h0000_0293; // addi x5, x0, 0
        u_ram.mem[2]  = 32'h3050_9073; // csrw mtvec, x1
        u_ram.mem[3]  = 32'h0000_0073; // ecall
        u_ram.mem[4]  = 32'h0990_0313; // addi x6, x0, 0x99
        u_ram.mem[5]  = 32'h0460_2a23; // sw   x6, 84(x0)
        u_ram.mem[6]  = 32'h0240_006f; // j    done
        u_ram.mem[7]  = 32'h0000_0000;
        u_ram.mem[8]  = 32'h3410_2173; // csrr x2, mepc
        u_ram.mem[9]  = 32'h0420_2823; // sw   x2, 80(x0)
        u_ram.mem[10] = 32'h3420_21f3; // csrr x3, mcause
        u_ram.mem[11] = 32'h0430_2c23; // sw   x3, 88(x0)
        u_ram.mem[12] = 32'h0041_0113; // addi x2, x2, 4
        u_ram.mem[13] = 32'h3411_1073; // csrw mepc, x2
        u_ram.mem[14] = 32'h3020_0073; // mret
        u_ram.mem[15] = 32'h0000_006f; // done: j done
        u_ram.mem[20] = 32'h0000_0000;
        u_ram.mem[21] = 32'h0000_0000;
        u_ram.mem[22] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (120) @(posedge clk);

        if (u_ram.mem[20] !== 32'h0000_000c) begin
            $fatal(1, "expected mepc save mem[20] = 0000000c, got %08x pc=%08x mtvec=%08x mepc=%08x mcause=%08x x1=%08x",
                   u_ram.mem[20], u_core.pc, u_core.csr_mtvec, u_core.csr_mepc,
                   u_core.csr_mcause, u_core.u_regfile.regs[1]);
        end
        if (u_ram.mem[21] !== 32'h0000_0099) begin
            $fatal(1, "expected trap-return mem[21] = 00000099, got %08x", u_ram.mem[21]);
        end
        if (u_ram.mem[22] !== 32'h0000_000b) begin
            $fatal(1, "expected mcause save mem[22] = 0000000b, got %08x", u_ram.mem[22]);
        end

        u_ram.mem[0]  = 32'h0400_0093; // li   x1, 64
        u_ram.mem[1]  = 32'h1050_9073; // csrw stvec, x1
        u_ram.mem[2]  = 32'h2000_0093; // li   x1, 512
        u_ram.mem[3]  = 32'h3020_9073; // csrw medeleg, x1
        u_ram.mem[4]  = 32'h0280_0093; // li   x1, 40
        u_ram.mem[5]  = 32'h3410_9073; // csrw mepc, x1
        u_ram.mem[6]  = 32'h0000_10b7; // lui  x1, 1
        u_ram.mem[7]  = 32'h8000_8093; // addi x1, x1, -2048
        u_ram.mem[8]  = 32'h3000_9073; // csrw mstatus, x1
        u_ram.mem[9]  = 32'h3020_0073; // mret
        u_ram.mem[10] = 32'h0000_0073; // ecall
        u_ram.mem[11] = 32'h0550_0313; // addi x6, x0, 0x55
        u_ram.mem[12] = 32'h1060_2423; // sw   x6, 264(x0)
        u_ram.mem[13] = 32'h0000_006f; // j    0
        u_ram.mem[14] = 32'h0000_0000;
        u_ram.mem[15] = 32'h0000_0000;
        u_ram.mem[16] = 32'h1410_2173; // csrr x2, sepc
        u_ram.mem[17] = 32'h1020_2023; // sw   x2, 256(x0)
        u_ram.mem[18] = 32'h1420_21f3; // csrr x3, scause
        u_ram.mem[19] = 32'h1030_2223; // sw   x3, 260(x0)
        u_ram.mem[20] = 32'h0041_0113; // addi x2, x2, 4
        u_ram.mem[21] = 32'h1411_1073; // csrw sepc, x2
        u_ram.mem[22] = 32'h1020_0073; // sret
        u_ram.mem[64] = 32'h0000_0000;
        u_ram.mem[65] = 32'h0000_0000;
        u_ram.mem[66] = 32'h0000_0000;

        reset_vector = 32'd0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (180) @(posedge clk);

        if (u_ram.mem[64] !== 32'h0000_0028) begin
            $fatal(1, "expected sepc save mem[64] = 00000028, got %08x pc=%08x priv=%0d stvec=%08x sepc=%08x scause=%08x",
                   u_ram.mem[64], u_core.pc, u_core.current_priv, u_core.csr_stvec,
                   u_core.csr_sepc, u_core.csr_scause);
        end
        if (u_ram.mem[65] !== 32'h0000_0009) begin
            $fatal(1, "expected scause save mem[65] = 00000009, got %08x", u_ram.mem[65]);
        end
        if (u_ram.mem[66] !== 32'h0000_0055) begin
            $fatal(1, "expected sret-return mem[66] = 00000055, got %08x", u_ram.mem[66]);
        end

        u_ram.mem[0]  = 32'h0500_0093; // addi x1, x0, 0x50
        u_ram.mem[1]  = 32'h1050_9073; // csrw stvec, x1
        u_ram.mem[2]  = 32'h0200_0113; // addi x2, x0, 0x20
        u_ram.mem[3]  = 32'h3031_1073; // csrw mideleg, x2
        u_ram.mem[4]  = 32'h0000_10b7; // lui  x1, 1
        u_ram.mem[5]  = 32'h8000_8093; // addi x1, x1, -2048
        u_ram.mem[6]  = 32'h3000_9073; // csrw mstatus, x1
        u_ram.mem[7]  = 32'h0280_0193; // addi x3, x0, 0x28
        u_ram.mem[8]  = 32'h3411_9073; // csrw mepc, x3
        u_ram.mem[9]  = 32'h3020_0073; // mret
        u_ram.mem[10] = 32'h0200_0113; // addi x2, x0, 0x20
        u_ram.mem[11] = 32'h1041_1073; // csrw sie, x2
        u_ram.mem[12] = 32'h1020_0193; // addi x3, x0, 0x102
        u_ram.mem[13] = 32'h1001_9073; // csrw sstatus, x3
        u_ram.mem[14] = 32'h0000_006f; // j    0
        u_ram.mem[15] = 32'h05a0_0313; // addi x6, x0, 0x5a
        u_ram.mem[16] = 32'h0a60_2423; // sw   x6, 168(x0)
        u_ram.mem[17] = 32'h0000_006f; // j    0
        u_ram.mem[20] = 32'h1420_21f3; // csrr x3, scause
        u_ram.mem[21] = 32'h0a30_2023; // sw   x3, 160(x0)
        u_ram.mem[22] = 32'h1410_2273; // csrr x4, sepc
        u_ram.mem[23] = 32'h0a40_2223; // sw   x4, 164(x0)
        u_ram.mem[24] = 32'h0042_0213; // addi x4, x4, 4
        u_ram.mem[25] = 32'h1412_1073; // csrw sepc, x4
        u_ram.mem[26] = 32'h1000_0293; // addi x5, x0, 0x100
        u_ram.mem[27] = 32'h1002_9073; // csrw sstatus, x5
        u_ram.mem[28] = 32'h1020_0073; // sret
        u_ram.mem[40] = 32'h0000_0000;
        u_ram.mem[41] = 32'h0000_0000;
        u_ram.mem[42] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (20) @(posedge clk);
        irq_timer = 1'b1;

        repeat (240) @(posedge clk);

        if (u_ram.mem[40] !== 32'h8000_0005) begin
            $fatal(1, "expected S-mode timer scause mem[40] = 80000005, got %08x pc=%08x priv=%0d mstatus=%08x mideleg=%08x sie=%08x mip=%08x",
                   u_ram.mem[40], u_core.pc, u_core.current_priv, u_core.csr_mstatus,
                   u_core.csr_mideleg, u_core.csr_sie, u_core.csr_mip);
        end
        if (u_ram.mem[41] !== 32'h0000_0038) begin
            $fatal(1, "expected S-mode timer sepc mem[41] = 00000038, got %08x", u_ram.mem[41]);
        end
        if (u_ram.mem[42] !== 32'h0000_005a) begin
            $fatal(1, "expected S-mode timer marker mem[42] = 0000005a, got %08x", u_ram.mem[42]);
        end
        if (u_core.current_priv !== 2'b01) begin
            $fatal(1, "expected to return to S-mode after timer trap, priv=%0d", u_core.current_priv);
        end

        u_ram.mem[0]  = 32'h0400_0093; // addi x1, x0, 64
        u_ram.mem[1]  = 32'h1050_9073; // csrw stvec, x1
        u_ram.mem[2]  = 32'h2000_0093; // addi x1, x0, 0x200
        u_ram.mem[3]  = 32'h3030_9073; // csrw mideleg, x1
        u_ram.mem[4]  = 32'h1040_9073; // csrw sie, x1
        u_ram.mem[5]  = 32'h0000_10b7; // lui  x1, 1
        u_ram.mem[6]  = 32'h8000_8093; // addi x1, x1, -2048
        u_ram.mem[7]  = 32'h3000_9073; // csrw mstatus, x1
        u_ram.mem[8]  = 32'h02c0_0193; // addi x3, x0, 0x2c
        u_ram.mem[9]  = 32'h3411_9073; // csrw mepc, x3
        u_ram.mem[10] = 32'h3020_0073; // mret
        u_ram.mem[11] = 32'h0020_0093; // addi x1, x0, 2
        u_ram.mem[12] = 32'h1000_9073; // csrw sstatus, x1
        u_ram.mem[13] = 32'h0000_006f; // j    0
        u_ram.mem[16] = 32'h1420_2173; // csrr x2, scause
        u_ram.mem[17] = 32'h0c20_2023; // sw   x2, 192(x0)
        u_ram.mem[18] = 32'h05a0_0193; // addi x3, x0, 0x5a
        u_ram.mem[19] = 32'h0c30_2223; // sw   x3, 196(x0)
        u_ram.mem[20] = 32'h0000_006f; // j    0
        u_ram.mem[48] = 32'h0000_0000;
        u_ram.mem[49] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (40) @(posedge clk);
        irq_external = 1'b1;
        repeat (80) @(posedge clk);
        irq_external = 1'b0;

        repeat (160) @(posedge clk);

        if (u_ram.mem[48] !== 32'h8000_0009) begin
            $fatal(1, "expected S-mode external scause mem[48] = 80000009, got %08x pc=%08x priv=%0d mideleg=%08x sie=%08x sip=%08x",
                   u_ram.mem[48], u_core.pc, u_core.current_priv, u_core.csr_mideleg,
                   u_core.csr_sie, u_core.csr_sip_view);
        end
        if (u_ram.mem[49] !== 32'h0000_005a) begin
            $fatal(1, "expected S-mode external marker mem[49] = 0000005a, got %08x", u_ram.mem[49]);
        end

        u_ram.mem[0]  = 32'h8000_00b7; // lui  x1, 0x80000
        u_ram.mem[1]  = 32'h0010_8093; // addi x1, x1, 1
        u_ram.mem[2]  = 32'h1800_9073; // csrw satp, x1
        u_ram.mem[3]  = 32'h0000_10b7; // lui  x1, 0x1
        u_ram.mem[4]  = 32'h8000_8093; // addi x1, x1, -2048
        u_ram.mem[5]  = 32'h3000_9073; // csrw mstatus, x1
        u_ram.mem[6]  = 32'h4000_01b7; // lui  x3, 0x40000
        u_ram.mem[7]  = 32'h3411_9073; // csrw mepc, x3
        u_ram.mem[8]  = 32'h3020_0073; // mret

        u_ram.mem[SV32_ROOT_IDX + 256] = (32'd2 << 10) | 32'h001;
        u_ram.mem[SV32_L0_IDX + 0] = (32'd3 << 10) | 32'h00B;
        u_ram.mem[SV32_L0_IDX + 1] = (32'd4 << 10) | 32'h007;

        u_ram.mem[SV32_CODE_IDX + 0] = 32'h4000_10b7; // lui  x1, 0x40001
        u_ram.mem[SV32_CODE_IDX + 1] = 32'h1234_5137; // lui  x2, 0x12345
        u_ram.mem[SV32_CODE_IDX + 2] = 32'h6781_0113; // addi x2, x2, 0x678
        u_ram.mem[SV32_CODE_IDX + 3] = 32'h0020_a023; // sw   x2, 0(x1)
        u_ram.mem[SV32_CODE_IDX + 4] = 32'h0000_a183; // lw   x3, 0(x1)
        u_ram.mem[SV32_CODE_IDX + 5] = 32'h0030_a223; // sw   x3, 4(x1)
        u_ram.mem[SV32_CODE_IDX + 6] = 32'h0000_006f; // j    0

        u_ram.mem[SV32_DATA_IDX + 0] = 32'h0000_0000;
        u_ram.mem[SV32_DATA_IDX + 1] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (400) @(posedge clk);

        if (u_ram.mem[SV32_DATA_IDX + 0] !== 32'h1234_5678) begin
            $fatal(1, "expected Sv32 store mem[4096] = 12345678, got %08x pc=%08x priv=%0d satp=%08x state=%0d req=%0d pa=%0d pf=%0d pte=%08x l1=%08x l0=%08x mcause=%08x mtval=%08x mepc=%08x scause=%08x stval=%08x root=%08x l0mem=%08x code0=%08x code1=%08x",
                   u_ram.mem[SV32_DATA_IDX + 0], u_core.pc, u_core.current_priv, u_core.csr_satp,
                   u_core.state, u_core.req_active, u_core.req_pa_valid, u_core.page_fault_pending,
                   u_core.ptw_pte_addr, u_core.ptw_l1_pte, u_core.ptw_l0_pte,
                   u_core.csr_mcause, u_core.csr_mtval, u_core.csr_mepc, u_core.csr_scause, u_core.csr_stval,
                   u_ram.mem[SV32_ROOT_IDX + 256], u_ram.mem[SV32_L0_IDX + 0],
                   u_ram.mem[SV32_CODE_IDX + 0], u_ram.mem[SV32_CODE_IDX + 1]);
        end
        if (u_ram.mem[SV32_DATA_IDX + 1] !== 32'h1234_5678) begin
            $fatal(1, "expected Sv32 load/store mem[4097] = 12345678, got %08x pc=%08x priv=%0d satp=%08x state=%0d req=%0d pa=%0d pf=%0d pte=%08x l1=%08x l0=%08x mcause=%08x mtval=%08x mepc=%08x scause=%08x stval=%08x",
                   u_ram.mem[SV32_DATA_IDX + 1], u_core.pc, u_core.current_priv, u_core.csr_satp,
                   u_core.state, u_core.req_active, u_core.req_pa_valid, u_core.page_fault_pending,
                   u_core.ptw_pte_addr, u_core.ptw_l1_pte, u_core.ptw_l0_pte,
                   u_core.csr_mcause, u_core.csr_mtval, u_core.csr_mepc, u_core.csr_scause, u_core.csr_stval);
        end
        if (u_ram.mem[SV32_L0_IDX + 0] !== 32'h0000_0c4b) begin
            $fatal(1, "expected Sv32 code PTE A-bit update mem[%0d] = 00000c4b, got %08x",
                   SV32_L0_IDX + 0, u_ram.mem[SV32_L0_IDX + 0]);
        end
        if (u_ram.mem[SV32_L0_IDX + 1] !== 32'h0000_10c7) begin
            $fatal(1, "expected Sv32 data PTE A/D update mem[%0d] = 000010c7, got %08x",
                   SV32_L0_IDX + 1, u_ram.mem[SV32_L0_IDX + 1]);
        end
        if (u_core.current_priv !== 2'b01) begin
            $fatal(1, "expected to remain in S-mode after Sv32 smoke, priv=%0d", u_core.current_priv);
        end

        u_ram.mem[0]  = 32'h8000_00b7; // lui  x1, 0x80000
        u_ram.mem[1]  = 32'h0010_8093; // addi x1, x1, 1
        u_ram.mem[2]  = 32'h1800_9073; // csrw satp, x1
        u_ram.mem[3]  = 32'h0000_10b7; // lui  x1, 0x1
        u_ram.mem[4]  = 32'h8000_8093; // addi x1, x1, -2048
        u_ram.mem[5]  = 32'h3000_9073; // csrw mstatus, x1
        u_ram.mem[6]  = 32'h4000_01b7; // lui  x3, 0x40000
        u_ram.mem[7]  = 32'h3411_9073; // csrw mepc, x3
        u_ram.mem[8]  = 32'h3020_0073; // mret

        u_ram.mem[SV32_ROOT_IDX + 256] = (32'd2 << 10) | 32'h001;
        u_ram.mem[SV32_L0_IDX + 0] = (32'd3 << 10) | 32'h00B;
        u_ram.mem[SV32_L0_IDX + 1] = (32'd4 << 10) | 32'h007;
        u_ram.mem[SV32_L0_IDX + 2] = (32'd2 << 10) | 32'h007;

        u_ram.mem[SV32_CODE_IDX + 0] = 32'h4000_10b7; // lui  x1, 0x40001
        u_ram.mem[SV32_CODE_IDX + 1] = 32'haaaa_5137; // lui  x2, 0xaaaa5
        u_ram.mem[SV32_CODE_IDX + 2] = 32'h5551_0113; // addi x2, x2, 0x555
        u_ram.mem[SV32_CODE_IDX + 3] = 32'h0020_a023; // sw   x2, 0(x1)
        u_ram.mem[SV32_CODE_IDX + 4] = 32'h4000_21b7; // lui  x3, 0x40002
        u_ram.mem[SV32_CODE_IDX + 5] = 32'h0000_12b7; // lui  x5, 0x1
        u_ram.mem[SV32_CODE_IDX + 6] = 32'h4c72_8293; // addi x5, x5, 0x4c7
        u_ram.mem[SV32_CODE_IDX + 7] = 32'h0051_a223; // sw   x5, 4(x3)
        u_ram.mem[SV32_CODE_IDX + 8] = 32'h1200_0073; // sfence.vma
        u_ram.mem[SV32_CODE_IDX + 9] = 32'h1234_5137; // lui  x2, 0x12345
        u_ram.mem[SV32_CODE_IDX + 10] = 32'h6781_0113; // addi x2, x2, 0x678
        u_ram.mem[SV32_CODE_IDX + 11] = 32'h0020_a023; // sw   x2, 0(x1)
        u_ram.mem[SV32_CODE_IDX + 12] = 32'h0000_a303; // lw   x6, 0(x1)
        u_ram.mem[SV32_CODE_IDX + 13] = 32'h0060_a423; // sw   x6, 8(x1)
        u_ram.mem[SV32_CODE_IDX + 14] = 32'h0000_006f; // j    0

        u_ram.mem[SV32_DATA_IDX + 0] = 32'h0000_0000;
        u_ram.mem[SV32_NEW_DATA_IDX + 0] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (500) @(posedge clk);

        if (u_ram.mem[SV32_DATA_IDX + 0] !== 32'haaaa_5555) begin
            $fatal(1, "expected Sv32 old page mem[%0d] = aaaa5555, got %08x pc=%08x priv=%0d satp=%08x state=%0d pte=%08x",
                   SV32_DATA_IDX, u_ram.mem[SV32_DATA_IDX + 0], u_core.pc, u_core.current_priv,
                   u_core.csr_satp, u_core.state, u_ram.mem[SV32_L0_IDX + 1]);
        end
        if (u_ram.mem[SV32_NEW_DATA_IDX + 0] !== 32'h1234_5678) begin
            $fatal(1, "expected Sv32 new page mem[%0d] = 12345678, got %08x pc=%08x priv=%0d satp=%08x state=%0d pte=%08x",
                   SV32_NEW_DATA_IDX, u_ram.mem[SV32_NEW_DATA_IDX + 0], u_core.pc, u_core.current_priv,
                   u_core.csr_satp, u_core.state, u_ram.mem[SV32_L0_IDX + 1]);
        end
        if (u_ram.mem[SV32_L0_IDX + 1] !== 32'h0000_14c7) begin
            $fatal(1, "expected updated PTE mem[%0d] = 000014c7, got %08x",
                   SV32_L0_IDX + 1, u_ram.mem[SV32_L0_IDX + 1]);
        end
        if (u_core.current_priv !== 2'b01) begin
            $fatal(1, "expected to remain in S-mode after TLB smoke, priv=%0d", u_core.current_priv);
        end

        u_ram.mem[0]  = 32'h8040_00b7; // lui  x1, 0x80400
        u_ram.mem[1]  = 32'h0010_8093; // addi x1, x1, 1
        u_ram.mem[2]  = 32'h1800_9073; // csrw satp, x1 (ASID=1, PPN=1)
        u_ram.mem[3]  = 32'h0000_10b7; // lui  x1, 0x1
        u_ram.mem[4]  = 32'h8000_8093; // addi x1, x1, -2048
        u_ram.mem[5]  = 32'h3000_9073; // csrw mstatus, x1
        u_ram.mem[6]  = 32'h4000_01b7; // lui  x3, 0x40000
        u_ram.mem[7]  = 32'h0401_8193; // addi x3, x3, 0x40
        u_ram.mem[8]  = 32'h3411_9073; // csrw mepc, x3
        u_ram.mem[9]  = 32'h3020_0073; // mret

        u_ram.mem[16] = 32'h4000_50b7; // lui  x1, 0x40005
        u_ram.mem[17] = 32'h1111_1137; // lui  x2, 0x11111
        u_ram.mem[18] = 32'h1111_0113; // addi x2, x2, 0x111
        u_ram.mem[19] = 32'h0020_a023; // sw   x2, 0(x1)
        u_ram.mem[20] = 32'h8080_0237; // lui  x4, 0x80800
        u_ram.mem[21] = 32'h0012_0213; // addi x4, x4, 1
        u_ram.mem[22] = 32'h1802_1073; // csrw satp, x4 (ASID=2, PPN=1)
        u_ram.mem[23] = 32'h2222_2137; // lui  x2, 0x22222
        u_ram.mem[24] = 32'h2221_0113; // addi x2, x2, 0x222
        u_ram.mem[25] = 32'h0020_a023; // sw   x2, 0(x1)
        u_ram.mem[26] = 32'h0010_0393; // addi x7, x0, 1
        u_ram.mem[27] = 32'h1270_0073; // sfence.vma x0, x7
        u_ram.mem[28] = 32'h0000_006f; // j    0

        u_ram.mem[SV32_ROOT_IDX + 256] = 32'h0000_00cf;
        u_ram.mem[SV32_NEW_DATA_IDX + 0] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (500) @(posedge clk);

        if (u_ram.mem[SV32_NEW_DATA_IDX + 0] !== 32'h2222_2222) begin
            $fatal(1, "expected superpage data mem[%0d] = 22222222, got %08x pc=%08x priv=%0d satp=%08x state=%0d mcause=%08x mtval=%08x mepc=%08x scause=%08x stval=%08x sepc=%08x pte=%08x req=%0d pa=%0d pf=%0d ptaddr=%08x",
                   SV32_NEW_DATA_IDX, u_ram.mem[SV32_NEW_DATA_IDX + 0], u_core.pc, u_core.current_priv,
                   u_core.csr_satp, u_core.state, u_core.csr_mcause, u_core.csr_mtval, u_core.csr_mepc,
                   u_core.csr_scause, u_core.csr_stval, u_core.csr_sepc, u_ram.mem[SV32_ROOT_IDX + 256],
                   u_core.req_active, u_core.req_pa_valid, u_core.page_fault_pending, u_core.ptw_pte_addr);
        end
        if (u_ram.mem[SV32_ROOT_IDX + 256] !== 32'h0000_00cf) begin
            $fatal(1, "expected superpage root PTE A/D update mem[%0d] = 000000cf, got %08x",
                   SV32_ROOT_IDX + 256, u_ram.mem[SV32_ROOT_IDX + 256]);
        end

        super_asid1_valid = 1'b0;
        super_asid2_valid = 1'b0;
        for (int i = 0; i < 8; i++) begin
            if (u_core.tlb_valid[i] && u_core.tlb_superpage[i] &&
                (u_core.tlb_vpn[i][19:10] == 10'h100)) begin
                if (u_core.tlb_asid[i] == 9'd1) begin
                    super_asid1_valid = 1'b1;
                end
                if (u_core.tlb_asid[i] == 9'd2) begin
                    super_asid2_valid = 1'b1;
                end
            end
        end
        if (super_asid1_valid) begin
            $fatal(1, "expected sfence.vma x0,x7 to invalidate ASID=1 superpage TLB entry");
        end
        if (!super_asid2_valid) begin
            $fatal(1, "expected ASID=2 superpage TLB entry to survive selective sfence.vma");
        end
        if (u_core.current_priv !== 2'b01) begin
            $fatal(1, "expected to remain in S-mode after superpage TLB smoke, priv=%0d", u_core.current_priv);
        end

        u_ram.mem[0]  = 32'h0800_0293; // li     x5, 128
        u_ram.mem[1]  = 32'h3052_9073; // csrw   mtvec, x5
        u_ram.mem[2]  = 32'h0000_12b7; // lui    x5, 0x1
        u_ram.mem[3]  = 32'h0002_8293; // addi   x5, x5, 0
        u_ram.mem[4]  = 32'h3022_9073; // csrw   medeleg, x5
        u_ram.mem[5]  = 32'h0000_32b7; // lui    x5, 0x3
        u_ram.mem[6]  = 32'h0002_8293; // addi   x5, x5, 0
        u_ram.mem[7]  = 32'h3412_9073; // csrw   mepc, x5
        u_ram.mem[8]  = 32'h0000_12b7; // lui    x5, 0x1
        u_ram.mem[9]  = 32'h8002_8293; // addi   x5, x5, -2048
        u_ram.mem[10] = 32'h3002_9073; // csrw   mstatus, x5
        u_ram.mem[11] = 32'h3020_0073; // mret
        u_ram.mem[12] = 32'h0000_006f; // j      0
        u_ram.mem[32] = 32'h3330_0293; // li     x5, 0x333
        u_ram.mem[33] = 32'h2050_2823; // sw     x5, 528(x0)
        u_ram.mem[34] = 32'h0000_006f; // j      0

        u_ram.mem[SV32_CODE_IDX + 0]  = 32'hc000_32b7; // lui    x5, 0xc0003
        u_ram.mem[SV32_CODE_IDX + 1]  = 32'h0402_8293; // addi   x5, x5, 0x40
        u_ram.mem[SV32_CODE_IDX + 2]  = 32'h1052_9073; // csrw   stvec, x5
        u_ram.mem[SV32_CODE_IDX + 3]  = 32'h8000_02b7; // lui    x5, 0x80000
        u_ram.mem[SV32_CODE_IDX + 4]  = 32'h0012_8293; // addi   x5, x5, 1
        u_ram.mem[SV32_CODE_IDX + 5]  = 32'h1802_9073; // csrw   satp, x5
        u_ram.mem[SV32_CODE_IDX + 6]  = 32'h0000_1337; // lui    x6, 0x1
        u_ram.mem[SV32_CODE_IDX + 7]  = 32'hbad3_0313; // addi   x6, x6, -1107
        u_ram.mem[SV32_CODE_IDX + 8]  = 32'h2060_2023; // sw     x6, 512(x0)
        u_ram.mem[SV32_CODE_IDX + 9]  = 32'h0000_006f; // j      0
        u_ram.mem[SV32_CODE_IDX + 16] = 32'hc000_0eb7; // lui    x29, 0xc0000
        u_ram.mem[SV32_CODE_IDX + 17] = 32'h000e_8e93; // addi   x29, x29, 0
        u_ram.mem[SV32_CODE_IDX + 18] = 32'h05a0_0293; // li     x5, 0x5a
        u_ram.mem[SV32_CODE_IDX + 19] = 32'h205e_a023; // sw     x5, 512(x29)
        u_ram.mem[SV32_CODE_IDX + 20] = 32'h1410_2373; // csrr   x6, sepc
        u_ram.mem[SV32_CODE_IDX + 21] = 32'h206e_a223; // sw     x6, 516(x29)
        u_ram.mem[SV32_CODE_IDX + 22] = 32'h1420_23f3; // csrr   x7, scause
        u_ram.mem[SV32_CODE_IDX + 23] = 32'h207e_a423; // sw     x7, 520(x29)
        u_ram.mem[SV32_CODE_IDX + 24] = 32'h1430_2e73; // csrr   x28, stval
        u_ram.mem[SV32_CODE_IDX + 25] = 32'h21ce_a623; // sw     x28, 524(x29)
        u_ram.mem[SV32_CODE_IDX + 26] = 32'h0000_006f; // j      0

        u_ram.mem[SV32_ROOT_IDX + 0] = 32'h0000_0000;
        u_ram.mem[SV32_ROOT_IDX + 768] = 32'h0000_00cf;
        u_ram.mem[128] = 32'h0000_0000;
        u_ram.mem[129] = 32'h0000_0000;
        u_ram.mem[130] = 32'h0000_0000;
        u_ram.mem[131] = 32'h0000_0000;
        u_ram.mem[132] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (420) @(posedge clk);

        if (u_ram.mem[128] !== 32'h0000_005a) begin
            $fatal(1, "expected Linux-style Sv32 trampoline marker mem[128] = 0000005a, got %08x pc=%08x priv=%0d satp=%08x stvec=%08x sepc=%08x scause=%08x stval=%08x state=%0d req=%0d pa=%0d pte=%08x l1=%08x",
                   u_ram.mem[128], u_core.pc, u_core.current_priv, u_core.csr_satp,
                   u_core.csr_stvec, u_core.csr_sepc, u_core.csr_scause, u_core.csr_stval,
                   u_core.state, u_core.req_active, u_core.req_pa_valid, u_core.ptw_pte_addr,
                   u_core.ptw_l1_pte);
        end
        if (u_ram.mem[129] !== 32'h0000_3018) begin
            $fatal(1, "expected Linux-style Sv32 trampoline sepc mem[129] = 00003018, got %08x",
                   u_ram.mem[129]);
        end
        if (u_ram.mem[130] !== 32'h0000_000c) begin
            $fatal(1, "expected Linux-style Sv32 trampoline scause mem[130] = 0000000c, got %08x",
                   u_ram.mem[130]);
        end
        if (u_ram.mem[131] !== 32'h0000_3018) begin
            $fatal(1, "expected Linux-style Sv32 trampoline stval mem[131] = 00003018, got %08x",
                   u_ram.mem[131]);
        end
        if (u_core.current_priv !== 2'b01) begin
            $fatal(1, "expected to remain in S-mode after Linux-style Sv32 trampoline smoke, priv=%0d",
                   u_core.current_priv);
        end

        u_ram.mem[0]  = 32'h0400_0093; // addi x1, x0, 64
        u_ram.mem[1]  = 32'h0010_0313; // addi x6, x0, 1
        u_ram.mem[2]  = 32'h0020_0513; // addi x10, x0, 2
        u_ram.mem[3]  = 32'h1000_a2af; // lr.w x5, 0(x1)
        u_ram.mem[4]  = 32'h1860_a3af; // sc.w x7, x6, 0(x1)
        u_ram.mem[5]  = 32'h1000_a42f; // lr.w x8, 0(x1)
        u_ram.mem[6]  = 32'h00a0_a023; // sw   x10, 0(x1)
        u_ram.mem[7]  = 32'h1860_a4af; // sc.w x9, x6, 0(x1)
        u_ram.mem[8]  = 32'h0080_a223; // sw   x8, 4(x1)
        u_ram.mem[9]  = 32'h0070_a423; // sw   x7, 8(x1)
        u_ram.mem[10] = 32'h0090_a623; // sw   x9, 12(x1)
        u_ram.mem[11] = 32'h0050_0593; // addi x11, x0, 5
        u_ram.mem[12] = 32'h00b0_a62f; // amoadd.w x12, x11, 0(x1)
        u_ram.mem[13] = 32'h00c0_a823; // sw   x12, 16(x1)
        u_ram.mem[14] = 32'h0000_006f; // jal  x0, 0
        u_ram.mem[16] = 32'h0000_0000;
        u_ram.mem[17] = 32'h0000_0000;
        u_ram.mem[18] = 32'h0000_0000;
        u_ram.mem[19] = 32'h0000_0000;
        u_ram.mem[20] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (200) @(posedge clk);

        if (u_ram.mem[16] !== 32'h0000_0007) begin
            $fatal(1, "expected LR/SC/AMOADD final mem[16] = 00000007, got %08x", u_ram.mem[16]);
        end
        if (u_ram.mem[17] !== 32'h0000_0001) begin
            $fatal(1, "expected LR/SC shadow mem[17] = 00000001, got %08x", u_ram.mem[17]);
        end
        if (u_ram.mem[18] !== 32'h0000_0000) begin
            $fatal(1, "expected SC success code mem[18] = 00000000, got %08x", u_ram.mem[18]);
        end
        if (u_ram.mem[19] !== 32'h0000_0001) begin
            $fatal(1, "expected SC fail code mem[19] = 00000001, got %08x", u_ram.mem[19]);
        end
        if (u_ram.mem[20] !== 32'h0000_0002) begin
            $fatal(1, "expected AMOADD old value mem[20] = 00000002, got %08x", u_ram.mem[20]);
        end

        u_ram.mem[0]  = 32'hff90_0093; // addi x1, x0, -7
        u_ram.mem[1]  = 32'h0030_0113; // addi x2, x0, 3
        u_ram.mem[2]  = 32'h0800_0513; // addi x10, x0, 128
        u_ram.mem[3]  = 32'h0220_81b3; // mul    x3, x1, x2
        u_ram.mem[4]  = 32'h0220_9233; // mulh   x4, x1, x2
        u_ram.mem[5]  = 32'h0220_a2b3; // mulhsu x5, x1, x2
        u_ram.mem[6]  = 32'h0220_b333; // mulhu  x6, x1, x2
        u_ram.mem[7]  = 32'h0220_c3b3; // div    x7, x1, x2
        u_ram.mem[8]  = 32'h0220_d433; // divu   x8, x1, x2
        u_ram.mem[9]  = 32'h0220_e4b3; // rem    x9, x1, x2
        u_ram.mem[10] = 32'h0220_f5b3; // remu   x11, x1, x2
        u_ram.mem[11] = 32'h0200_c633; // div    x12, x1, x0
        u_ram.mem[12] = 32'h0200_e6b3; // rem    x13, x1, x0
        u_ram.mem[13] = 32'h8000_0737; // lui    x14, 0x80000
        u_ram.mem[14] = 32'hfff0_0813; // addi   x16, x0, -1
        u_ram.mem[15] = 32'h0307_47b3; // div    x15, x14, x16
        u_ram.mem[16] = 32'h0307_68b3; // rem    x17, x14, x16
        u_ram.mem[17] = 32'h0035_2023; // sw     x3, 0(x10)
        u_ram.mem[18] = 32'h0045_2223; // sw     x4, 4(x10)
        u_ram.mem[19] = 32'h0055_2423; // sw     x5, 8(x10)
        u_ram.mem[20] = 32'h0065_2623; // sw     x6, 12(x10)
        u_ram.mem[21] = 32'h0075_2823; // sw     x7, 16(x10)
        u_ram.mem[22] = 32'h0085_2a23; // sw     x8, 20(x10)
        u_ram.mem[23] = 32'h0095_2c23; // sw     x9, 24(x10)
        u_ram.mem[24] = 32'h00b5_2e23; // sw     x11, 28(x10)
        u_ram.mem[25] = 32'h02c5_2023; // sw     x12, 32(x10)
        u_ram.mem[26] = 32'h02d5_2223; // sw     x13, 36(x10)
        u_ram.mem[27] = 32'h02f5_2423; // sw     x15, 40(x10)
        u_ram.mem[28] = 32'h0315_2623; // sw     x17, 44(x10)
        u_ram.mem[29] = 32'h0000_006f; // jal    x0, 0
        for (int i = 32; i < 44; i++) begin
            u_ram.mem[i] = 32'h0000_0000;
        end

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (700) @(posedge clk);

        if (u_ram.mem[32] !== 32'hffff_ffeb) begin
            $fatal(1, "expected MUL mem[32] = ffffffeb, got %08x", u_ram.mem[32]);
        end
        if (u_ram.mem[33] !== 32'hffff_ffff) begin
            $fatal(1, "expected MULH mem[33] = ffffffff, got %08x", u_ram.mem[33]);
        end
        if (u_ram.mem[34] !== 32'hffff_ffff) begin
            $fatal(1, "expected MULHSU mem[34] = ffffffff, got %08x", u_ram.mem[34]);
        end
        if (u_ram.mem[35] !== 32'h0000_0002) begin
            $fatal(1, "expected MULHU mem[35] = 00000002, got %08x", u_ram.mem[35]);
        end
        if (u_ram.mem[36] !== 32'hffff_fffe) begin
            $fatal(1, "expected DIV mem[36] = fffffffe, got %08x", u_ram.mem[36]);
        end
        if (u_ram.mem[37] !== 32'h5555_5553) begin
            $fatal(1, "expected DIVU mem[37] = 55555553, got %08x", u_ram.mem[37]);
        end
        if (u_ram.mem[38] !== 32'hffff_ffff) begin
            $fatal(1, "expected REM mem[38] = ffffffff, got %08x", u_ram.mem[38]);
        end
        if (u_ram.mem[39] !== 32'h0000_0000) begin
            $fatal(1, "expected REMU mem[39] = 00000000, got %08x", u_ram.mem[39]);
        end
        if (u_ram.mem[40] !== 32'hffff_ffff) begin
            $fatal(1, "expected DIV-by-zero mem[40] = ffffffff, got %08x", u_ram.mem[40]);
        end
        if (u_ram.mem[41] !== 32'hffff_fff9) begin
            $fatal(1, "expected REM-by-zero mem[41] = fffffff9, got %08x", u_ram.mem[41]);
        end
        if (u_ram.mem[42] !== 32'h8000_0000) begin
            $fatal(1, "expected DIV overflow mem[42] = 80000000, got %08x", u_ram.mem[42]);
        end
        if (u_ram.mem[43] !== 32'h0000_0000) begin
            $fatal(1, "expected REM overflow mem[43] = 00000000, got %08x", u_ram.mem[43]);
        end

        u_ram.mem[0]  = 32'h1000_0093; // li     x1, 0x100
        u_ram.mem[1]  = 32'hb000_9073; // csrw   mcycle, x1
        u_ram.mem[2]  = 32'hb800_1073; // csrw   mcycleh, x0
        u_ram.mem[3]  = 32'hb000_2173; // csrr   x2, mcycle
        u_ram.mem[4]  = 32'hc000_21f3; // csrr   x3, cycle
        u_ram.mem[5]  = 32'hc010_2273; // csrr   x4, time
        u_ram.mem[6]  = 32'hb020_1073; // csrw   minstret, x0
        u_ram.mem[7]  = 32'h0000_0013; // nop
        u_ram.mem[8]  = 32'h0000_0013; // nop
        u_ram.mem[9]  = 32'hb020_22f3; // csrr   x5, minstret
        u_ram.mem[10] = 32'h1820_2023; // sw     x2, 384(x0)
        u_ram.mem[11] = 32'h1830_2223; // sw     x3, 388(x0)
        u_ram.mem[12] = 32'h1840_2423; // sw     x4, 392(x0)
        u_ram.mem[13] = 32'h1850_2623; // sw     x5, 396(x0)
        u_ram.mem[14] = 32'h0000_006f; // j      0
        for (int i = 96; i < 100; i++) begin
            u_ram.mem[i] = 32'h0000_0000;
        end

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (180) @(posedge clk);

        if (u_ram.mem[96] < 32'h0000_0100) begin
            $fatal(1, "expected mcycle read mem[96] >= 00000100, got %08x", u_ram.mem[96]);
        end
        if (u_ram.mem[97] < u_ram.mem[96]) begin
            $fatal(1, "expected cycle read mem[97] >= mcycle read mem[96], got %08x < %08x",
                   u_ram.mem[97], u_ram.mem[96]);
        end
        if (u_ram.mem[98] < u_ram.mem[97]) begin
            $fatal(1, "expected time read mem[98] >= cycle read mem[97], got %08x < %08x",
                   u_ram.mem[98], u_ram.mem[97]);
        end
        if (u_ram.mem[99] < 32'h0000_0002) begin
            $fatal(1, "expected minstret read mem[99] >= 00000002, got %08x", u_ram.mem[99]);
        end

        u_ram.mem[0]  = 32'h0400_0093; // li     x1, 0x40
        u_ram.mem[1]  = 32'h1050_9073; // csrw   stvec, x1
        u_ram.mem[2]  = 32'h0040_0093; // li     x1, 4
        u_ram.mem[3]  = 32'h3020_9073; // csrw   medeleg, x1
        u_ram.mem[4]  = 32'h0280_0093; // li     x1, 0x28
        u_ram.mem[5]  = 32'h3410_9073; // csrw   mepc, x1
        u_ram.mem[6]  = 32'h0000_10b7; // lui    x1, 1
        u_ram.mem[7]  = 32'h8000_8093; // addi   x1, x1, -2048
        u_ram.mem[8]  = 32'h3000_9073; // csrw   mstatus, x1
        u_ram.mem[9]  = 32'h3020_0073; // mret
        u_ram.mem[10] = 32'hc000_2173; // csrr   x2, cycle
        u_ram.mem[11] = 32'h0ee0_0193; // li     x3, 0xee
        u_ram.mem[12] = 32'h1830_2a23; // sw     x3, 404(x0)
        u_ram.mem[13] = 32'h0000_006f; // j      0
        u_ram.mem[14] = 32'h0000_0000;
        u_ram.mem[15] = 32'h0000_0000;
        u_ram.mem[16] = 32'h1420_2273; // csrr   x4, scause
        u_ram.mem[17] = 32'h1840_2823; // sw     x4, 400(x0)
        u_ram.mem[18] = 32'h1410_22f3; // csrr   x5, sepc
        u_ram.mem[19] = 32'h1850_2c23; // sw     x5, 408(x0)
        u_ram.mem[20] = 32'h0042_8293; // addi   x5, x5, 4
        u_ram.mem[21] = 32'h1412_9073; // csrw   sepc, x5
        u_ram.mem[22] = 32'h1020_0073; // sret
        for (int i = 100; i < 103; i++) begin
            u_ram.mem[i] = 32'h0000_0000;
        end

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (240) @(posedge clk);

        if (u_ram.mem[100] !== 32'h0000_0002) begin
            $fatal(1, "expected S-mode counter-deny scause mem[100] = 00000002, got %08x",
                   u_ram.mem[100]);
        end
        if (u_ram.mem[101] !== 32'h0000_00ee) begin
            $fatal(1, "expected S-mode counter-deny return marker mem[101] = 000000ee, got %08x",
                   u_ram.mem[101]);
        end
        if (u_ram.mem[102] !== 32'h0000_0028) begin
            $fatal(1, "expected S-mode counter-deny sepc mem[102] = 00000028, got %08x",
                   u_ram.mem[102]);
        end
        if (u_core.current_priv !== 2'b01) begin
            $fatal(1, "expected to remain in S-mode after counter-deny smoke, priv=%0d",
                   u_core.current_priv);
        end

        u_ram.mem[0]  = 32'h0070_0093; // li     x1, 7
        u_ram.mem[1]  = 32'h3060_9073; // csrw   mcounteren, x1
        u_ram.mem[2]  = 32'h0200_0093; // li     x1, 0x20
        u_ram.mem[3]  = 32'h3410_9073; // csrw   mepc, x1
        u_ram.mem[4]  = 32'h0000_10b7; // lui    x1, 1
        u_ram.mem[5]  = 32'h8000_8093; // addi   x1, x1, -2048
        u_ram.mem[6]  = 32'h3000_9073; // csrw   mstatus, x1
        u_ram.mem[7]  = 32'h3020_0073; // mret
        u_ram.mem[8]  = 32'h0070_0313; // li     x6, 7
        u_ram.mem[9]  = 32'h1063_1073; // csrw   scounteren, x6
        u_ram.mem[10] = 32'h1060_23f3; // csrr   x7, scounteren
        u_ram.mem[11] = 32'hc000_2173; // csrr   x2, cycle
        u_ram.mem[12] = 32'hc010_21f3; // csrr   x3, time
        u_ram.mem[13] = 32'hc020_2273; // csrr   x4, instret
        u_ram.mem[14] = 32'h1870_2e23; // sw     x7, 412(x0)
        u_ram.mem[15] = 32'h1a20_2023; // sw     x2, 416(x0)
        u_ram.mem[16] = 32'h1a30_2223; // sw     x3, 420(x0)
        u_ram.mem[17] = 32'h1a40_2423; // sw     x4, 424(x0)
        u_ram.mem[18] = 32'h05a0_0293; // li     x5, 0x5a
        u_ram.mem[19] = 32'h1a50_2623; // sw     x5, 428(x0)
        u_ram.mem[20] = 32'h0000_006f; // j      0
        for (int i = 103; i < 108; i++) begin
            u_ram.mem[i] = 32'h0000_0000;
        end

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (220) @(posedge clk);

        if (u_ram.mem[103] !== 32'h0000_0007) begin
            $fatal(1, "expected scounteren readback mem[103] = 00000007, got %08x",
                   u_ram.mem[103]);
        end
        if (u_ram.mem[104] == 32'h0000_0000) begin
            $fatal(1, "expected S-mode cycle read mem[104] to be nonzero");
        end
        if (u_ram.mem[105] < u_ram.mem[104]) begin
            $fatal(1, "expected S-mode time read mem[105] >= cycle read mem[104], got %08x < %08x",
                   u_ram.mem[105], u_ram.mem[104]);
        end
        if (u_ram.mem[106] == 32'h0000_0000) begin
            $fatal(1, "expected S-mode instret read mem[106] to be nonzero");
        end
        if (u_ram.mem[107] !== 32'h0000_005a) begin
            $fatal(1, "expected S-mode counter-enable marker mem[107] = 0000005a, got %08x",
                   u_ram.mem[107]);
        end
        if (u_core.current_priv !== 2'b01) begin
            $fatal(1, "expected to remain in S-mode after counter-enable smoke, priv=%0d",
                   u_core.current_priv);
        end

        u_ram.mem[0]  = 32'h0200_0093; // addi x1, x0, 0x20
        u_ram.mem[1]  = 32'h3050_9073; // csrw mtvec, x1
        u_ram.mem[2]  = 32'h0800_0093; // addi x1, x0, 0x80
        u_ram.mem[3]  = 32'h3040_9073; // csrw mie, x1
        u_ram.mem[4]  = 32'h0080_0093; // addi x1, x0, 8
        u_ram.mem[5]  = 32'h3000_9073; // csrw mstatus, x1
        u_ram.mem[6]  = 32'h0000_006f; // j    0
        u_ram.mem[8]  = 32'h3420_2173; // csrr x2, mcause
        u_ram.mem[9]  = 32'h0620_2023; // sw   x2, 96(x0)
        u_ram.mem[10] = 32'h05a0_0193; // addi x3, x0, 0x5a
        u_ram.mem[11] = 32'h0630_2223; // sw   x3, 100(x0)
        u_ram.mem[12] = 32'h3040_1073; // csrw mie, x0
        u_ram.mem[13] = 32'h0000_006f; // j    0
        u_ram.mem[24] = 32'h0000_0000;
        u_ram.mem[25] = 32'h0000_0000;

        reset_vector = 32'd0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (20) @(posedge clk);
        irq_timer = 1'b1;

        repeat (120) @(posedge clk);

        if (u_ram.mem[24] !== 32'h8000_0007) begin
            $fatal(1, "expected timer mcause mem[24] = 80000007, got %08x", u_ram.mem[24]);
        end
        if (u_ram.mem[25] !== 32'h0000_005a) begin
            $fatal(1, "expected timer marker mem[25] = 0000005a, got %08x", u_ram.mem[25]);
        end

        u_ram.mem[0]  = 32'h0080_00ef; // jal  ra, main
        u_ram.mem[1]  = 32'h04a0_2823; // sw   a0, 80(x0)
        u_ram.mem[2]  = 32'h05a0_0513; // addi a0, x0, 0x5a
        u_ram.mem[3]  = 32'h0000_8067; // ret
        u_ram.mem[20] = 32'h0000_0000;

        reset_vector = 32'd0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        repeat (100) @(posedge clk);

        if (u_ram.mem[20] !== 32'h0000_005a) begin
            $fatal(1, "expected jal-link mem[20] = 0000005a, got %08x ra=%08x pc=%08x",
                   u_ram.mem[20], u_core.u_regfile.regs[1], u_core.pc);
        end

        $display("PASS");
        $finish;
    end
endmodule
