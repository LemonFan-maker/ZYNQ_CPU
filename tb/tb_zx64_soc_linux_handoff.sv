module tb_zx64_soc_linux_handoff;
    localparam int BRAM_WORDS = 1024;
    localparam int KERNEL_WORDS = 1024;
    localparam int RESULT_WORDS = 128;
    localparam int DTB_WORDS = 64;
    localparam int FW_ENTRY = 32'h0000_0000;
    localparam int M_TRAP = 32'h0000_0100;
    localparam logic [31:0] DDR_CPU_BASE = 32'h8000_0000;
    localparam logic [31:0] KERNEL_CPU = 32'h8020_0000;
    localparam logic [31:0] KERNEL_PHYS = KERNEL_CPU - DDR_CPU_BASE;
    localparam logic [31:0] KERNEL_TRAP_CPU = KERNEL_CPU + 32'h0000_0100;
    localparam logic [31:0] RESULT_CPU = 32'h8000_2000;
    localparam logic [31:0] RESULT_PHYS = RESULT_CPU - DDR_CPU_BASE;
    localparam logic [31:0] DTB_CPU = 32'h8200_0000;
    localparam logic [31:0] DTB_PHYS = DTB_CPU - DDR_CPU_BASE;
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
    logic [31:0] result_mem [0:RESULT_WORDS-1];
    logic [31:0] dtb_mem [0:DTB_WORDS-1];
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
    integer      bram_pcw;
    integer      kernel_pcw;

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

    assign M_AXI_DDR_AWREADY = 1'b1;
    assign M_AXI_DDR_WREADY = 1'b1;
    assign M_AXI_DDR_ARREADY = !M_AXI_DDR_RVALID && !rburst_active_q;
    assign M_AXI_DDR_BID = 4'd0;
    assign M_AXI_DDR_BRESP = 2'd0;
    assign M_AXI_DDR_RID = 4'd0;
    assign M_AXI_DDR_RRESP = 2'd0;
    assign M_AXI_DDR_RLAST = M_AXI_DDR_RVALID && (rbeat_q == arlen_q);

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

    function automatic logic [31:0] ddr_read_word(input logic [31:0] addr);
        begin
            ddr_read_word = 32'd0;
            if (addr >= KERNEL_PHYS && addr < KERNEL_PHYS + KERNEL_WORDS * 4) begin
                ddr_read_word = kernel_mem[(addr - KERNEL_PHYS) >> 2];
            end else if (addr >= RESULT_PHYS && addr < RESULT_PHYS + RESULT_WORDS * 4) begin
                ddr_read_word = result_mem[(addr - RESULT_PHYS) >> 2];
            end else if (addr >= DTB_PHYS && addr < DTB_PHYS + DTB_WORDS * 4) begin
                ddr_read_word = dtb_mem[(addr - DTB_PHYS) >> 2];
            end
        end
    endfunction

    function automatic logic [63:0] result_read64(input logic [31:0] offset);
        result_read64 = {result_mem[(offset >> 2) + 1], result_mem[offset >> 2]};
    endfunction

    task automatic ddr_write_word(input logic [31:0] addr,
                                  input logic [31:0] data,
                                  input logic [3:0]  wstrb);
        logic [31:0] new_word;
        begin
            if (addr >= RESULT_PHYS && addr < RESULT_PHYS + RESULT_WORDS * 4) begin
                new_word = result_mem[(addr - RESULT_PHYS) >> 2];
                for (int b = 0; b < 4; b++) begin
                    if (wstrb[b]) begin
                        new_word[b * 8 +: 8] = data[b * 8 +: 8];
                    end
                end
                result_mem[(addr - RESULT_PHYS) >> 2] = new_word;
            end
        end
    endtask

    task automatic bram_emit(input logic [31:0] inst);
        begin
            if (bram_pcw[0]) begin
                u_soc.u_ram.mem[bram_pcw >> 1][63:32] = inst;
            end else begin
                u_soc.u_ram.mem[bram_pcw >> 1][31:0] = inst;
            end
            bram_pcw = bram_pcw + 1;
        end
    endtask

    task automatic bram_seek(input int byte_addr);
        begin
            bram_pcw = byte_addr >> 2;
        end
    endtask

    task automatic bram_j(input int target_byte);
        logic signed [20:0] delta;
        begin
            delta = target_byte - (bram_pcw << 2);
            bram_emit(enc_j(delta, 5'd0, 7'b1101111));
        end
    endtask

    task automatic bram_beq(input logic [4:0] rs1,
                            input logic [4:0] rs2,
                            input int target_byte);
        logic signed [12:0] delta;
        begin
            delta = target_byte - (bram_pcw << 2);
            bram_emit(enc_b(delta, rs2, rs1, 3'b000, 7'b1100011));
        end
    endtask

    task automatic bram_bne(input logic [4:0] rs1,
                            input logic [4:0] rs2,
                            input int target_byte);
        logic signed [12:0] delta;
        begin
            delta = target_byte - (bram_pcw << 2);
            bram_emit(enc_b(delta, rs2, rs1, 3'b001, 7'b1100011));
        end
    endtask

    task automatic kernel_emit(input logic [31:0] inst);
        begin
            kernel_mem[kernel_pcw] = inst;
            kernel_pcw = kernel_pcw + 1;
        end
    endtask

    task automatic kernel_seek(input int offset);
        begin
            kernel_pcw = offset >> 2;
        end
    endtask

    task automatic li_small_bram(input logic [4:0] rd, input logic signed [11:0] imm);
        begin
            bram_emit(enc_i(imm, 5'd0, 3'b000, rd, 7'b0010011));
        end
    endtask

    task automatic li_small_kernel(input logic [4:0] rd, input logic signed [11:0] imm);
        begin
            kernel_emit(enc_i(imm, 5'd0, 3'b000, rd, 7'b0010011));
        end
    endtask

    task automatic li_addr_base_bram(input logic [4:0] rd);
        begin
            li_small_bram(rd, 12'sd1);
            bram_emit(enc_i(12'sd31, rd, 3'b001, rd, 7'b0010011));
        end
    endtask

    task automatic li_addr_base_kernel(input logic [4:0] rd);
        begin
            li_small_kernel(rd, 12'sd1);
            kernel_emit(enc_i(12'sd31, rd, 3'b001, rd, 7'b0010011));
        end
    endtask

    task automatic li_dtb_addr_bram(input logic [4:0] rd, input logic [4:0] tmp);
        begin
            li_addr_base_bram(rd);
            li_small_bram(tmp, 12'sd1);
            bram_emit(enc_i(12'sd25, tmp, 3'b001, tmp, 7'b0010011));
            bram_emit(enc_r(7'b0000000, tmp, rd, 3'b000, rd, 7'b0110011));
        end
    endtask

    task automatic li_kernel_addr_bram(input logic [4:0] rd, input logic [4:0] tmp);
        begin
            li_addr_base_bram(rd);
            li_small_bram(tmp, 12'sd1);
            bram_emit(enc_i(12'sd21, tmp, 3'b001, tmp, 7'b0010011));
            bram_emit(enc_r(7'b0000000, tmp, rd, 3'b000, rd, 7'b0110011));
        end
    endtask

    task automatic li_result_addr_bram(input logic [4:0] rd, input logic [4:0] tmp);
        begin
            li_addr_base_bram(rd);
            li_small_bram(tmp, 12'sd1);
            bram_emit(enc_i(12'sd13, tmp, 3'b001, tmp, 7'b0010011));
            bram_emit(enc_r(7'b0000000, tmp, rd, 3'b000, rd, 7'b0110011));
        end
    endtask

    task automatic li_result_addr_kernel(input logic [4:0] rd, input logic [4:0] tmp);
        begin
            li_addr_base_kernel(rd);
            li_small_kernel(tmp, 12'sd1);
            kernel_emit(enc_i(12'sd13, tmp, 3'b001, tmp, 7'b0010011));
            kernel_emit(enc_r(7'b0000000, tmp, rd, 3'b000, rd, 7'b0110011));
        end
    endtask

    task automatic li_kernel_trap_addr(input logic [4:0] rd, input logic [4:0] tmp);
        begin
            li_addr_base_kernel(rd);
            li_small_kernel(tmp, 12'sd1);
            kernel_emit(enc_i(12'sd21, tmp, 3'b001, tmp, 7'b0010011));
            kernel_emit(enc_r(7'b0000000, tmp, rd, 3'b000, rd, 7'b0110011));
            kernel_emit(enc_i(12'sd256, rd, 3'b000, rd, 7'b0010011));
        end
    endtask

    task automatic expect_result64(input logic [31:0] offset,
                                   input logic [63:0] expected,
                                   input string label);
        logic [63:0] got;
        begin
            got = result_read64(offset);
            if (got !== expected) begin
                $fatal(1, "%s expected result[%08x]=%016x got %016x pc=%016x instr=%08x state=%08x illegal=%0d",
                       label, offset, expected, got, dbg_pc, dbg_instr,
                       dbg_core_state, core_illegal);
            end
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
        rst_n = 1'b0;

        for (int i = 0; i < BRAM_WORDS; i++) begin
            u_soc.u_ram.mem[i] = 64'd0;
        end
        for (int i = 0; i < KERNEL_WORDS; i++) begin
            kernel_mem[i] = 32'h0010_0073;
        end
        for (int i = 0; i < RESULT_WORDS; i++) begin
            result_mem[i] = 32'd0;
        end
        for (int i = 0; i < DTB_WORDS; i++) begin
            dtb_mem[i] = 32'd0;
        end
        dtb_mem[0] = 32'hd00d_feed;

        bram_seek(FW_ENTRY);
        bram_emit(enc_u(20'h10010, 5'd29, 7'b0110111));                 // lui   t4, 0x10010
        bram_emit(enc_s(12'sd0, 5'd0, 5'd29, 3'b010, 7'b0100011));      // sw    x0, mtimecmp_lo
        bram_emit(enc_s(12'sd4, 5'd0, 5'd29, 3'b010, 7'b0100011));      // sw    x0, mtimecmp_hi
        li_small_bram(5'd5, M_TRAP[11:0]);
        bram_emit(enc_csr(12'h305, 5'd5, 3'b001, 5'd0));                // csrw  mtvec, t0
        li_small_bram(5'd5, 12'sd32);
        bram_emit(enc_csr(12'h303, 5'd5, 3'b001, 5'd0));                // csrw  mideleg, t0
        li_small_bram(5'd10, 12'sd0);                                   // li    a0, 0
        li_dtb_addr_bram(5'd11, 5'd12);                                  // li    a1, DTB_CPU
        li_kernel_addr_bram(5'd5, 5'd6);
        bram_emit(enc_csr(12'h341, 5'd5, 3'b001, 5'd0));                // csrw  mepc, t0
        bram_emit(enc_u(20'h00001, 5'd5, 7'b0110111));                  // lui   t0, 0x1
        bram_emit(enc_i(-12'sd2048, 5'd5, 3'b000, 5'd5, 7'b0010011));   // addi  t0, t0, -2048
        bram_emit(enc_csr(12'h300, 5'd5, 3'b001, 5'd0));                // csrw  mstatus, t0 (MPP=S)
        bram_emit(32'h3020_0073);                                        // mret

        bram_seek(M_TRAP);
        bram_emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd6));                // csrr  t1, mcause
        li_small_bram(5'd7, 12'sd9);
        bram_bne(5'd6, 5'd7, 32'h0000_0200);
        bram_emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd5));                // csrr  t0, mepc
        bram_emit(enc_i(12'sd4, 5'd5, 3'b000, 5'd5, 7'b0010011));       // addi  t0, t0, 4
        bram_emit(enc_csr(12'h341, 5'd5, 3'b001, 5'd0));                // csrw  mepc, t0
        li_small_bram(5'd7, 12'sd16);
        bram_beq(5'd17, 5'd7, 32'h0000_0140);                          // beq   a7, base
        bram_beq(5'd17, 5'd0, 32'h0000_01a0);                           // beq   a7, set_timer
        bram_j(32'h0000_01f0);

        bram_seek(32'h0000_0140);
        bram_beq(5'd16, 5'd0, 32'h0000_0170);                          // fid 0: spec version
        li_small_bram(5'd7, 12'sd3);
        bram_beq(5'd16, 5'd7, 32'h0000_0180);                          // fid 3: probe extension
        bram_j(32'h0000_01f0);

        bram_seek(32'h0000_0170);
        li_small_bram(5'd10, 12'sd0);
        li_small_bram(5'd11, 12'sd2);
        bram_emit(32'h3020_0073);                                        // mret

        bram_seek(32'h0000_0180);
        li_small_bram(5'd10, 12'sd0);
        li_small_bram(5'd11, 12'sd1);
        bram_emit(32'h3020_0073);                                        // mret

        bram_seek(32'h0000_01a0);
        bram_emit(enc_u(20'h10010, 5'd29, 7'b0110111));                 // lui   t4, 0x10010
        li_small_bram(5'd7, -12'sd1);
        bram_emit(enc_s(12'sd12, 5'd7, 5'd29, 3'b010, 7'b0100011));     // sw    -1, mtimecmp_hi
        bram_emit(enc_s(12'sd8, 5'd10, 5'd29, 3'b010, 7'b0100011));     // sw    a0, mtimecmp_lo
        bram_emit(enc_s(12'sd12, 5'd11, 5'd29, 3'b010, 7'b0100011));    // sw    a1, mtimecmp_hi
        li_small_bram(5'd10, 12'sd0);
        li_small_bram(5'd11, 12'sd0);
        bram_emit(32'h3020_0073);                                        // mret

        bram_seek(32'h0000_01f0);
        li_small_bram(5'd10, -12'sd2);
        li_small_bram(5'd11, 12'sd0);
        bram_emit(32'h3020_0073);                                        // mret

        bram_seek(32'h0000_0200);
        li_result_addr_bram(5'd31, 5'd30);
        bram_emit(enc_s(12'sd96, 5'd6, 5'd31, 3'b011, 7'b0100011));     // sd    mcause, fail slot
        bram_emit(enc_csr(12'h343, 5'd0, 3'b010, 5'd6));                // csrr  t1, mtval
        bram_emit(enc_s(12'sd104, 5'd6, 5'd31, 3'b011, 7'b0100011));    // sd    mtval, fail slot
        bram_j(32'h0000_0200);

        kernel_seek(0);
        li_result_addr_kernel(5'd1, 5'd2);
        kernel_emit(enc_s(12'sd0, 5'd10, 5'd1, 3'b011, 7'b0100011));    // sd    a0, 0(result)
        kernel_emit(enc_s(12'sd8, 5'd11, 5'd1, 3'b011, 7'b0100011));    // sd    a1, 8(result)
        kernel_emit(enc_i(12'sd0, 5'd11, 3'b110, 5'd5, 7'b0000011));    // lwu   t0, 0(a1)
        kernel_emit(enc_s(12'sd16, 5'd5, 5'd1, 3'b011, 7'b0100011));    // sd    t0, 16(result)
        kernel_emit(enc_csr(12'h180, 5'd0, 3'b010, 5'd5));              // csrr  t0, satp
        kernel_emit(enc_s(12'sd24, 5'd5, 5'd1, 3'b011, 7'b0100011));    // sd    t0, 24(result)
        li_kernel_trap_addr(5'd5, 5'd6);
        kernel_emit(enc_csr(12'h105, 5'd5, 3'b001, 5'd0));              // csrw  stvec, t0
        li_small_kernel(5'd5, 12'sd32);
        kernel_emit(enc_csr(12'h104, 5'd5, 3'b001, 5'd0));              // csrw  sie, t0
        li_small_kernel(5'd5, 12'sd2);
        kernel_emit(enc_csr(12'h100, 5'd5, 3'b001, 5'd0));              // csrw  sstatus, t0 (SIE)
        li_small_kernel(5'd17, 12'sd16);
        li_small_kernel(5'd16, 12'sd0);
        kernel_emit(32'h0000_0073);                                      // ecall SBI base spec
        kernel_emit(enc_s(12'sd32, 5'd10, 5'd1, 3'b011, 7'b0100011));
        kernel_emit(enc_s(12'sd40, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small_kernel(5'd10, 12'sd1);
        li_small_kernel(5'd11, 12'sd0);
        li_small_kernel(5'd17, 12'sd0);
        kernel_emit(32'h0000_0073);                                      // ecall legacy set_timer
        kernel_emit(enc_s(12'sd48, 5'd10, 5'd1, 3'b011, 7'b0100011));
        kernel_emit(enc_s(12'sd56, 5'd11, 5'd1, 3'b011, 7'b0100011));
        kernel_emit(32'h1050_0073);                                      // wfi
        li_small_kernel(5'd5, 12'sd123);
        kernel_emit(enc_s(12'sd88, 5'd5, 5'd1, 3'b011, 7'b0100011));    // fallthrough marker
        kernel_emit(32'h0010_0073);                                      // ebreak if timer did not arrive

        kernel_seek(32'h100);
        li_result_addr_kernel(5'd1, 5'd2);
        kernel_emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd5));              // csrr  t0, scause
        kernel_emit(enc_s(12'sd64, 5'd5, 5'd1, 3'b011, 7'b0100011));
        kernel_emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd5));              // csrr  t0, sepc
        kernel_emit(enc_s(12'sd72, 5'd5, 5'd1, 3'b011, 7'b0100011));
        kernel_emit(enc_csr(12'h144, 5'd0, 3'b010, 5'd5));              // csrr  t0, sip
        kernel_emit(enc_s(12'sd80, 5'd5, 5'd1, 3'b011, 7'b0100011));
        kernel_emit(32'h0010_0073);                                      // ebreak

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 30000 && !core_halted; cycle++) begin
            @(posedge clk);
        end

        if (!core_halted || core_illegal) begin
            $fatal(1, "ZX64 Linux handoff did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x imem=%0d/%0d iaddr=%08x ic_sel=%0d bram=%0d hit=%0d miss=%0d resp=%0d resp_addr=%08x idx=%0d valid=%0d ic_refill=%0d ic_wait=%0d dmem=%0d/%0d daddr=%08x dc_refill=%0d dc_wait=%0d ddrv=%0d ddrready=%0d",
                   core_halted, core_illegal, dbg_pc, dbg_instr, dbg_core_state,
                   u_soc.imem_valid, u_soc.imem_ready, u_soc.imem_addr,
                   u_soc.imem_cacheable_selected, u_soc.imem_bram_selected,
                   u_soc.icache_hit, u_soc.icache_miss_start,
                   u_soc.icache_resp_valid, u_soc.icache_resp_addr,
                   u_soc.icache_index, u_soc.icache_valid[u_soc.icache_index],
                   u_soc.icache_refill_valid, u_soc.icache_refill_wait,
                   u_soc.dmem_valid, u_soc.dmem_ready, u_soc.dmem_addr,
                   u_soc.dcache_refill_valid, u_soc.dcache_refill_wait,
                   u_soc.ddr32_valid, u_soc.ddr32_ready);
        end

        expect_result64(32'd0, 64'd0, "Linux handoff hartid");
        expect_result64(32'd8, {32'd0, DTB_CPU}, "Linux handoff dtb");
        expect_result64(32'd16, 64'h0000_0000_d00d_feed, "Linux handoff DTB magic");
        expect_result64(32'd24, 64'd0, "Linux handoff satp disabled");
        expect_result64(32'd32, 64'd0, "Linux handoff SBI base error");
        expect_result64(32'd40, 64'd2, "Linux handoff SBI base value");
        expect_result64(32'd48, 64'd0, "Linux handoff SBI timer error");
        expect_result64(32'd56, 64'd0, "Linux handoff SBI timer value");
        expect_result64(32'd64, 64'h8000_0000_0000_0005, "Linux handoff S timer scause");
        expect_result64(32'd88, 64'd0, "Linux handoff WFI fallthrough marker");
        expect_result64(32'd96, 64'd0, "Linux handoff unexpected M trap");
        expect_result64(32'd104, 64'd0, "Linux handoff unexpected M trap tval");

        if (dbg_icache_misses == 32'd0 || dbg_dcache_misses == 32'd0 ||
            burst_read_count < 32'd2 || max_arlen_seen < 8'd7 || write_count < 32'd8) begin
            $fatal(1, "ZX64 Linux handoff DDR activity too small ih=%0d im=%0d dh=%0d dm=%0d bursts=%0d writes=%0d max_arlen=%0d",
                   dbg_icache_hits, dbg_icache_misses,
                   dbg_dcache_hits, dbg_dcache_misses,
                   burst_read_count, write_count, max_arlen_seen);
        end

        $display("tb_zx64_soc_linux_handoff: PASS ih=%0d im=%0d dh=%0d dm=%0d bursts=%0d writes=%0d",
                 dbg_icache_hits, dbg_icache_misses,
                 dbg_dcache_hits, dbg_dcache_misses,
                 burst_read_count, write_count);
        $finish;
    end
endmodule
