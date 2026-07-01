module tb_zx32_soc_sv32_ddr;
    logic clk;
    logic rst_n;
    logic uart_tx;

    logic        host_valid;
    logic        host_we;
    logic [3:0]  host_wstrb;
    logic [31:0] host_addr;
    logic [31:0] host_wdata;
    logic        host_ready;
    logic [31:0] host_rdata;

    logic        dm_mm2s_cmd_valid;
    logic        dm_mm2s_cmd_ready;
    logic [71:0] dm_mm2s_cmd_data;
    logic        dm_mm2s_sts_valid;
    logic        dm_mm2s_sts_ready;
    logic [7:0]  dm_mm2s_sts_data;
    logic        dm_s2mm_cmd_valid;
    logic        dm_s2mm_cmd_ready;
    logic [71:0] dm_s2mm_cmd_data;
    logic        dm_s2mm_sts_valid;
    logic        dm_s2mm_sts_ready;
    logic [7:0]  dm_s2mm_sts_data;
    logic [31:0] dm_m_axis_mm2s_tdata;
    logic [3:0]  dm_m_axis_mm2s_tkeep;
    logic        dm_m_axis_mm2s_tlast;
    logic        dm_m_axis_mm2s_tvalid;
    logic        dm_m_axis_mm2s_tready;
    logic [31:0] dm_s_axis_s2mm_tdata;
    logic [3:0]  dm_s_axis_s2mm_tkeep;
    logic        dm_s_axis_s2mm_tlast;
    logic        dm_s_axis_s2mm_tvalid;
    logic        dm_s_axis_s2mm_tready;

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

    localparam logic [31:0] CTRL_BASE = 32'h1003_0000;
    localparam logic [31:0] GPU_BASE = 32'h1007_0000;
    localparam logic [31:0] IMEM_BASE = 32'h0000_0000;
    localparam logic [31:0] KERNEL_CPU_BASE = 32'h8040_0000;
    localparam logic [31:0] ROOT_CPU_BASE = 32'h8080_0000;
    localparam logic [31:0] VRAM_CPU_BASE = 32'hbc00_0000;
    localparam logic [31:0] KERNEL_PS_BASE = 32'h0040_0000;
    localparam logic [31:0] ROOT_PS_BASE = 32'h0080_0000;
    localparam logic [31:0] VRAM_PS_BASE = 32'h3c00_0000;
    localparam logic [31:0] TRAP_MARKER_CPU = KERNEL_CPU_BASE + 32'h200;
    localparam logic [31:0] ROOT_VIRT_PTE = 32'h2010_00cf;

    logic [31:0] kernel_mem [0:1023];
    logic [31:0] root_mem [0:1023];
    logic [31:0] vram_mem [0:1023];
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
    logic [7:0]  max_arlen_seen;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    zx32_soc #(.BRAM_WORDS(1024), .CLK_HZ(75_000_000)) u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx(uart_tx),
        .host_valid(host_valid),
        .host_we(host_we),
        .host_wstrb(host_wstrb),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .dm_mm2s_cmd_valid(dm_mm2s_cmd_valid),
        .dm_mm2s_cmd_ready(dm_mm2s_cmd_ready),
        .dm_mm2s_cmd_data(dm_mm2s_cmd_data),
        .dm_mm2s_sts_valid(dm_mm2s_sts_valid),
        .dm_mm2s_sts_ready(dm_mm2s_sts_ready),
        .dm_mm2s_sts_data(dm_mm2s_sts_data),
        .dm_s2mm_cmd_valid(dm_s2mm_cmd_valid),
        .dm_s2mm_cmd_ready(dm_s2mm_cmd_ready),
        .dm_s2mm_cmd_data(dm_s2mm_cmd_data),
        .dm_s2mm_sts_valid(dm_s2mm_sts_valid),
        .dm_s2mm_sts_ready(dm_s2mm_sts_ready),
        .dm_s2mm_sts_data(dm_s2mm_sts_data),
        .dm_m_axis_mm2s_tdata(dm_m_axis_mm2s_tdata),
        .dm_m_axis_mm2s_tkeep(dm_m_axis_mm2s_tkeep),
        .dm_m_axis_mm2s_tlast(dm_m_axis_mm2s_tlast),
        .dm_m_axis_mm2s_tvalid(dm_m_axis_mm2s_tvalid),
        .dm_m_axis_mm2s_tready(dm_m_axis_mm2s_tready),
        .dm_s_axis_s2mm_tdata(dm_s_axis_s2mm_tdata),
        .dm_s_axis_s2mm_tkeep(dm_s_axis_s2mm_tkeep),
        .dm_s_axis_s2mm_tlast(dm_s_axis_s2mm_tlast),
        .dm_s_axis_s2mm_tvalid(dm_s_axis_s2mm_tvalid),
        .dm_s_axis_s2mm_tready(dm_s_axis_s2mm_tready),
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

    task automatic host_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            host_addr = addr;
            host_wdata = data;
            host_wstrb = 4'hf;
            host_we = 1'b1;
            host_valid = 1'b1;
            do begin
                @(posedge clk);
            end while (host_ready !== 1'b1);
            @(negedge clk);
            host_valid = 1'b0;
            host_we = 1'b0;
            host_wstrb = 4'd0;
        end
    endtask

    task automatic host_read(input logic [31:0] addr, output logic [31:0] data);
        begin
            @(negedge clk);
            host_addr = addr;
            host_wdata = 32'd0;
            host_wstrb = 4'd0;
            host_we = 1'b0;
            host_valid = 1'b1;
            do begin
                @(posedge clk);
            end while (host_ready !== 1'b1);
            #1;
            data = host_rdata;
            @(negedge clk);
            host_valid = 1'b0;
        end
    endtask

    function automatic logic [31:0] ddr_read_word(input logic [31:0] addr);
        begin
            if (addr >= KERNEL_PS_BASE && addr < KERNEL_PS_BASE + 32'h1000) begin
                ddr_read_word = kernel_mem[(addr - KERNEL_PS_BASE) >> 2];
            end else if (addr >= ROOT_PS_BASE && addr < ROOT_PS_BASE + 32'h1000) begin
                ddr_read_word = root_mem[(addr - ROOT_PS_BASE) >> 2];
            end else if (addr >= VRAM_PS_BASE && addr < VRAM_PS_BASE + 32'h1000) begin
                ddr_read_word = vram_mem[(addr - VRAM_PS_BASE) >> 2];
            end else begin
                ddr_read_word = 32'd0;
            end
        end
    endfunction

    task automatic ddr_write_word(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [3:0]  wstrb
    );
        logic [31:0] old_word;
        logic [31:0] new_word;
        begin
            old_word = ddr_read_word(addr);
            new_word = old_word;
            for (int b = 0; b < 4; b++) begin
                if (wstrb[b]) begin
                    new_word[b * 8 +: 8] = data[b * 8 +: 8];
                end
            end
            if (addr >= KERNEL_PS_BASE && addr < KERNEL_PS_BASE + 32'h1000) begin
                kernel_mem[(addr - KERNEL_PS_BASE) >> 2] = new_word;
            end else if (addr >= ROOT_PS_BASE && addr < ROOT_PS_BASE + 32'h1000) begin
                root_mem[(addr - ROOT_PS_BASE) >> 2] = new_word;
            end else if (addr >= VRAM_PS_BASE && addr < VRAM_PS_BASE + 32'h1000) begin
                vram_mem[(addr - VRAM_PS_BASE) >> 2] = new_word;
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
        logic [31:0] marker;
        logic [31:0] sepc;
        logic [31:0] scause;
        logic [31:0] stval;
        logic [31:0] icache_hits;
        logic [31:0] icache_misses;
        logic [31:0] gpu_status;
        logic [31:0] gpu_first_word;

        host_valid = 1'b0;
        host_we = 1'b0;
        host_wstrb = 4'd0;
        host_addr = 32'd0;
        host_wdata = 32'd0;
        dm_mm2s_cmd_ready = 1'b0;
        dm_mm2s_sts_valid = 1'b0;
        dm_mm2s_sts_data = 8'd0;
        dm_s2mm_cmd_ready = 1'b0;
        dm_s2mm_sts_valid = 1'b0;
        dm_s2mm_sts_data = 8'd0;
        dm_m_axis_mm2s_tdata = 32'd0;
        dm_m_axis_mm2s_tkeep = 4'd0;
        dm_m_axis_mm2s_tlast = 1'b0;
        dm_m_axis_mm2s_tvalid = 1'b0;
        dm_s_axis_s2mm_tready = 1'b0;

        for (int i = 0; i < 1024; i++) begin
            kernel_mem[i] = 32'd0;
            root_mem[i] = 32'd0;
            vram_mem[i] = 32'd0;
        end

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        host_write(GPU_BASE + 32'h08, KERNEL_CPU_BASE);
        host_write(GPU_BASE + 32'h0c, 32'd16);
        host_write(GPU_BASE + 32'h10, 32'h0003_0004);
        host_write(GPU_BASE + 32'h14, 32'haabb_ccdd);
        host_write(GPU_BASE + 32'h00, 32'h0000_0011);
        host_read(KERNEL_CPU_BASE, gpu_first_word);
        if (gpu_first_word !== 32'haabb_ccdd) begin
            $fatal(1, "host DDR read overlapped with GPU write incorrectly: got %08x",
                   gpu_first_word);
        end
        repeat (200) begin
            host_read(GPU_BASE + 32'h04, gpu_status);
            if (gpu_status[1]) begin
                break;
            end
            @(posedge clk);
        end
        if (gpu_status !== 32'h0000_0002) begin
            $fatal(1, "GPU clear failed, status=%08x", gpu_status);
        end
        for (int i = 0; i < 12; i++) begin
            if (kernel_mem[i] !== 32'haabb_ccdd) begin
                $fatal(1, "GPU clear word %0d mismatch: %08x", i, kernel_mem[i]);
            end
        end

        host_write(GPU_BASE + 32'h14, 32'h1122_3344);
        host_write(GPU_BASE + 32'h18, 32'h0001_0001);
        host_write(GPU_BASE + 32'h1c, 32'h0001_0002);
        host_write(GPU_BASE + 32'h00, 32'h0000_0021);
        repeat (200) begin
            host_read(GPU_BASE + 32'h04, gpu_status);
            if (gpu_status[1]) begin
                break;
            end
            @(posedge clk);
        end
        if (gpu_status !== 32'h0000_0002) begin
            $fatal(1, "GPU fill-rect failed, status=%08x", gpu_status);
        end
        if (kernel_mem[5] !== 32'h1122_3344 || kernel_mem[6] !== 32'h1122_3344) begin
            $fatal(1, "GPU fill-rect pixels mismatch: mem[5]=%08x mem[6]=%08x",
                   kernel_mem[5], kernel_mem[6]);
        end
        if (kernel_mem[4] !== 32'haabb_ccdd || kernel_mem[7] !== 32'haabb_ccdd) begin
            $fatal(1, "GPU fill-rect over-wrote neighboring pixels: mem[4]=%08x mem[7]=%08x",
                   kernel_mem[4], kernel_mem[7]);
        end

        host_write(GPU_BASE + 32'h14, 32'h5566_7788);
        host_write(GPU_BASE + 32'h18, 32'h0002_0000);
        host_write(GPU_BASE + 32'h1c, 32'h0000_0003);
        host_write(GPU_BASE + 32'h00, 32'h0000_0031);
        repeat (200) begin
            host_read(GPU_BASE + 32'h04, gpu_status);
            if (gpu_status[1]) begin
                break;
            end
            @(posedge clk);
        end
        if (gpu_status !== 32'h0000_0002) begin
            $fatal(1, "GPU draw-line failed, status=%08x", gpu_status);
        end
        if (kernel_mem[8] !== 32'h5566_7788 ||
            kernel_mem[5] !== 32'h5566_7788 ||
            kernel_mem[6] !== 32'h5566_7788 ||
            kernel_mem[3] !== 32'h5566_7788) begin
            $fatal(1, "GPU draw-line pixels mismatch: mem[8]=%08x mem[5]=%08x mem[6]=%08x mem[3]=%08x",
                   kernel_mem[8], kernel_mem[5], kernel_mem[6], kernel_mem[3]);
        end

        host_write(GPU_BASE + 32'h00, 32'h8000_0000);
        for (int i = 0; i < 12; i++) begin
            kernel_mem[i] = 32'd0;
        end
        host_write(GPU_BASE + 32'h08, KERNEL_CPU_BASE);
        host_write(GPU_BASE + 32'h0c, 32'd16);
        host_write(GPU_BASE + 32'h10, 32'h0003_0004);
        host_write(GPU_BASE + 32'h14, 32'h0102_0304);
        host_write(GPU_BASE + 32'h34, 32'h0000_0011);
        host_write(GPU_BASE + 32'h14, 32'h0506_0708);
        host_write(GPU_BASE + 32'h18, 32'h0001_0001);
        host_write(GPU_BASE + 32'h1c, 32'h0001_0002);
        host_write(GPU_BASE + 32'h34, 32'h0000_0021);
        host_write(GPU_BASE + 32'h14, 32'h090a_0b0c);
        host_write(GPU_BASE + 32'h18, 32'h0002_0000);
        host_write(GPU_BASE + 32'h1c, 32'h0000_0003);
        host_write(GPU_BASE + 32'h34, 32'h0000_0031);
        repeat (300) begin
            host_read(GPU_BASE + 32'h04, gpu_status);
            if (gpu_status[1]) begin
                break;
            end
            @(posedge clk);
        end
        if (gpu_status !== 32'h0000_0002) begin
            $fatal(1, "GPU fifo batch failed, status=%08x", gpu_status);
        end
        host_read(GPU_BASE + 32'h38, gpu_status);
        if (gpu_status !== 32'd3) begin
            $fatal(1, "GPU fifo done_count mismatch: %08x", gpu_status);
        end
        if (kernel_mem[8] !== 32'h090a_0b0c ||
            kernel_mem[5] !== 32'h090a_0b0c ||
            kernel_mem[6] !== 32'h090a_0b0c ||
            kernel_mem[3] !== 32'h090a_0b0c) begin
            $fatal(1, "GPU fifo line pixels mismatch: mem[8]=%08x mem[5]=%08x mem[6]=%08x mem[3]=%08x",
                   kernel_mem[8], kernel_mem[5], kernel_mem[6], kernel_mem[3]);
        end
        if (kernel_mem[0] !== 32'h0102_0304 || kernel_mem[1] !== 32'h0102_0304) begin
            $fatal(1, "GPU fifo clear pixels mismatch: mem[0]=%08x mem[1]=%08x",
                   kernel_mem[0], kernel_mem[1]);
        end

        host_write(GPU_BASE + 32'h00, 32'h8000_0000);
        vram_mem[0] = 32'hdead_beef;
        vram_mem[4] = 32'h0000_0000;
        host_read(VRAM_CPU_BASE, gpu_first_word);
        if (gpu_first_word !== 32'hdead_beef) begin
            $fatal(1, "VRAM pre-read mismatch: %08x", gpu_first_word);
        end
        host_write(GPU_BASE + 32'h08, VRAM_CPU_BASE);
        host_write(GPU_BASE + 32'h0c, 32'd32);
        host_write(GPU_BASE + 32'h10, 32'h0004_0008);
        host_write(GPU_BASE + 32'h14, 32'hcaf0_1234);
        host_write(GPU_BASE + 32'h00, 32'h0000_0011);
        repeat (300) begin
            host_read(GPU_BASE + 32'h04, gpu_status);
            if (gpu_status[1]) begin
                break;
            end
            @(posedge clk);
        end
        if (gpu_status !== 32'h0000_0002) begin
            $fatal(1, "GPU VRAM clear failed, status=%08x", gpu_status);
        end
        host_read(VRAM_CPU_BASE + 32'd16, gpu_first_word);
        if (gpu_first_word !== 32'hcaf0_1234) begin
            $fatal(1, "GPU VRAM readback stale: got %08x", gpu_first_word);
        end

        host_write(GPU_BASE + 32'h00, 32'h8000_0000);
        for (int i = 0; i < 64; i++) begin
            vram_mem[i] = 32'd0;
        end
        vram_mem[32] = 32'h0102_0304;
        vram_mem[33] = 32'h1112_1314;
        vram_mem[40] = 32'h2122_2324;
        vram_mem[41] = 32'h3132_3334;
        host_write(GPU_BASE + 32'h08, VRAM_CPU_BASE);
        host_write(GPU_BASE + 32'h0c, 32'd32);
        host_write(GPU_BASE + 32'h10, 32'h0004_0008);
        host_write(GPU_BASE + 32'h18, 32'h0001_0001);
        host_write(GPU_BASE + 32'h1c, 32'h0002_0002);
        host_write(GPU_BASE + 32'h4c, VRAM_CPU_BASE + 32'd128);
        host_write(GPU_BASE + 32'h50, 32'd32);
        host_write(GPU_BASE + 32'h00, 32'h0000_0041);
        repeat (500) begin
            host_read(GPU_BASE + 32'h04, gpu_status);
            if (gpu_status[1]) begin
                break;
            end
            @(posedge clk);
        end
        if (gpu_status !== 32'h0000_0002) begin
            $fatal(1, "GPU VRAM blit failed, status=%08x", gpu_status);
        end
        if (vram_mem[9] !== 32'h0102_0304 ||
            vram_mem[10] !== 32'h1112_1314 ||
            vram_mem[17] !== 32'h2122_2324 ||
            vram_mem[18] !== 32'h3132_3334) begin
            $fatal(1, "GPU VRAM blit pixels mismatch: mem[9]=%08x mem[10]=%08x mem[17]=%08x mem[18]=%08x",
                   vram_mem[9], vram_mem[10], vram_mem[17], vram_mem[18]);
        end

        host_write(CTRL_BASE, 32'd1);

        host_write(IMEM_BASE + 32'd0,  32'h0300_0293);
        host_write(IMEM_BASE + 32'd4,  32'h3052_9073);
        host_write(IMEM_BASE + 32'd8,  32'h0000_12b7);
        host_write(IMEM_BASE + 32'd12, 32'h0002_8293);
        host_write(IMEM_BASE + 32'd16, 32'h3022_9073);
        host_write(IMEM_BASE + 32'd20, 32'h8040_02b7);
        host_write(IMEM_BASE + 32'd24, 32'h0002_8293);
        host_write(IMEM_BASE + 32'd28, 32'h3412_9073);
        host_write(IMEM_BASE + 32'd32, 32'h0000_12b7);
        host_write(IMEM_BASE + 32'd36, 32'h8002_8293);
        host_write(IMEM_BASE + 32'd40, 32'h3002_9073);
        host_write(IMEM_BASE + 32'd44, 32'h3020_0073);
        host_write(IMEM_BASE + 32'd48, 32'h0000_006f);

        host_write(KERNEL_CPU_BASE + 32'd0,   32'hc000_02b7);
        host_write(KERNEL_CPU_BASE + 32'd4,   32'h0402_8293);
        host_write(KERNEL_CPU_BASE + 32'd8,   32'h1052_9073);
        host_write(KERNEL_CPU_BASE + 32'd12,  32'h8008_12b7);
        host_write(KERNEL_CPU_BASE + 32'd16,  32'h8002_8293);
        host_write(KERNEL_CPU_BASE + 32'd20,  32'h1200_0073);
        host_write(KERNEL_CPU_BASE + 32'd24,  32'h1802_9073);
        host_write(KERNEL_CPU_BASE + 32'd28,  32'hbad0_0337);
        host_write(KERNEL_CPU_BASE + 32'd32,  32'h0003_0313);
        host_write(KERNEL_CPU_BASE + 32'd36,  32'h2060_2023);
        host_write(KERNEL_CPU_BASE + 32'd40,  32'h0000_006f);
        host_write(KERNEL_CPU_BASE + 32'd64,  32'hc000_0eb7);
        host_write(KERNEL_CPU_BASE + 32'd68,  32'h000e_8e93);
        host_write(KERNEL_CPU_BASE + 32'd72,  32'h05a0_0293);
        host_write(KERNEL_CPU_BASE + 32'd76,  32'h205e_a023);
        host_write(KERNEL_CPU_BASE + 32'd80,  32'h1410_2373);
        host_write(KERNEL_CPU_BASE + 32'd84,  32'h206e_a223);
        host_write(KERNEL_CPU_BASE + 32'd88,  32'h1420_23f3);
        host_write(KERNEL_CPU_BASE + 32'd92,  32'h207e_a423);
        host_write(KERNEL_CPU_BASE + 32'd96,  32'h1430_2e73);
        host_write(KERNEL_CPU_BASE + 32'd100, 32'h21ce_a623);
        host_write(KERNEL_CPU_BASE + 32'd104, 32'h0000_006f);

        host_write(ROOT_CPU_BASE + (768 * 4), ROOT_VIRT_PTE);
        host_write(CTRL_BASE + 32'h10, 32'd0);
        host_write(CTRL_BASE, 32'd0);

        repeat (1600) @(posedge clk);

        host_read(TRAP_MARKER_CPU, marker);
        host_read(TRAP_MARKER_CPU + 32'd4, sepc);
        host_read(TRAP_MARKER_CPU + 32'd8, scause);
        host_read(TRAP_MARKER_CPU + 32'd12, stval);
        host_read(CTRL_BASE + 32'hac, icache_hits);
        host_read(CTRL_BASE + 32'hb0, icache_misses);

        if (marker !== 32'h0000_005a || sepc !== 32'h8040_001c ||
            scause !== 32'h0000_000c || stval !== 32'h8040_001c) begin
            $fatal(1, "SOC Sv32 DDR trampoline failed marker=%08x sepc=%08x scause=%08x stval=%08x dbg=%08x pc=%08x satp=%08x ptw=%08x l1=%08x bus=%08x",
                   marker, sepc, scause, stval,
                   u_soc.dbg_core_state, u_soc.dbg_pc, u_soc.dbg_satp,
                   u_soc.dbg_ptw_pte_addr, u_soc.dbg_ptw_l1_pte, u_soc.dbg_bus_state);
        end
        if (icache_hits == 32'd0 || icache_misses == 32'd0) begin
            $fatal(1, "expected DDR I-cache activity hits=%0d misses=%0d", icache_hits, icache_misses);
        end
        if (burst_read_count == 32'd0 || max_arlen_seen !== 8'd7) begin
            $fatal(1, "expected 8-beat DDR read bursts, count=%0d max_arlen=%0d", burst_read_count, max_arlen_seen);
        end

        $display("PASS");
        $finish;
    end
endmodule
