module tb_zx64_soc_ddr;
    localparam int BRAM_WORDS = 1024;
    localparam int DDR_WORDS = 65536;
    localparam logic [31:0] RESET_CPU = 32'h8000_0000;
    localparam logic [31:0] DATA_CPU = 32'h8001_0000;
    localparam logic [31:0] DATA_PHYS = DATA_CPU - RESET_CPU;
    parameter bit USE_CORE5 = 1'b0;
    parameter bit RUN_SV39 = 1'b0;

    logic clk;
    logic rst_n;
    logic irq_external_i;
    logic virtio_blk_backend_irq;
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

    logic [31:0] ddr_mem [0:DDR_WORDS-1];
    logic [31:0] awaddr_q;
    logic        aw_seen_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic        w_seen_q;
    logic [31:0] araddr_q;
    logic [7:0]  arlen_q;
    logic [7:0]  rbeat_q;
    logic        rburst_active_q;
    logic [31:0] burst_read_count;
    logic [31:0] write_count;
    logic [7:0]  max_arlen_seen;
    integer      pcw;

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
        .reset_vector({32'd0, RESET_CPU}),
        .irq_external_i(irq_external_i),
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

    assign M_AXI_DDR_AWREADY = 1'b1;
    assign M_AXI_DDR_WREADY = 1'b1;
    assign M_AXI_DDR_ARREADY = !M_AXI_DDR_RVALID && !rburst_active_q;
    assign M_AXI_DDR_BID = 4'd0;
    assign M_AXI_DDR_BRESP = 2'd0;
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

    function automatic logic [31:0] enc_b(input logic signed [12:0] imm,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [6:0] opcode);
        enc_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] enc_r(input logic [6:0] funct7,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
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

    function automatic logic [31:0] ddr_read_word(input logic [31:0] addr);
        begin
            if (addr[31:2] < DDR_WORDS) begin
                ddr_read_word = ddr_mem[addr[31:2]];
            end else begin
                ddr_read_word = 32'd0;
            end
        end
    endfunction

    function automatic logic [63:0] ddr_read64(input logic [31:0] addr);
        ddr_read64 = {ddr_read_word(addr + 32'd4), ddr_read_word(addr)};
    endfunction

    task automatic ddr_write_word(input logic [31:0] addr,
                                  input logic [31:0] data,
                                  input logic [3:0]  wstrb);
        logic [31:0] new_word;
        begin
            if (addr[31:2] < DDR_WORDS) begin
                new_word = ddr_mem[addr[31:2]];
                for (int b = 0; b < 4; b++) begin
                    if (wstrb[b]) begin
                        new_word[b * 8 +: 8] = data[b * 8 +: 8];
                    end
                end
                ddr_mem[addr[31:2]] = new_word;
            end
        end
    endtask

    task automatic emit(input logic [31:0] inst);
        begin
            ddr_mem[pcw] = inst;
            pcw = pcw + 1;
        end
    endtask

    task automatic seek_cpu(input logic [31:0] cpu_addr);
        begin
            pcw = (cpu_addr - RESET_CPU) >> 2;
        end
    endtask

    task automatic ddr_put64(input logic [31:0] addr,
                             input logic [63:0] data);
        begin
            ddr_mem[addr[31:2]] = data[31:0];
            ddr_mem[addr[31:2] + 1] = data[63:32];
        end
    endtask

    task automatic clear_ddr;
        begin
            for (int i = 0; i < DDR_WORDS; i++) begin
                ddr_mem[i] = 32'd0;
            end
        end
    endtask

    task automatic expect64(input logic [31:0] addr,
                            input logic [63:0] expected,
                            input string label);
        logic [63:0] got;
        begin
            got = ddr_read64(addr);
            if (got !== expected) begin
                $fatal(1, "%s expected mem[%08x]=%016x got %016x pc=%016x instr=%08x state=%08x illegal=%0d",
                       label, addr, expected, got, dbg_pc, dbg_instr,
                       dbg_core_state, core_illegal);
            end
        end
    endtask

    task automatic expect_sv39_trap_ok;
        logic [63:0] mepc;
        logic [63:0] mcause;
        logic [63:0] mtval;
        begin
            mepc = ddr_read64(32'h0001_0200);
            mcause = ddr_read64(32'h0001_0208);
            mtval = ddr_read64(32'h0001_0210);
            if (!((mepc == 64'd0 && mcause == 64'd0 && mtval == 64'd0) ||
                  (mepc == 64'h0000_0000_8000_1020 && mcause == 64'd3))) begin
                $fatal(1, "DDR Sv39 unexpected trap mepc=%016x mcause=%016x mtval=%016x pc=%016x instr=%08x state=%08x illegal=%0d",
                       mepc, mcause, mtval, dbg_pc, dbg_instr,
                       dbg_core_state, core_illegal);
            end
        end
    endtask

    task automatic run_virtio_irq_dcache_test;
        localparam logic [63:0] OLD_VALUE = 64'h1122_3344_5566_7788;
        localparam logic [63:0] NEW_VALUE = 64'haabb_ccdd_eeff_0011;
        localparam logic [31:0] RESULT_PHYS = DATA_PHYS + 32'h0000_0100;
        logic [31:0] invalidates_before;
        logic [31:0] invalidates_after;
        bit saw_initial_load;
        begin
            rst_n = 1'b0;
            irq_external_i = 1'b0;
            virtio_blk_backend_irq = 1'b0;
            clear_ddr();

            pcw = 0;
            emit(enc_u(20'h80010, 5'd1, 7'b0110111));                  // lui   x1, 0x80010
            emit(enc_i(12'sd256, 5'd1, 3'b000, 5'd4, 7'b0010011));     // addi  x4, x1, 256
            emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd2, 7'b0000011));       // ld    x2, 0(x1)
            emit(enc_s(12'sd0, 5'd2, 5'd4, 3'b011, 7'b0100011));       // sd    x2, 0(x4)
            emit(enc_u(20'h10060, 5'd5, 7'b0110111));                  // lui   x5, 0x10060
            emit(enc_i(12'sh060, 5'd5, 3'b010, 5'd6, 7'b0000011));     // lw    x6, 0x60(x5)
            emit(enc_b(-13'sd4, 5'd0, 5'd6, 3'b000, 7'b1100011));      // beq   x6, x0, -4
            emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd3, 7'b0000011));       // ld    x3, 0(x1)
            emit(enc_s(12'sd8, 5'd3, 5'd4, 3'b011, 7'b0100011));       // sd    x3, 8(x4)
            emit(32'h0010_0073);                                       // ebreak

            ddr_put64(DATA_PHYS, OLD_VALUE);

            repeat (4) @(posedge clk);
            rst_n = 1'b1;

            saw_initial_load = 1'b0;
            for (int cycle = 0; cycle < 6000 && !saw_initial_load; cycle++) begin
                @(posedge clk);
                saw_initial_load = (ddr_read64(RESULT_PHYS) == OLD_VALUE);
            end
            if (!saw_initial_load) begin
                $fatal(1, "virtio IRQ dcache test did not cache/store initial value result=%016x pc=%016x instr=%08x state=%08x",
                       ddr_read64(RESULT_PHYS), dbg_pc, dbg_instr, dbg_core_state);
            end

            repeat (8) @(posedge clk);
            ddr_put64(DATA_PHYS, NEW_VALUE);
            invalidates_before = u_soc.perf_cache_invalidates;
            @(negedge clk);
            virtio_blk_backend_irq = 1'b1;
            @(posedge clk);
            @(negedge clk);
            virtio_blk_backend_irq = 1'b0;
            invalidates_after = u_soc.perf_cache_invalidates;
            if (invalidates_after != invalidates_before + 32'd1) begin
                $fatal(1, "virtio IRQ dcache invalidate count expected %0d got %0d",
                       invalidates_before + 32'd1, invalidates_after);
            end

            for (int cycle = 0; cycle < 6000 && !core_halted; cycle++) begin
                @(posedge clk);
            end

            if (!core_halted || core_illegal) begin
                $fatal(1, "virtio IRQ dcache test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                       core_halted, core_illegal, dbg_pc, dbg_instr, dbg_core_state);
            end
            expect64(RESULT_PHYS, OLD_VALUE, "virtio IRQ dcache old cached result");
            expect64(RESULT_PHYS + 32'd8, NEW_VALUE, "virtio IRQ dcache fresh result");

            invalidates_after = u_soc.perf_cache_invalidates;
            if (dbg_dcache_misses < 32'd2) begin
                $fatal(1, "virtio IRQ dcache test expected second load miss after invalidate dm=%0d",
                       dbg_dcache_misses);
            end

            $display("tb_zx64_soc_ddr: virtio IRQ dcache PASS invalidates=%0d dm=%0d",
                     invalidates_after, dbg_dcache_misses);
        end
    endtask

    task automatic run_fence_i_icache_test;
        localparam logic [31:0] RESULT_PHYS = DATA_PHYS + 32'h0000_0200;
        logic [31:0] invalidates_before;
        logic [31:0] invalidates_after;
        bit saw_first_result;
        begin
            rst_n = 1'b0;
            irq_external_i = 1'b0;
            virtio_blk_backend_irq = 1'b0;
            clear_ddr();

            pcw = 0;
            emit(enc_u(20'h80010, 5'd1, 7'b0110111));                  // lui   x1, 0x80010
            emit(enc_i(12'sd0, 5'd0, 3'b000, 5'd5, 7'b0010011));       // addi  x5, x0, 0
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));       // patch: addi x2, x0, 1
            emit(enc_i(12'sd1, 5'd5, 3'b000, 5'd5, 7'b0010011));       // addi  x5, x5, 1
            emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd6, 7'b0010011));       // addi  x6, x0, 1
            emit(enc_b(13'sd12, 5'd6, 5'd5, 3'b000, 7'b1100011));      // beq   x5, x6, first
            emit(enc_s(12'sd528, 5'd2, 5'd1, 3'b011, 7'b0100011));     // sd    x2, 528(x1)
            emit(32'h0010_0073);                                       // ebreak
            emit(enc_s(12'sd520, 5'd2, 5'd1, 3'b011, 7'b0100011));     // first: sd x2, 520(x1)
            emit(enc_u(20'h10060, 5'd8, 7'b0110111));                  // lui   x8, 0x10060
            emit(enc_i(12'sh060, 5'd8, 3'b010, 5'd9, 7'b0000011));     // poll: lw x9, 0x60(x8)
            emit(enc_b(-13'sd4, 5'd0, 5'd9, 3'b000, 7'b1100011));      // beq   x9, x0, poll
            emit(32'h0000_100f);                                       // fence.i
            emit(enc_j(-21'sd44, 5'd0, 7'b1101111));                   // jal   x0, patch

            repeat (4) @(posedge clk);
            rst_n = 1'b1;

            saw_first_result = 1'b0;
            for (int cycle = 0; cycle < 6000 && !saw_first_result; cycle++) begin
                @(posedge clk);
                saw_first_result = (ddr_read64(RESULT_PHYS + 32'd8) == 64'd1);
            end
            if (!saw_first_result) begin
                $fatal(1, "fence.i test did not cache and execute the original patch site result=%016x pc=%016x instr=%08x state=%08x",
                       ddr_read64(RESULT_PHYS + 32'd8), dbg_pc, dbg_instr, dbg_core_state);
            end

            ddr_mem[2] = enc_i(12'sd2, 5'd0, 3'b000, 5'd2, 7'b0010011);
            invalidates_before = u_soc.perf_cache_invalidates;
            @(negedge clk);
            virtio_blk_backend_irq = 1'b1;
            @(posedge clk);
            @(negedge clk);
            virtio_blk_backend_irq = 1'b0;

            for (int cycle = 0; cycle < 6000 && !core_halted; cycle++) begin
                @(posedge clk);
            end

            if (!core_halted || core_illegal) begin
                $fatal(1, "fence.i test did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                       core_halted, core_illegal, dbg_pc, dbg_instr, dbg_core_state);
            end
            expect64(RESULT_PHYS + 32'd8, 64'd1, "fence.i original cached execution");
            expect64(RESULT_PHYS + 32'd16, 64'd2, "fence.i patched execution");

            invalidates_after = u_soc.perf_cache_invalidates;
            if (invalidates_after < invalidates_before + 32'd2) begin
                $fatal(1, "fence.i test expected virtio and fence.i invalidates before=%0d after=%0d",
                       invalidates_before, invalidates_after);
            end

            $display("tb_zx64_soc_ddr: fence.i icache PASS invalidates=%0d", invalidates_after);
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_AXI_DDR_BVALID <= 1'b0;
            M_AXI_DDR_RVALID <= 1'b0;
            M_AXI_DDR_RDATA <= 32'd0;
            awaddr_q <= 32'd0;
            aw_seen_q <= 1'b0;
            wdata_q <= 32'd0;
            wstrb_q <= 4'd0;
            w_seen_q <= 1'b0;
            araddr_q <= 32'd0;
            arlen_q <= 8'd0;
            rbeat_q <= 8'd0;
            rburst_active_q <= 1'b0;
            burst_read_count <= 32'd0;
            write_count <= 32'd0;
            max_arlen_seen <= 8'd0;
        end else begin
            if (M_AXI_DDR_BVALID && M_AXI_DDR_BREADY) begin
                M_AXI_DDR_BVALID <= 1'b0;
            end
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

            if (M_AXI_DDR_AWVALID && M_AXI_DDR_AWREADY) begin
                awaddr_q <= M_AXI_DDR_AWADDR;
                aw_seen_q <= 1'b1;
            end
            if (M_AXI_DDR_WVALID && M_AXI_DDR_WREADY) begin
                wdata_q <= M_AXI_DDR_WDATA;
                wstrb_q <= M_AXI_DDR_WSTRB;
                w_seen_q <= 1'b1;
            end

            if (!M_AXI_DDR_BVALID &&
                ((aw_seen_q || (M_AXI_DDR_AWVALID && M_AXI_DDR_AWREADY)) &&
                 (w_seen_q || (M_AXI_DDR_WVALID && M_AXI_DDR_WREADY)))) begin
                ddr_write_word((M_AXI_DDR_AWVALID && M_AXI_DDR_AWREADY) ? M_AXI_DDR_AWADDR : awaddr_q,
                               (M_AXI_DDR_WVALID && M_AXI_DDR_WREADY) ? M_AXI_DDR_WDATA : wdata_q,
                               (M_AXI_DDR_WVALID && M_AXI_DDR_WREADY) ? M_AXI_DDR_WSTRB : wstrb_q);
                M_AXI_DDR_BVALID <= 1'b1;
                aw_seen_q <= 1'b0;
                w_seen_q <= 1'b0;
                write_count <= write_count + 32'd1;
            end

            if (M_AXI_DDR_ARVALID && M_AXI_DDR_ARREADY) begin
                araddr_q <= M_AXI_DDR_ARADDR;
                arlen_q <= M_AXI_DDR_ARLEN;
                rbeat_q <= 8'd0;
                rburst_active_q <= 1'b1;
                if (M_AXI_DDR_ARLEN != 8'd0) begin
                    burst_read_count <= burst_read_count + 32'd1;
                end
                if (M_AXI_DDR_ARLEN > max_arlen_seen) begin
                    max_arlen_seen <= M_AXI_DDR_ARLEN;
                end
                M_AXI_DDR_RDATA <= ddr_read_word(M_AXI_DDR_ARADDR);
                M_AXI_DDR_RVALID <= 1'b1;
            end
        end
    end

    initial begin
        irq_external_i = 1'b0;
        virtio_blk_backend_irq = 1'b0;
        rst_n = 1'b0;

        clear_ddr();

        if (!RUN_SV39) begin
        pcw = 0;
        emit(enc_u(20'h80010, 5'd1, 7'b0110111));                  // lui   x1, 0x80010
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd2, 7'b0000011));       // ld    x2, 0(x1)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd3, 7'b0000011));       // ld    x3, 0(x1)
        emit(enc_s(12'sd8, 5'd3, 5'd1, 3'b011, 7'b0100011));       // sd    x3, 8(x1)
        emit(enc_s(12'sd0, 5'd0, 5'd1, 3'b011, 7'b0100011));       // sd    x0, 0(x1)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd4, 7'b0000011));       // ld    x4, 0(x1)
        emit(enc_s(12'sd16, 5'd4, 5'd1, 3'b011, 7'b0100011));      // sd    x4, 16(x1)
        emit(32'h0010_0073);                                       // ebreak

        ddr_mem[DATA_PHYS[31:2]] = 32'h5566_7788;
        ddr_mem[DATA_PHYS[31:2] + 1] = 32'h1122_3344;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 6000 && !core_halted; cycle++) begin
            @(posedge clk);
        end

        if (!core_halted || core_illegal) begin
            $fatal(1, "ZX64 DDR SoC smoke did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   core_halted, core_illegal, dbg_pc, dbg_instr, dbg_core_state);
        end

        expect64(DATA_PHYS, 64'h0000_0000_0000_0000, "DDR store zero");
        expect64(DATA_PHYS + 32'd8, 64'h1122_3344_5566_7788, "DDR store copied value");
        expect64(DATA_PHYS + 32'd16, 64'h0000_0000_0000_0000, "DDR post-invalidate load");

        if (dbg_icache_hits == 32'd0 || dbg_icache_misses == 32'd0 ||
            dbg_dcache_hits == 32'd0 || dbg_dcache_misses < 32'd2) begin
            $fatal(1, "ZX64 DDR cache counters unexpected ih=%0d im=%0d dh=%0d dm=%0d",
                   dbg_icache_hits, dbg_icache_misses,
                   dbg_dcache_hits, dbg_dcache_misses);
        end
        if (max_arlen_seen < 8'd7 || burst_read_count < 32'd2 || write_count < 32'd6) begin
            $fatal(1, "ZX64 DDR AXI activity too small max_arlen=%0d bursts=%0d writes=%0d",
                   max_arlen_seen, burst_read_count, write_count);
        end

	        $display("tb_zx64_soc_ddr: DDR smoke PASS ih=%0d im=%0d dh=%0d dm=%0d bursts=%0d writes=%0d",
	                 dbg_icache_hits, dbg_icache_misses,
	                 dbg_dcache_hits, dbg_dcache_misses,
	                 burst_read_count, write_count);
	        run_virtio_irq_dcache_test();
	        run_fence_i_icache_test();
	        $display("tb_zx64_soc_ddr: PASS");
	        $finish;
        end

        if (RUN_SV39) begin
        ddr_put64(32'h0000_2010, 64'h0000_0000_2000_00cf);         // root[2]: 0x80000000 1GiB RWXAD leaf

        pcw = 0;
        emit(enc_i(12'sd1, 5'd0, 3'b000, 5'd2, 7'b0010011));       // addi  x2, x0, 1
        emit(enc_i(12'sh03f, 5'd2, 3'b001, 5'd2, 7'b0010011));     // slli  x2, x2, 63
        emit(enc_u(20'h00080, 5'd3, 7'b0110111));                  // lui   x3, 0x80
        emit(enc_i(12'sd2, 5'd3, 3'b000, 5'd3, 7'b0010011));       // addi  x3, x3, 2
        emit(enc_r(7'd0, 5'd3, 5'd2, 3'b000, 5'd2, 7'b0110011));   // add   x2, x2, x3
        emit(enc_csr(12'h180, 5'd2, 3'b001, 5'd0));                // csrw  satp, x2
        emit(32'h1200_0073);                                       // sfence.vma x0, x0
        emit(enc_u(20'h00001, 5'd3, 7'b0110111));                  // lui   x3, 0x1
        emit(enc_i(-12'sd2048, 5'd3, 3'b000, 5'd3, 7'b0010011));   // addi  x3, x3, -2048
        emit(enc_csr(12'h300, 5'd3, 3'b001, 5'd0));                // csrw  mstatus, x3 (MPP=S)
        emit(enc_u(20'h40000, 5'd7, 7'b0110111));                  // lui   x7, 0x40000
        emit(enc_i(12'sd1, 5'd7, 3'b001, 5'd7, 7'b0010011));       // slli  x7, x7, 1
        emit(enc_u(20'h00003, 5'd6, 7'b0110111));                  // lui   x6, 0x3
        emit(enc_r(7'd0, 5'd6, 5'd7, 3'b000, 5'd7, 7'b0110011));   // add   x7, x7, x6
        emit(enc_csr(12'h305, 5'd7, 3'b001, 5'd0));                // csrw  mtvec, x7
        emit(enc_u(20'h40000, 5'd4, 7'b0110111));                  // lui   x4, 0x40000
        emit(enc_i(12'sd1, 5'd4, 3'b001, 5'd4, 7'b0010011));       // slli  x4, x4, 1
        emit(enc_u(20'h00001, 5'd6, 7'b0110111));                  // lui   x6, 0x1
        emit(enc_r(7'd0, 5'd6, 5'd4, 3'b000, 5'd4, 7'b0110011));   // add   x4, x4, x6
        emit(enc_csr(12'h341, 5'd4, 3'b001, 5'd0));                // csrw  mepc, x4
        emit(32'h3020_0073);                                       // mret  to VA 0x80001000

        seek_cpu(32'h8000_1000);
        emit(enc_u(20'h40008, 5'd1, 7'b0110111));                  // lui   x1, 0x40008
        emit(enc_i(12'sd1, 5'd1, 3'b001, 5'd1, 7'b0010011));       // slli  x1, x1, 1
        emit(enc_i(12'sh07d, 5'd0, 3'b000, 5'd2, 7'b0010011));     // addi  x2, x0, 0x7d
        emit(enc_s(12'sd0, 5'd2, 5'd1, 3'b011, 7'b0100011));       // sd    x2, 0(x1)
        emit(enc_i(12'sd0, 5'd1, 3'b011, 5'd3, 7'b0000011));       // ld    x3, 0(x1)
        emit(enc_s(12'sd256, 5'd3, 5'd1, 3'b011, 7'b0100011));     // sd    x3, 256(x1)
        emit(enc_csr(12'h180, 5'd0, 3'b010, 5'd5));                // csrr  x5, satp
        emit(enc_s(12'sd264, 5'd5, 5'd1, 3'b011, 7'b0100011));     // sd    x5, 264(x1)
        emit(32'h0010_0073);                                       // ebreak

        seek_cpu(32'h8000_3000);
        emit(enc_u(20'h40008, 5'd1, 7'b0110111));                  // lui   x1, 0x40008
        emit(enc_i(12'sd1, 5'd1, 3'b001, 5'd1, 7'b0010011));       // slli  x1, x1, 1
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd2));                // csrr  x2, mepc
        emit(enc_s(12'sd512, 5'd2, 5'd1, 3'b011, 7'b0100011));     // sd    x2, 512(x1)
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd3));                // csrr  x3, mcause
        emit(enc_s(12'sd520, 5'd3, 5'd1, 3'b011, 7'b0100011));     // sd    x3, 520(x1)
        emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd4));                // csrr  x4, mtval
        emit(enc_s(12'sd528, 5'd4, 5'd1, 3'b011, 7'b0100011));     // sd    x4, 528(x1)
        emit(32'h0010_0073);                                       // ebreak

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        for (int cycle = 0; cycle < 10000 && !core_halted; cycle++) begin
            @(posedge clk);
        end

        if (!core_halted || core_illegal) begin
            $fatal(1, "ZX64 DDR Sv39 smoke did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   core_halted, core_illegal, dbg_pc, dbg_instr, dbg_core_state);
        end

        expect64(32'h0001_0000, 64'h0000_0000_0000_007d, "DDR Sv39 translated store");
        expect64(32'h0001_0100, 64'h0000_0000_0000_007d, "DDR Sv39 translated load");
        expect64(32'h0001_0108, 64'h8000_0000_0008_0002, "DDR Sv39 satp readback");
        expect_sv39_trap_ok();

        if (dbg_icache_hits == 32'd0 || dbg_icache_misses == 32'd0 ||
            dbg_dcache_misses < 32'd2 || burst_read_count < 32'd3) begin
            $fatal(1, "ZX64 DDR Sv39 activity too small ih=%0d im=%0d dh=%0d dm=%0d bursts=%0d",
                   dbg_icache_hits, dbg_icache_misses,
                   dbg_dcache_hits, dbg_dcache_misses, burst_read_count);
        end

        $display("tb_zx64_soc_ddr: Sv39 PASS ih=%0d im=%0d dh=%0d dm=%0d bursts=%0d writes=%0d",
                 dbg_icache_hits, dbg_icache_misses,
                 dbg_dcache_hits, dbg_dcache_misses,
                 burst_read_count, write_count);
        $display("tb_zx64_soc_ddr: PASS");
        $finish;
        end
    end
endmodule
