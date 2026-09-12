module tb_zx64_soc_mmio;
    localparam int BRAM_WORDS = 1024;
    parameter bit USE_CORE5 = 1'b1;

    logic clk;
    logic rst_n;
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
	logic        virtio_blk_backend_irq;
	logic        virtio_input_backend_irq;
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
    integer pcw;

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
        .reset_vector(64'd0),
        .irq_external_i(1'b0),
        .virtio_blk_capacity_sectors(64'd0),
		.virtio_blk_backend_irq(virtio_blk_backend_irq),
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
        .virtio_input_backend_irq(virtio_input_backend_irq),
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
    assign M_AXI_DDR_ARREADY = 1'b0;
    assign M_AXI_DDR_RID = 4'd0;
    assign M_AXI_DDR_RDATA = 32'd0;
    assign M_AXI_DDR_RRESP = 2'd0;
    assign M_AXI_DDR_RLAST = 1'b0;
    assign M_AXI_DDR_RVALID = 1'b0;

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

    task automatic emit(input logic [31:0] inst);
        begin
            if (pcw[0]) begin
                u_soc.u_ram.mem[pcw >> 1][63:32] = inst;
            end else begin
                u_soc.u_ram.mem[pcw >> 1][31:0] = inst;
            end
            pcw = pcw + 1;
        end
    endtask

    task automatic expect64(input int idx, input logic [63:0] expected, input string label);
        begin
            if (u_soc.u_ram.mem[idx] !== expected) begin
                $fatal(1, "%s expected mem[%0d]=%016x got %016x pc=%016x instr=%08x state=%08x illegal=%0d",
                       label, idx, expected, u_soc.u_ram.mem[idx],
                       dbg_pc, dbg_instr, dbg_core_state, core_illegal);
            end
        end
    endtask

	initial begin
		rst_n = 1'b0;
		virtio_blk_backend_irq = 1'b0;
		virtio_input_backend_irq = 1'b0;
		for (int i = 0; i < BRAM_WORDS; i++) begin
			u_soc.u_ram.mem[i] = 64'd0;
		end

        pcw = 0;
        emit(enc_i(12'sd1024, 5'd0, 3'b000, 5'd1, 7'b0010011));     // addi x1, x0, 1024
        emit(enc_u(20'h10060, 5'd2, 7'b0110111));                  // lui  x2, 0x10060
        emit(enc_i(12'sd0, 5'd2, 3'b010, 5'd3, 7'b0000011));        // lw   x3, 0(x2)
        emit(enc_s(12'sd0, 5'd3, 5'd1, 3'b011, 7'b0100011));        // sd   x3, 0(x1)
        emit(enc_i(12'sd8, 5'd2, 3'b010, 5'd3, 7'b0000011));        // lw   x3, 8(x2)
        emit(enc_s(12'sd8, 5'd3, 5'd1, 3'b011, 7'b0100011));        // sd   x3, 8(x1)
        emit(enc_u(20'h10090, 5'd8, 7'b0110111));                  // lui  x8, 0x10090
        emit(enc_i(12'sd0, 5'd8, 3'b010, 5'd3, 7'b0000011));        // lw   x3, 0(x8)
        emit(enc_s(12'sd16, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd   x3, 16(x1)
        emit(enc_i(12'sd8, 5'd8, 3'b010, 5'd3, 7'b0000011));        // lw   x3, 8(x8)
        emit(enc_s(12'sd24, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd   x3, 24(x1)
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd4, 7'b0010011));        // addi x4, x0, 1
        emit(enc_i(12'sd6, 5'd0, 3'b000, 5'd5, 7'b0010011));        // addi x5, x0, 6
        emit(enc_u(20'h0c000, 5'd6, 7'b0110111));                  // lui  x6, 0x0c000
        emit(enc_s(12'sd4, 5'd4, 5'd6, 3'b010, 7'b0100011));        // sw   x4, 4(x6)
        emit(enc_s(12'sd8, 5'd4, 5'd6, 3'b010, 7'b0100011));        // sw   x4, 8(x6)
        emit(enc_u(20'h0c002, 5'd6, 7'b0110111));                  // lui  x6, 0x0c002
        emit(enc_s(12'sd0, 5'd5, 5'd6, 3'b010, 7'b0100011));        // sw   x5, 0(x6)
		emit(enc_u(20'h0c200, 5'd6, 7'b0110111));                  // lui  x6, 0x0c200
		emit(enc_i(12'sd4, 5'd6, 3'b010, 5'd7, 7'b0000011));        // lw   x7, 4(x6)
        emit(enc_s(12'sd32, 5'd7, 5'd1, 3'b011, 7'b0100011));       // sd   x7, 32(x1)
        emit(enc_s(12'sd4, 5'd7, 5'd6, 3'b010, 7'b0100011));        // sw   x7, 4(x6)
		emit(enc_i(12'sd4, 5'd6, 3'b010, 5'd7, 7'b0000011));        // lw   x7, 4(x6)
        emit(enc_s(12'sd40, 5'd7, 5'd1, 3'b011, 7'b0100011));       // sd   x7, 40(x1)
		emit(32'h0010_0073);                                        // ebreak

		repeat (4) @(posedge clk);
		rst_n = 1'b1;
		repeat (2) @(posedge clk);
		virtio_blk_backend_irq = 1'b1;
		virtio_input_backend_irq = 1'b1;
		@(posedge clk);
		virtio_blk_backend_irq = 1'b0;
		virtio_input_backend_irq = 1'b0;

		for (int cycle = 0; cycle < 1000 && !core_halted; cycle++) begin
            @(posedge clk);
        end

        if (!core_halted || core_illegal) begin
            $fatal(1, "ZX64 SoC MMIO smoke did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   core_halted, core_illegal, dbg_pc, dbg_instr, dbg_core_state);
        end

        expect64(128, 64'h0000_0000_7472_6976, "SoC virtio magic");
        expect64(129, 64'h0000_0000_0000_0002, "SoC virtio device id");
        expect64(130, 64'h0000_0000_7472_6976, "SoC virtio-input magic");
        expect64(131, 64'h0000_0000_0000_0012, "SoC virtio-input device id");
        expect64(132, 64'h0000_0000_0000_0002, "SoC PLIC input claim");
        expect64(133, 64'h0000_0000_0000_0001, "SoC PLIC block claim");

        $display("tb_zx64_soc_mmio: PASS");
        $finish;
    end
endmodule
