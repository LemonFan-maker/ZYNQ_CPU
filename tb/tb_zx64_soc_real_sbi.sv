module tb_zx64_soc_real_sbi;
    localparam int BRAM_WORDS = 1024;
    localparam int KERNEL_WORDS = 1024;
    localparam int FW_ENTRY = 32'h0000_0000;
    localparam logic [31:0] DDR_CPU_BASE = 32'h8000_0000;
    localparam logic [31:0] KERNEL_CPU = 32'h8020_0000;
    localparam logic [31:0] KERNEL_PHYS = KERNEL_CPU - DDR_CPU_BASE;
    localparam logic [31:0] DTB_CPU = 32'h8200_0000;
    localparam logic [31:0] SBI_EXT_TIME = 32'h5449_4d45;
    localparam logic [31:0] SBI_EXT_IPI = 32'h0073_5049;
    localparam logic [31:0] SBI_EXT_RFENCE = 32'h5246_4e43;
    localparam logic [31:0] SBI_EXT_HSM = 32'h0048_534d;
    localparam logic [31:0] SBI_EXT_SRST = 32'h5352_5354;
    localparam logic [31:0] SBI_EXT_PMU = 32'h0050_4d55;
    localparam logic [31:0] SBI_EXT_DBCN = 32'h4442_434e;
    localparam logic [31:0] SBI_EXT_UNKNOWN = 32'h0000_0123;
    localparam logic [31:0] CPU_STATUS_PASS = 32'h0000_0222;
    parameter bit USE_CORE5 = 1'b0;

    logic clk;
    logic rst_n;
    logic irq_external_i;
    logic uart_tx;
    logic core_halted;
    logic core_illegal;
    logic [31:0] dbg_core_state;
    logic [63:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_icache_hits;
    logic [31:0] dbg_icache_misses;
    logic [31:0] dbg_dcache_hits;
    logic [31:0] dbg_dcache_misses;
    logic [31:0] dbg_cache_invalidates;

    logic [3:0]  M_AXI_DDR_AWID;
    logic [31:0] M_AXI_DDR_AWADDR;
    logic [7:0]  M_AXI_DDR_AWLEN;
    logic [2:0]  M_AXI_DDR_AWSIZE;
    logic [1:0]  M_AXI_DDR_AWBURST;
    logic        M_AXI_DDR_AWLOCK;
    logic [3:0]  M_AXI_DDR_AWCACHE;
    logic [2:0]  M_AXI_DDR_AWPROT;
    logic [3:0]  M_AXI_DDR_AWQOS;
    logic        M_AXI_DDR_AWVALID;
    logic        M_AXI_DDR_AWREADY;
    logic [31:0] M_AXI_DDR_WDATA;
    logic [3:0]  M_AXI_DDR_WSTRB;
    logic        M_AXI_DDR_WLAST;
    logic        M_AXI_DDR_WVALID;
    logic        M_AXI_DDR_WREADY;
    logic [3:0]  M_AXI_DDR_BID;
    logic [1:0]  M_AXI_DDR_BRESP;
    logic        M_AXI_DDR_BVALID;
    logic        M_AXI_DDR_BREADY;
    logic [3:0]  M_AXI_DDR_ARID;
    logic [31:0] M_AXI_DDR_ARADDR;
    logic [7:0]  M_AXI_DDR_ARLEN;
    logic [2:0]  M_AXI_DDR_ARSIZE;
    logic [1:0]  M_AXI_DDR_ARBURST;
    logic        M_AXI_DDR_ARLOCK;
    logic [3:0]  M_AXI_DDR_ARCACHE;
    logic [2:0]  M_AXI_DDR_ARPROT;
    logic [3:0]  M_AXI_DDR_ARQOS;
    logic        M_AXI_DDR_ARVALID;
    logic        M_AXI_DDR_ARREADY;
    logic [3:0]  M_AXI_DDR_RID;
    logic [31:0] M_AXI_DDR_RDATA;
    logic [1:0]  M_AXI_DDR_RRESP;
    logic        M_AXI_DDR_RLAST;
    logic        M_AXI_DDR_RVALID;
    logic        M_AXI_DDR_RREADY;

    logic [31:0] kernel_mem [0:KERNEL_WORDS-1];
    logic [31:0] araddr_q;
    logic [7:0]  arlen_q;
    logic [7:0]  rbeat_q;
    logic        rburst_active_q;
    logic [31:0] burst_read_count;
    integer      kernel_pcw;
    string       fw_memh;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    zx64_soc #(
        .BRAM_WORDS(BRAM_WORDS),
        .CLK_HZ(1_000_000),
        .USE_CORE5(USE_CORE5)
    ) u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(1'b0),
        .reset_vector({32'd0, FW_ENTRY}),
        .irq_external_i(irq_external_i),
        .virtio_blk_capacity_sectors(64'd0),
        .virtio_blk_backend_irq(1'b0),
        .virtio_blk_notify_ack(1'b0),
        .virtio_blk_notify_pending(),
        .virtio_blk_notify_queue(),
        .virtio_blk_notify_count(),
        .virtio_blk_queue_num(),
        .virtio_blk_queue_ready(),
        .virtio_blk_queue_desc_addr(),
        .virtio_blk_queue_avail_addr(),
        .virtio_blk_queue_used_addr(),
        .virtio_blk_irq_pending(),
        .virtio_blk_device_status(),
        .virtio_input_backend_irq(1'b0),
        .virtio_input_notify_ack(1'b0),
        .virtio_input_notify_pending(),
        .virtio_input_notify_queue(),
        .virtio_input_notify_count(),
        .virtio_input_irq_pending(),
        .virtio_input_device_status(),
        .virtio_input_event_queue_num(),
        .virtio_input_event_queue_ready(),
        .virtio_input_event_queue_desc_addr(),
        .virtio_input_event_queue_avail_addr(),
        .virtio_input_event_queue_used_addr(),
        .virtio_input_status_queue_num(),
        .virtio_input_status_queue_ready(),
        .virtio_input_status_queue_desc_addr(),
        .virtio_input_status_queue_avail_addr(),
        .virtio_input_status_queue_used_addr(),
        .uart_tx(uart_tx),
        .core_halted(core_halted),
        .core_illegal(core_illegal),
        .dbg_core_state(dbg_core_state),
        .dbg_pc(dbg_pc),
        .dbg_instr(dbg_instr),
        .dbg_icache_hits(dbg_icache_hits),
        .dbg_icache_misses(dbg_icache_misses),
        .dbg_dcache_hits(dbg_dcache_hits),
        .dbg_dcache_misses(dbg_dcache_misses),
        .dbg_cache_invalidates(dbg_cache_invalidates),
        .host_valid(1'b0),
        .host_we(1'b0),
        .host_wstrb(4'd0),
        .host_addr(32'd0),
        .host_wdata(32'd0),
        .host_ready(),
        .host_rdata(),
        .M_AXI_DDR_AWID(M_AXI_DDR_AWID),
        .M_AXI_DDR_AWADDR(M_AXI_DDR_AWADDR),
        .M_AXI_DDR_AWLEN(M_AXI_DDR_AWLEN),
        .M_AXI_DDR_AWSIZE(M_AXI_DDR_AWSIZE),
        .M_AXI_DDR_AWBURST(M_AXI_DDR_AWBURST),
        .M_AXI_DDR_AWLOCK(M_AXI_DDR_AWLOCK),
        .M_AXI_DDR_AWCACHE(M_AXI_DDR_AWCACHE),
        .M_AXI_DDR_AWPROT(M_AXI_DDR_AWPROT),
        .M_AXI_DDR_AWQOS(M_AXI_DDR_AWQOS),
        .M_AXI_DDR_AWVALID(M_AXI_DDR_AWVALID),
        .M_AXI_DDR_AWREADY(M_AXI_DDR_AWREADY),
        .M_AXI_DDR_WDATA(M_AXI_DDR_WDATA),
        .M_AXI_DDR_WSTRB(M_AXI_DDR_WSTRB),
        .M_AXI_DDR_WLAST(M_AXI_DDR_WLAST),
        .M_AXI_DDR_WVALID(M_AXI_DDR_WVALID),
        .M_AXI_DDR_WREADY(M_AXI_DDR_WREADY),
        .M_AXI_DDR_BID(M_AXI_DDR_BID),
        .M_AXI_DDR_BRESP(M_AXI_DDR_BRESP),
        .M_AXI_DDR_BVALID(M_AXI_DDR_BVALID),
        .M_AXI_DDR_BREADY(M_AXI_DDR_BREADY),
        .M_AXI_DDR_ARID(M_AXI_DDR_ARID),
        .M_AXI_DDR_ARADDR(M_AXI_DDR_ARADDR),
        .M_AXI_DDR_ARLEN(M_AXI_DDR_ARLEN),
        .M_AXI_DDR_ARSIZE(M_AXI_DDR_ARSIZE),
        .M_AXI_DDR_ARBURST(M_AXI_DDR_ARBURST),
        .M_AXI_DDR_ARLOCK(M_AXI_DDR_ARLOCK),
        .M_AXI_DDR_ARCACHE(M_AXI_DDR_ARCACHE),
        .M_AXI_DDR_ARPROT(M_AXI_DDR_ARPROT),
        .M_AXI_DDR_ARQOS(M_AXI_DDR_ARQOS),
        .M_AXI_DDR_ARVALID(M_AXI_DDR_ARVALID),
        .M_AXI_DDR_ARREADY(M_AXI_DDR_ARREADY),
        .M_AXI_DDR_RID(M_AXI_DDR_RID),
        .M_AXI_DDR_RDATA(M_AXI_DDR_RDATA),
        .M_AXI_DDR_RRESP(M_AXI_DDR_RRESP),
        .M_AXI_DDR_RLAST(M_AXI_DDR_RLAST),
        .M_AXI_DDR_RVALID(M_AXI_DDR_RVALID),
        .M_AXI_DDR_RREADY(M_AXI_DDR_RREADY)
    );

    assign M_AXI_DDR_AWREADY = 1'b0;
    assign M_AXI_DDR_WREADY = 1'b0;
    assign M_AXI_DDR_BID = 4'd0;
    assign M_AXI_DDR_BRESP = 2'd0;
    assign M_AXI_DDR_BVALID = 1'b0;
    assign M_AXI_DDR_ARREADY = !M_AXI_DDR_RVALID && !rburst_active_q;
    assign M_AXI_DDR_RID = 4'd0;
    assign M_AXI_DDR_RRESP = 2'd0;
    assign M_AXI_DDR_RLAST = M_AXI_DDR_RVALID && (rbeat_q == arlen_q);

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

    function automatic logic [31:0] enc_u(input logic [19:0] imm20,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_u = {imm20, rd, opcode};
    endfunction

    function automatic logic [31:0] ddr_read_word(input logic [31:0] addr);
        begin
            ddr_read_word = 32'h0010_0073;
            if (addr >= KERNEL_PHYS && addr < KERNEL_PHYS + KERNEL_WORDS * 4) begin
                ddr_read_word = kernel_mem[(addr - KERNEL_PHYS) >> 2];
            end
        end
    endfunction

    task automatic kernel_emit(input logic [31:0] inst);
        begin
            kernel_mem[kernel_pcw] = inst;
            kernel_pcw = kernel_pcw + 1;
        end
    endtask

    task automatic li_small(input logic [4:0] rd, input logic signed [11:0] imm);
        kernel_emit(enc_i(imm, 5'd0, 3'b000, rd, 7'b0010011));
    endtask

    task automatic li_const32(input logic [4:0] rd, input logic [31:0] value);
        logic [31:0] upper;
        logic signed [11:0] lower;
        begin
            upper = (value + 32'h0000_0800) >> 12;
            lower = value[11:0];
            kernel_emit(enc_u(upper[19:0], rd, 7'b0110111));
            if (lower != 12'sd0) begin
                kernel_emit(enc_i(lower, rd, 3'b000, rd, 7'b0010011));
            end
        end
    endtask

    task automatic lw_offset(input logic [4:0] rd,
                             input logic [4:0] rs1,
                             input logic signed [11:0] imm);
        kernel_emit(enc_i(imm, rs1, 3'b010, rd, 7'b0000011));
    endtask

    function automatic logic [31:0] scratch_tx_word(input int word_index);
        begin
            scratch_tx_word = word_index[0] ?
                              u_soc.scratch_tx_hi_mem[word_index >> 1] :
                              u_soc.scratch_tx_lo_mem[word_index >> 1];
        end
    endfunction

    task automatic set_tx_word(input int word_index,
                               input logic [31:0] value);
        begin
            if (word_index[0]) begin
                u_soc.scratch_tx_hi_mem[word_index >> 1] = value;
            end else begin
                u_soc.scratch_tx_lo_mem[word_index >> 1] = value;
            end
        end
    endtask

    task automatic expect_tx(input int word_index,
                             input logic [31:0] expected,
                             input string label);
        logic [31:0] got;
        begin
            got = scratch_tx_word(word_index);
            if (got !== expected) begin
                $fatal(1, "%s expected tx[%0d]=%08x got %08x pc=%016x instr=%08x state=%08x illegal=%0d",
                       label, word_index, expected, got, dbg_pc, dbg_instr,
                       dbg_core_state, core_illegal);
            end
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_DDR_RVALID <= 1'b0;
            M_AXI_DDR_RDATA <= 32'd0;
            araddr_q <= 32'd0;
            arlen_q <= 8'd0;
            rbeat_q <= 8'd0;
            rburst_active_q <= 1'b0;
            burst_read_count <= 32'd0;
        end else begin
            if (M_AXI_DDR_RVALID && M_AXI_DDR_RREADY) begin
                if (rbeat_q == arlen_q) begin
                    M_AXI_DDR_RVALID <= 1'b0;
                    rburst_active_q <= 1'b0;
                    rbeat_q <= 8'd0;
                end else begin
                    rbeat_q <= rbeat_q + 8'd1;
                    M_AXI_DDR_RDATA <= ddr_read_word(araddr_q + {22'd0, rbeat_q + 8'd1, 2'b00});
                end
            end
            if (M_AXI_DDR_ARVALID && M_AXI_DDR_ARREADY) begin
                araddr_q <= M_AXI_DDR_ARADDR;
                arlen_q <= M_AXI_DDR_ARLEN;
                rbeat_q <= 8'd0;
                rburst_active_q <= 1'b1;
                burst_read_count <= burst_read_count + 32'd1;
                M_AXI_DDR_RDATA <= ddr_read_word(M_AXI_DDR_ARADDR);
                M_AXI_DDR_RVALID <= 1'b1;
            end
        end
    end

    initial begin
        irq_external_i = 1'b0;
        rst_n = 1'b0;
        if (!$value$plusargs("FW_MEMH=%s", fw_memh)) begin
            fw_memh = "/tmp/zx64_linux_boot_firmware.memh";
        end

        for (int i = 0; i < BRAM_WORDS; i++) begin
            u_soc.u_ram.mem[i] = 64'd0;
        end
        for (int i = 0; i < KERNEL_WORDS; i++) begin
            kernel_mem[i] = 32'h1050_0073;
        end
        $readmemh(fw_memh, u_soc.u_ram.mem);

        set_tx_word(('h300 >> 2), KERNEL_CPU);
        set_tx_word(('h304 >> 2), DTB_CPU);

        kernel_pcw = 0;
        kernel_emit(enc_u(20'h20010, 5'd8, 7'b0110111));                 // lui   s0, 0x20010
        kernel_emit(enc_s(12'sh3b0, 5'd10, 5'd8, 3'b010, 7'b0100011));   // sw    a0, 0x3b0(s0)
        kernel_emit(enc_s(12'sh3b4, 5'd11, 5'd8, 3'b010, 7'b0100011));   // sw    a1, 0x3b4(s0)
        li_small(5'd5, 12'sd81);                                         // prepare legacy input 'Q'
        kernel_emit(enc_s(12'sh108, 5'd5, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd5, 12'sd1);
        kernel_emit(enc_s(12'sh10c, 5'd5, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd5, 32'h0000_5352);                                 // prepare input ring "RS"
        kernel_emit(enc_s(12'sh110, 5'd5, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd5, 12'sd2);
        kernel_emit(enc_s(12'sh190, 5'd5, 5'd8, 3'b010, 7'b0100011));     // head
        li_small(5'd5, 12'sd0);
        kernel_emit(enc_s(12'sh194, 5'd5, 5'd8, 3'b010, 7'b0100011));     // tail
        li_const32(5'd5, 32'h0043_4241);                                 // prepare DBCN write buffer "ABC"
        kernel_emit(enc_s(12'sh370, 5'd5, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);                                        // a7 = SBI_EXT_BASE
        li_small(5'd16, 12'sd0);                                         // a6 = get_spec_version
        kernel_emit(32'h0000_0073);                                      // ecall
        kernel_emit(enc_s(12'sh3b8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3bc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd1);                                         // get_impl_id
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3c0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3c4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd2);                                         // get_impl_version
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh298, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh29c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd4);                                         // get_mvendorid
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2a0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2a4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd5);                                         // get_marchid
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2a8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2ac, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd6);                                         // get_mimpid
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2b0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2b4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_DBCN);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3c8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3cc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_TIME);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3d0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3d4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_IPI);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3d8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3dc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_RFENCE);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3e0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3e4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_HSM);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3e8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3ec, 5'd11, 5'd8, 3'b010, 7'b0100011));
        // PMU result slots intentionally use the low scratch area in this
        // test. Keep console output short or move these slots out of
        // 0x000..0x0ff before adding larger DBCN write coverage.
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_PMU);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh020, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh024, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_small(5'd10, 12'sd16);                                        // SBI_EXT_BASE
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0a0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0a4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_SRST);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0a8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0ac, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe_extension
        li_const32(5'd10, SBI_EXT_UNKNOWN);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0b0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0b4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy set_timer
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh400, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh404, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy console_putchar
        li_small(5'd10, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh408, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh40c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy console_getchar
        li_small(5'd10, 12'sd2);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh410, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh414, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy clear_ipi
        li_small(5'd10, 12'sd3);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh418, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh41c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy send_ipi
        li_small(5'd10, 12'sd4);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh420, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh424, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy remote_fence_i
        li_small(5'd10, 12'sd5);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh428, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh42c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy remote_sfence_vma
        li_small(5'd10, 12'sd6);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh430, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh434, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy remote_sfence_vma_asid
        li_small(5'd10, 12'sd7);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh438, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh43c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd3);                                         // probe legacy shutdown
        li_small(5'd10, 12'sd8);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh440, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh444, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd2);                                         // console_write_byte
        li_small(5'd10, 12'sd90);                                        // 'Z'
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh270, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh274, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd0);                                        // console_write buffer
        li_small(5'd10, 12'sd3);                                        // num bytes
        li_const32(5'd11, 32'h2001_0370);                               // input buffer in tx scratch
        li_small(5'd12, 12'sd0);                                        // base_addr_hi
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh380, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh384, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd0);                                        // console_write zero length
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        li_small(5'd13, 12'sd33);
        li_small(5'd14, 12'sd44);
        li_small(5'd15, 12'sd55);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh388, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh38c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0c0, 5'd12, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0c4, 5'd13, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0c8, 5'd14, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0cc, 5'd15, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0d0, 5'd16, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0d4, 5'd17, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd0);                                        // console_write invalid high address
        li_small(5'd10, 12'sd1);
        li_const32(5'd11, 32'h2001_0370);
        li_small(5'd12, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0d8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0dc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd1);                                        // console_read zero length
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh390, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh394, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd1);                                        // console_read ring buffer
        li_small(5'd10, 12'sd2);                                        // num bytes
        li_const32(5'd11, 32'h2001_0364);                               // output buffer in tx scratch
        li_small(5'd12, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh398, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh39c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd1);                                        // console_read
        li_small(5'd10, 12'sd1);                                        // num bytes
        li_const32(5'd11, 32'h2001_0368);                               // output buffer in tx scratch
        li_small(5'd12, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh288, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh28c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd1);                                        // console_read invalid high address
        li_small(5'd10, 12'sd1);
        li_const32(5'd11, 32'h2001_0368);
        li_small(5'd12, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0e0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0e4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd5, 12'sd0);
        kernel_emit(enc_s(12'sh100, 5'd5, 5'd8, 3'b010, 7'b0100011));    // ring head = 0
        li_small(5'd5, 12'sd256);
        kernel_emit(enc_s(12'sh104, 5'd5, 5'd8, 3'b010, 7'b0100011));    // ring total = full
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd0);                                        // full-ring console_write
        li_small(5'd10, 12'sd1);
        li_const32(5'd11, 32'h2001_0370);
        li_small(5'd12, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0e8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0ec, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd5, 12'sd0);
        kernel_emit(enc_s(12'sh100, 5'd5, 5'd8, 3'b010, 7'b0100011));    // restore ring head
        li_small(5'd5, 12'sd4);
        kernel_emit(enc_s(12'sh104, 5'd5, 5'd8, 3'b010, 7'b0100011));    // restore ring total
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd7);                                        // invalid BASE fid
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh240, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh244, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_UNKNOWN);
        li_small(5'd16, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh290, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh294, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_TIME);
        li_small(5'd16, 12'sd1);                                        // invalid TIME fid
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh248, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh24c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_DBCN);
        li_small(5'd16, 12'sd3);                                        // invalid DBCN fid
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh250, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh254, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_TIME);
        li_small(5'd16, 12'sd0);                                        // set_timer
        li_const32(5'd10, 32'h0040_0000);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh278, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh27c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        lw_offset(5'd5, 5'd8, 12'sh320);                                // CPU_LINUX_CMP_LO
        kernel_emit(enc_s(12'sh280, 5'd5, 5'd8, 3'b010, 7'b0100011));
        lw_offset(5'd5, 5'd8, 12'sh324);                                // CPU_LINUX_CMP_HI
        kernel_emit(enc_s(12'sh284, 5'd5, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_TIME);
        li_small(5'd16, 12'sd0);                                        // set_timer UINT64_MAX
        li_small(5'd10, -12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0b8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0bc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        lw_offset(5'd5, 5'd8, 12'sh320);                                // CPU_LINUX_CMP_LO
        kernel_emit(enc_s(12'sh0f0, 5'd5, 5'd8, 3'b010, 7'b0100011));
        lw_offset(5'd5, 5'd8, 12'sh324);                                // CPU_LINUX_CMP_HI
        kernel_emit(enc_s(12'sh0f4, 5'd5, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_SRST);
        li_small(5'd16, 12'sd0);                                        // system_reset
        li_small(5'd10, 12'sd3);                                        // invalid reset type
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2b8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2bc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_SRST);
        li_small(5'd16, 12'sd0);                                        // system_reset
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd2);                                        // invalid reset reason
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2c0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2c4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_SRST);
        li_small(5'd16, 12'sd1);                                        // invalid SRST fid
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh348, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh34c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        lw_offset(5'd5, 5'd8, 12'sh260);                                // reset magic must still be clear
        kernel_emit(enc_s(12'sh264, 5'd5, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_IPI);
        li_small(5'd16, 12'sd0);                                        // send_ipi
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2c8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2cc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_IPI);
        li_small(5'd16, 12'sd0);                                        // empty hart mask with nonzero base
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh0f8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh0fc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_IPI);
        li_small(5'd16, 12'sd0);                                        // invalid hart mask selects hart1
        li_small(5'd10, 12'sd2);
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh358, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh35c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_IPI);
        li_small(5'd16, 12'sd1);                                        // invalid IPI fid
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh360, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3a0, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_RFENCE);
        li_small(5'd16, 12'sd0);                                        // remote_fence_i
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2d0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2d4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_RFENCE);
        li_small(5'd16, 12'sd0);                                        // empty hart mask with nonzero base
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3a4, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3a8, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_RFENCE);
        li_small(5'd16, 12'sd1);                                        // remote_sfence_vma
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        li_small(5'd13, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh330, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh334, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_RFENCE);
        li_small(5'd16, 12'sd2);                                        // remote_sfence_vma_asid
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        li_small(5'd13, 12'sd0);
        li_small(5'd14, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh338, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh33c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_RFENCE);
        li_small(5'd16, 12'sd0);                                        // invalid hart mask selects hart1
        li_small(5'd10, 12'sd2);
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh340, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh344, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_RFENCE);
        li_small(5'd16, 12'sd3);                                        // remote_hfence_gvma_vmid unsupported without H
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh350, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh354, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd3);                                        // legacy clear_ipi
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh448, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh44c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd4);                                        // legacy send_ipi
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh450, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh454, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd5);                                        // legacy remote_fence_i
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh458, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh45c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd6);                                        // legacy remote_sfence_vma
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh460, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh464, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_small(5'd17, 12'sd7);                                        // legacy remote_sfence_vma_asid
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh468, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh46c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd0);                                        // num_counters
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh028, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh02c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd1);                                        // counter_get_info invalid counter
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh030, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh034, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd2);                                        // counter_config_matching unsupported
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh038, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh03c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd3);                                        // counter_start invalid counter
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh040, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh044, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd4);                                        // counter_stop invalid counter
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh048, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh04c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd5);                                        // counter_fw_read invalid counter
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh050, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh054, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd6);                                        // counter_fw_read_hi invalid counter
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh058, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh05c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd7);                                        // snapshot_set_shmem unsupported
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh060, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh064, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd8);                                        // event_get_info unsupported
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh068, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh06c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd9);                                        // invalid PMU fid
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh070, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh074, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd2);                                        // counter_config_matching reserved flags
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd256);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh078, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh07c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd7);                                        // snapshot_set_shmem reserved flags
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh080, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh084, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd7);                                        // snapshot_set_shmem unaligned low address
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh088, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh08c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd8);                                        // event_get_info reserved flags
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        li_small(5'd13, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh090, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh094, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_PMU);
        li_small(5'd16, 12'sd8);                                        // event_get_info unaligned address
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        li_small(5'd13, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh098, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh09c, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_HSM);
        li_small(5'd16, 12'sd2);                                        // hart_get_status
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2d8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2dc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_HSM);
        li_small(5'd16, 12'sd2);                                        // hart_get_status invalid hart
        li_small(5'd10, 12'sd1);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2e0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2e4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_HSM);
        li_small(5'd16, 12'sd0);                                        // hart_start already-started boot hart
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2e8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2ec, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_HSM);
        li_small(5'd16, 12'sd3);                                        // hart_suspend unsupported
        li_small(5'd10, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2f0, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2f4, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_HSM);
        li_small(5'd16, 12'sd3);                                        // hart_suspend reserved type
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        li_small(5'd12, 12'sd0);
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh3f4, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh3f8, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_HSM);
        li_small(5'd16, 12'sd1);                                        // hart_stop cannot stop boot hart
        kernel_emit(32'h0000_0073);
        kernel_emit(enc_s(12'sh2f8, 5'd10, 5'd8, 3'b010, 7'b0100011));
        kernel_emit(enc_s(12'sh2fc, 5'd11, 5'd8, 3'b010, 7'b0100011));
        li_const32(5'd17, SBI_EXT_SRST);
        li_small(5'd16, 12'sd0);                                        // system_reset
        li_small(5'd10, 12'sd0);                                        // shutdown
        li_small(5'd11, 12'sd0);                                        // no reason
        kernel_emit(32'h0000_0073);
        kernel_emit(32'h1050_0073);                                      // wfi
        kernel_emit(32'h0000_006f);                                      // j .

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 100000 && scratch_tx_word('h3f0 >> 2) != CPU_STATUS_PASS; cycle++) begin
            @(posedge clk);
        end

        if (scratch_tx_word('h3f0 >> 2) != CPU_STATUS_PASS || core_illegal) begin
            $fatal(1, "real RV64 firmware SBI path did not pass status=%08x illegal=%0d pc=%016x instr=%08x state=%08x bursts=%0d",
                   scratch_tx_word('h3f0 >> 2), core_illegal,
                   dbg_pc, dbg_instr, dbg_core_state, burst_read_count);
        end

        expect_tx(('h3b0 >> 2), 32'd0, "payload hartid");
        expect_tx(('h3b4 >> 2), DTB_CPU, "payload dtb");
        expect_tx(('h3b8 >> 2), 32'd0, "SBI spec error");
        expect_tx(('h3bc >> 2), 32'h0200_0000, "SBI spec version");
        expect_tx(('h3c0 >> 2), 32'd0, "SBI impl id error");
        expect_tx(('h3c4 >> 2), 32'h0000_5a64, "SBI impl id");
        expect_tx(('h298 >> 2), 32'd0, "SBI impl version error");
        expect_tx(('h29c >> 2), 32'd1, "SBI impl version");
        expect_tx(('h2a0 >> 2), 32'd0, "SBI mvendorid error");
        expect_tx(('h2a4 >> 2), 32'd0, "SBI mvendorid");
        expect_tx(('h2a8 >> 2), 32'd0, "SBI marchid error");
        expect_tx(('h2ac >> 2), 32'h0000_5a64, "SBI marchid");
        expect_tx(('h2b0 >> 2), 32'd0, "SBI mimpid error");
        expect_tx(('h2b4 >> 2), 32'd1, "SBI mimpid");
        expect_tx(('h3c8 >> 2), 32'd0, "SBI DBCN probe error");
        expect_tx(('h3cc >> 2), 32'd1, "SBI DBCN probe value");
        expect_tx(('h3d0 >> 2), 32'd0, "SBI TIME probe error");
        expect_tx(('h3d4 >> 2), 32'd1, "SBI TIME probe value");
        expect_tx(('h3d8 >> 2), 32'd0, "SBI IPI probe error");
        expect_tx(('h3dc >> 2), 32'd1, "SBI IPI probe value");
        expect_tx(('h3e0 >> 2), 32'd0, "SBI RFENCE probe error");
        expect_tx(('h3e4 >> 2), 32'd1, "SBI RFENCE probe value");
        expect_tx(('h3e8 >> 2), 32'd0, "SBI HSM probe error");
        expect_tx(('h3ec >> 2), 32'd1, "SBI HSM probe value");
        expect_tx(('h020 >> 2), 32'd0, "SBI PMU probe error");
        expect_tx(('h024 >> 2), 32'd1, "SBI PMU probe value");
        expect_tx(('h0a0 >> 2), 32'd0, "SBI BASE probe error");
        expect_tx(('h0a4 >> 2), 32'd1, "SBI BASE probe value");
        expect_tx(('h0a8 >> 2), 32'd0, "SBI SRST probe error");
        expect_tx(('h0ac >> 2), 32'd1, "SBI SRST probe value");
        expect_tx(('h0b0 >> 2), 32'd0, "SBI unknown probe error");
        expect_tx(('h0b4 >> 2), 32'd0, "SBI unknown probe value");
        expect_tx(('h400 >> 2), 32'd0, "SBI legacy set_timer probe error");
        expect_tx(('h404 >> 2), 32'd1, "SBI legacy set_timer probe value");
        expect_tx(('h408 >> 2), 32'd0, "SBI legacy console_putchar probe error");
        expect_tx(('h40c >> 2), 32'd1, "SBI legacy console_putchar probe value");
        expect_tx(('h410 >> 2), 32'd0, "SBI legacy console_getchar probe error");
        expect_tx(('h414 >> 2), 32'd1, "SBI legacy console_getchar probe value");
        expect_tx(('h418 >> 2), 32'd0, "SBI legacy clear_ipi probe error");
        expect_tx(('h41c >> 2), 32'd1, "SBI legacy clear_ipi probe value");
        expect_tx(('h420 >> 2), 32'd0, "SBI legacy send_ipi probe error");
        expect_tx(('h424 >> 2), 32'd1, "SBI legacy send_ipi probe value");
        expect_tx(('h428 >> 2), 32'd0, "SBI legacy remote_fence_i probe error");
        expect_tx(('h42c >> 2), 32'd1, "SBI legacy remote_fence_i probe value");
        expect_tx(('h430 >> 2), 32'd0, "SBI legacy remote_sfence_vma probe error");
        expect_tx(('h434 >> 2), 32'd1, "SBI legacy remote_sfence_vma probe value");
        expect_tx(('h438 >> 2), 32'd0, "SBI legacy remote_sfence_vma_asid probe error");
        expect_tx(('h43c >> 2), 32'd1, "SBI legacy remote_sfence_vma_asid probe value");
        expect_tx(('h440 >> 2), 32'd0, "SBI legacy shutdown probe error");
        expect_tx(('h444 >> 2), 32'd1, "SBI legacy shutdown probe value");
        expect_tx(('h270 >> 2), 32'd0, "SBI DBCN write byte error");
        expect_tx(('h274 >> 2), 32'd0, "SBI DBCN write byte value");
        expect_tx(('h380 >> 2), 32'd0, "SBI DBCN write buffer error");
        expect_tx(('h384 >> 2), 32'd3, "SBI DBCN write buffer byte count");
        expect_tx(('h388 >> 2), 32'd0, "SBI DBCN zero write error");
        expect_tx(('h38c >> 2), 32'd0, "SBI DBCN zero write byte count");
        expect_tx(('h0c0 >> 2), 32'd0, "SBI DBCN preserves a2");
        expect_tx(('h0c4 >> 2), 32'd33, "SBI DBCN preserves a3");
        expect_tx(('h0c8 >> 2), 32'd44, "SBI DBCN preserves a4");
        expect_tx(('h0cc >> 2), 32'd55, "SBI DBCN preserves a5");
        expect_tx(('h0d0 >> 2), 32'd0, "SBI DBCN preserves a6");
        expect_tx(('h0d4 >> 2), SBI_EXT_DBCN, "SBI DBCN preserves a7");
        expect_tx(('h0d8 >> 2), 32'hffff_fffb, "SBI DBCN write high address error");
        expect_tx(('h0dc >> 2), 32'd0, "SBI DBCN write high address value");
        expect_tx(('h390 >> 2), 32'd0, "SBI DBCN zero read error");
        expect_tx(('h394 >> 2), 32'd0, "SBI DBCN zero read byte count");
        expect_tx(('h364 >> 2), 32'h0000_5352, "SBI DBCN read ring buffer bytes");
        expect_tx(('h398 >> 2), 32'd0, "SBI DBCN read ring error");
        expect_tx(('h39c >> 2), 32'd2, "SBI DBCN read ring byte count");
        expect_tx(('h368 >> 2), 32'd81, "SBI DBCN read legacy buffer byte");
        expect_tx(('h288 >> 2), 32'd0, "SBI DBCN read error");
        expect_tx(('h28c >> 2), 32'd1, "SBI DBCN read byte count");
        expect_tx(('h0e0 >> 2), 32'hffff_fffb, "SBI DBCN read high address error");
        expect_tx(('h0e4 >> 2), 32'd0, "SBI DBCN read high address value");
        expect_tx(('h0e8 >> 2), 32'd0, "SBI DBCN full ring write error");
        expect_tx(('h0ec >> 2), 32'd0, "SBI DBCN full ring write byte count");
        expect_tx(('h240 >> 2), 32'hffff_fffe, "SBI BASE invalid fid error");
        expect_tx(('h244 >> 2), 32'd0, "SBI BASE invalid fid value");
        expect_tx(('h290 >> 2), 32'hffff_fffe, "SBI unsupported error");
        expect_tx(('h294 >> 2), 32'd0, "SBI unsupported value");
        expect_tx(('h248 >> 2), 32'hffff_fffe, "SBI TIME invalid fid error");
        expect_tx(('h24c >> 2), 32'd0, "SBI TIME invalid fid value");
        expect_tx(('h250 >> 2), 32'hffff_fffe, "SBI DBCN invalid fid error");
        expect_tx(('h254 >> 2), 32'd0, "SBI DBCN invalid fid value");
        expect_tx(('h278 >> 2), 32'd0, "SBI TIME set_timer error");
        expect_tx(('h27c >> 2), 32'd0, "SBI TIME set_timer value");
        if (scratch_tx_word('h280 >> 2) == 32'd0) begin
            $fatal(1, "SBI TIME set_timer did not publish a compare value");
        end
        expect_tx(('h0b8 >> 2), 32'd0, "SBI TIME set_timer max error");
        expect_tx(('h0bc >> 2), 32'd0, "SBI TIME set_timer max value");
        expect_tx(('h0f0 >> 2), 32'hffff_ffff, "SBI TIME set_timer max cmp low");
        expect_tx(('h0f4 >> 2), 32'hffff_ffff, "SBI TIME set_timer max cmp high");
        expect_tx(('h2b8 >> 2), 32'hffff_fffd, "SBI SRST invalid type error");
        expect_tx(('h2bc >> 2), 32'd0, "SBI SRST invalid type value");
        expect_tx(('h2c0 >> 2), 32'hffff_fffd, "SBI SRST invalid reason error");
        expect_tx(('h2c4 >> 2), 32'd0, "SBI SRST invalid reason value");
        expect_tx(('h348 >> 2), 32'hffff_fffe, "SBI SRST invalid fid error");
        expect_tx(('h34c >> 2), 32'd0, "SBI SRST invalid fid value");
        expect_tx(('h264 >> 2), 32'd0, "SBI SRST invalid calls must not publish reset magic");
        expect_tx(('h2c8 >> 2), 32'd0, "SBI IPI send hart0 error");
        expect_tx(('h2cc >> 2), 32'd0, "SBI IPI send hart0 value");
        expect_tx(('h0f8 >> 2), 32'd0, "SBI IPI empty mask nonzero base error");
        expect_tx(('h0fc >> 2), 32'd0, "SBI IPI empty mask nonzero base value");
        expect_tx(('h358 >> 2), 32'hffff_fffd, "SBI IPI invalid hart mask error");
        expect_tx(('h35c >> 2), 32'd0, "SBI IPI invalid hart mask value");
        expect_tx(('h360 >> 2), 32'hffff_fffe, "SBI IPI invalid fid error");
        expect_tx(('h3a0 >> 2), 32'd0, "SBI IPI invalid fid value");
        expect_tx(('h2d0 >> 2), 32'd0, "SBI RFENCE fence_i error");
        expect_tx(('h2d4 >> 2), 32'd0, "SBI RFENCE fence_i value");
        expect_tx(('h3a4 >> 2), 32'd0, "SBI RFENCE empty mask nonzero base error");
        expect_tx(('h3a8 >> 2), 32'd0, "SBI RFENCE empty mask nonzero base value");
        expect_tx(('h330 >> 2), 32'd0, "SBI RFENCE sfence_vma error");
        expect_tx(('h334 >> 2), 32'd0, "SBI RFENCE sfence_vma value");
        expect_tx(('h338 >> 2), 32'd0, "SBI RFENCE sfence_vma_asid error");
        expect_tx(('h33c >> 2), 32'd0, "SBI RFENCE sfence_vma_asid value");
        expect_tx(('h340 >> 2), 32'hffff_fffd, "SBI RFENCE invalid hart mask error");
        expect_tx(('h344 >> 2), 32'd0, "SBI RFENCE invalid hart mask value");
        expect_tx(('h350 >> 2), 32'hffff_fffe, "SBI RFENCE hfence unsupported error");
        expect_tx(('h354 >> 2), 32'd0, "SBI RFENCE hfence unsupported value");
        expect_tx(('h448 >> 2), 32'd0, "SBI legacy clear_ipi error");
        expect_tx(('h44c >> 2), 32'd0, "SBI legacy clear_ipi value");
        expect_tx(('h450 >> 2), 32'd0, "SBI legacy send_ipi error");
        expect_tx(('h454 >> 2), 32'd0, "SBI legacy send_ipi value");
        expect_tx(('h458 >> 2), 32'd0, "SBI legacy remote_fence_i error");
        expect_tx(('h45c >> 2), 32'd0, "SBI legacy remote_fence_i value");
        expect_tx(('h460 >> 2), 32'd0, "SBI legacy remote_sfence_vma error");
        expect_tx(('h464 >> 2), 32'd0, "SBI legacy remote_sfence_vma value");
        expect_tx(('h468 >> 2), 32'd0, "SBI legacy remote_sfence_vma_asid error");
        expect_tx(('h46c >> 2), 32'd0, "SBI legacy remote_sfence_vma_asid value");
        expect_tx(('h028 >> 2), 32'd0, "SBI PMU num counters error");
        expect_tx(('h02c >> 2), 32'd0, "SBI PMU num counters value");
        expect_tx(('h030 >> 2), 32'hffff_fffd, "SBI PMU get info invalid counter error");
        expect_tx(('h034 >> 2), 32'd0, "SBI PMU get info invalid counter value");
        expect_tx(('h038 >> 2), 32'hffff_fffe, "SBI PMU config matching unsupported error");
        expect_tx(('h03c >> 2), 32'd0, "SBI PMU config matching unsupported value");
        expect_tx(('h040 >> 2), 32'hffff_fffd, "SBI PMU start invalid counter error");
        expect_tx(('h044 >> 2), 32'd0, "SBI PMU start invalid counter value");
        expect_tx(('h048 >> 2), 32'hffff_fffd, "SBI PMU stop invalid counter error");
        expect_tx(('h04c >> 2), 32'd0, "SBI PMU stop invalid counter value");
        expect_tx(('h050 >> 2), 32'hffff_fffd, "SBI PMU fw read invalid counter error");
        expect_tx(('h054 >> 2), 32'd0, "SBI PMU fw read invalid counter value");
        expect_tx(('h058 >> 2), 32'hffff_fffd, "SBI PMU fw read hi invalid counter error");
        expect_tx(('h05c >> 2), 32'd0, "SBI PMU fw read hi invalid counter value");
        expect_tx(('h060 >> 2), 32'hffff_fffe, "SBI PMU snapshot unsupported error");
        expect_tx(('h064 >> 2), 32'd0, "SBI PMU snapshot unsupported value");
        expect_tx(('h068 >> 2), 32'hffff_fffe, "SBI PMU event get info unsupported error");
        expect_tx(('h06c >> 2), 32'd0, "SBI PMU event get info unsupported value");
        expect_tx(('h070 >> 2), 32'hffff_fffe, "SBI PMU invalid fid error");
        expect_tx(('h074 >> 2), 32'd0, "SBI PMU invalid fid value");
        expect_tx(('h078 >> 2), 32'hffff_fffd, "SBI PMU config matching reserved flags error");
        expect_tx(('h07c >> 2), 32'd0, "SBI PMU config matching reserved flags value");
        expect_tx(('h080 >> 2), 32'hffff_fffd, "SBI PMU snapshot reserved flags error");
        expect_tx(('h084 >> 2), 32'd0, "SBI PMU snapshot reserved flags value");
        expect_tx(('h088 >> 2), 32'hffff_fffd, "SBI PMU snapshot unaligned address error");
        expect_tx(('h08c >> 2), 32'd0, "SBI PMU snapshot unaligned address value");
        expect_tx(('h090 >> 2), 32'hffff_fffd, "SBI PMU event get info reserved flags error");
        expect_tx(('h094 >> 2), 32'd0, "SBI PMU event get info reserved flags value");
        expect_tx(('h098 >> 2), 32'hffff_fffd, "SBI PMU event get info unaligned address error");
        expect_tx(('h09c >> 2), 32'd0, "SBI PMU event get info unaligned address value");
        expect_tx(('h2d8 >> 2), 32'd0, "SBI HSM get_status error");
        expect_tx(('h2dc >> 2), 32'd0, "SBI HSM get_status started value");
        expect_tx(('h2e0 >> 2), 32'hffff_fffd, "SBI HSM invalid hart error");
        expect_tx(('h2e4 >> 2), 32'd0, "SBI HSM invalid hart value");
        expect_tx(('h2e8 >> 2), 32'hffff_fffa, "SBI HSM start boot hart error");
        expect_tx(('h2ec >> 2), 32'd0, "SBI HSM start boot hart value");
        expect_tx(('h2f0 >> 2), 32'hffff_fffe, "SBI HSM suspend unsupported error");
        expect_tx(('h2f4 >> 2), 32'd0, "SBI HSM suspend unsupported value");
        expect_tx(('h3f4 >> 2), 32'hffff_fffd, "SBI HSM suspend reserved type error");
        expect_tx(('h3f8 >> 2), 32'd0, "SBI HSM suspend reserved type value");
        expect_tx(('h2f8 >> 2), 32'hffff_ffff, "SBI HSM stop failed error");
        expect_tx(('h2fc >> 2), 32'd0, "SBI HSM stop failed value");
        expect_tx(('h000 >> 2), 32'h4342_415a, "SBI console ring bytes");
        expect_tx(('h104 >> 2), 32'd4, "SBI console ring total");
        expect_tx(('h208 >> 2), 32'd25, "SBI base call count");
        expect_tx(('h20c >> 2), 32'd4, "SBI console put count");
        expect_tx(('h210 >> 2), 32'd3, "SBI console get count");
        expect_tx(('h204 >> 2), 32'd2, "SBI time call count");
        expect_tx(('h218 >> 2), 32'd7, "SBI unsupported call count");
        expect_tx(('h258 >> 2), 32'd0, "SBI SRST reset type");
        expect_tx(('h25c >> 2), 32'd0, "SBI SRST reset reason");
        expect_tx(('h260 >> 2), SBI_EXT_SRST, "SBI SRST reset magic");

        if (burst_read_count == 32'd0 || dbg_icache_misses == 32'd0) begin
            $fatal(1, "real RV64 firmware test did not exercise DDR fetch path bursts=%0d im=%0d",
                   burst_read_count, dbg_icache_misses);
        end

        $display("tb_zx64_soc_real_sbi: PASS ih=%0d im=%0d dh=%0d dm=%0d bursts=%0d",
                 dbg_icache_hits, dbg_icache_misses,
                 dbg_dcache_hits, dbg_dcache_misses,
                 burst_read_count);
        $finish;
    end
endmodule
