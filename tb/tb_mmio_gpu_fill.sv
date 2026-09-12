module tb_mmio_gpu_fill;
    logic clk;
    logic rst_n;
    logic valid;
    logic we;
    logic [3:0] wstrb;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic ready;
    logic [31:0] rdata;
    logic ddr_valid;
    logic ddr_we;
    logic [31:0] ddr_addr;
    logic [31:0] ddr_wdata;
    logic [31:0] ddr_rdata;
    logic ddr_ready;
    logic [31:0] ddr_mem [0:255];
    logic [31:0] writes [0:15];
    logic [31:0] write_addrs [0:15];
    int write_count;

    initial clk = 1'b0;
    always #5 clk = ~clk;
    assign ddr_rdata = ddr_mem[(ddr_addr - 32'h8000_0000) >> 2];

    mmio_gpu_fill u_gpu (
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .we(we),
        .wstrb(wstrb),
        .addr(addr),
        .wdata(wdata),
        .ready(ready),
        .rdata(rdata),
        .ddr_valid(ddr_valid),
        .ddr_we(ddr_we),
        .ddr_addr(ddr_addr),
        .ddr_wdata(ddr_wdata),
        .ddr_rdata(ddr_rdata),
        .ddr_ready(ddr_ready)
    );

    task automatic host_write(input logic [31:0] a, input logic [31:0] d);
        begin
            @(negedge clk);
            addr = a;
            wdata = d;
            wstrb = 4'hf;
            we = 1'b1;
            valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            valid = 1'b0;
            we = 1'b0;
            wstrb = 4'd0;
        end
    endtask

    task automatic host_read(input logic [31:0] a, output logic [31:0] d);
        begin
            @(negedge clk);
            addr = a;
            wdata = 32'd0;
            wstrb = 4'd0;
            we = 1'b0;
            valid = 1'b1;
            @(posedge clk);
            #1;
            d = rdata;
            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    function automatic logic [7:0] blend_channel(
        input logic [7:0] src,
        input logic [7:0] dst,
        input logic [7:0] alpha
    );
        logic [15:0] src_ext;
        logic [15:0] dst_ext;
        logic [15:0] alpha_ext;
        logic [15:0] inv_alpha_ext;
        logic [17:0] weighted;
        logic [17:0] biased;
        logic [17:0] div255;

        src_ext = {8'd0, src};
        dst_ext = {8'd0, dst};
        alpha_ext = {8'd0, alpha};
        inv_alpha_ext = 16'd255 - alpha_ext;
        weighted = (src_ext * alpha_ext) + (dst_ext * inv_alpha_ext);
        biased = weighted + 18'd128;
        div255 = biased + {10'd0, biased[17:8]};
        blend_channel = div255[15:8];
    endfunction

    function automatic logic [31:0] blend_xrgb8888(
        input logic [31:0] src,
        input logic [31:0] dst,
        input logic [7:0] alpha
    );
        blend_xrgb8888 = {
            8'hff,
            blend_channel(src[23:16], dst[23:16], alpha),
            blend_channel(src[15:8], dst[15:8], alpha),
            blend_channel(src[7:0], dst[7:0], alpha)
        };
    endfunction

    initial begin
        logic [31:0] status;
        logic [31:0] expected0;
        logic [31:0] expected1;
        logic [31:0] expected2;
        logic [31:0] expected3;

        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;
        ddr_ready = 1'b1;
        write_count = 0;
        for (int i = 0; i < 16; i++) begin
            writes[i] = 32'd0;
            write_addrs[i] = 32'd0;
        end
        for (int i = 0; i < 256; i++) begin
            ddr_mem[i] = 32'd0;
        end

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        host_write(32'h1007_0008, 32'h8000_0000);
        host_write(32'h1007_000c, 32'd16);
        host_write(32'h1007_0010, 32'h0002_0004);
        host_write(32'h1007_0014, 32'hcafe_beef);
        host_read(32'h1007_0008, status);
        if (status !== 32'h8000_0000) $fatal(1, "fb_addr readback %08x", status);
        host_read(32'h1007_000c, status);
        if (status !== 32'd16) $fatal(1, "fb_stride readback %08x", status);
        host_read(32'h1007_0010, status);
        if (status !== 32'h0002_0004) $fatal(1, "fb_size readback %08x", status);
        host_write(32'h1007_0000, 32'h0000_0011);

        repeat (50) begin
            host_read(32'h1007_0004, status);
            if (status[1]) break;
            @(posedge clk);
        end

        if (status !== 32'h0000_0002) begin
            $fatal(1, "GPU unit clear failed, status=%08x", status);
        end
        if (write_count !== 8) begin
            $fatal(1, "expected 8 writes, got %0d", write_count);
        end
        for (int i = 0; i < 8; i++) begin
            if (writes[i] !== 32'hcafe_beef) begin
                $fatal(1, "write[%0d] mismatch: %08x", i, writes[i]);
            end
        end

        write_count = 0;
        for (int i = 0; i < 16; i++) begin
            writes[i] = 32'd0;
            write_addrs[i] = 32'd0;
        end
        host_write(32'h1007_0014, 32'h1234_5678);
        host_write(32'h1007_0018, 32'h0000_0000);
        host_write(32'h1007_001c, 32'h0001_0003);
        host_write(32'h1007_0000, 32'h0000_0031);

        repeat (50) begin
            host_read(32'h1007_0004, status);
            if (status[1]) break;
            @(posedge clk);
        end

        if (status !== 32'h0000_0002) begin
            $fatal(1, "GPU unit line failed, status=%08x", status);
        end
        if (write_count !== 4) begin
            $fatal(1, "expected 4 line writes, got %0d", write_count);
        end
        if (write_addrs[0] !== 32'h8000_0000 ||
            write_addrs[1] !== 32'h8000_0004 ||
            write_addrs[2] !== 32'h8000_0018 ||
            write_addrs[3] !== 32'h8000_001c) begin
            $fatal(1, "line addresses mismatch: %08x %08x %08x %08x",
                   write_addrs[0], write_addrs[1], write_addrs[2], write_addrs[3]);
        end
        for (int i = 0; i < 4; i++) begin
            if (writes[i] !== 32'h1234_5678) begin
                $fatal(1, "line write[%0d] mismatch: %08x", i, writes[i]);
            end
        end

        host_write(32'h1007_0000, 32'h8000_0000);
        write_count = 0;
        for (int i = 0; i < 16; i++) begin
            writes[i] = 32'd0;
            write_addrs[i] = 32'd0;
        end
        ddr_ready = 1'b0;
        host_write(32'h1007_0014, 32'haaaa_0001);
        host_write(32'h1007_0034, 32'h0000_0011);
        host_write(32'h1007_0014, 32'hbbbb_0002);
        host_write(32'h1007_0018, 32'h0000_0001);
        host_write(32'h1007_001c, 32'h0001_0002);
        host_write(32'h1007_0034, 32'h0000_0021);
        host_write(32'h1007_0014, 32'hcccc_0003);
        host_write(32'h1007_0018, 32'h0001_0000);
        host_write(32'h1007_001c, 32'h0000_0003);
        host_write(32'h1007_0034, 32'h0000_0031);
        host_read(32'h1007_0034, status);
        if (status[7:5] !== 3'd2) begin
            $fatal(1, "expected fifo_count=2 while first command is active, got status=%08x", status);
        end
        ddr_ready = 1'b1;

        repeat (200) begin
            host_read(32'h1007_0004, status);
            if (status[1] && !status[0]) break;
            @(posedge clk);
        end

        if (status !== 32'h0000_0002) begin
            $fatal(1, "GPU unit fifo batch failed, status=%08x", status);
        end
        host_read(32'h1007_0038, status);
        if (status !== 32'd3) begin
            $fatal(1, "expected done_count=3, got %08x", status);
        end
        host_read(32'h1007_0034, status);
        if (!status[0] || status[7:5] !== 3'd0) begin
            $fatal(1, "expected fifo empty after batch, got status=%08x", status);
        end
        if (write_count !== 14) begin
            $fatal(1, "expected 14 fifo writes, got %0d", write_count);
        end
        for (int i = 0; i < 8; i++) begin
            if (writes[i] !== 32'haaaa_0001) begin
                $fatal(1, "fifo clear write[%0d] mismatch: %08x", i, writes[i]);
            end
        end
        if (write_addrs[8] !== 32'h8000_0004 || write_addrs[9] !== 32'h8000_0008 ||
            writes[8] !== 32'hbbbb_0002 || writes[9] !== 32'hbbbb_0002) begin
            $fatal(1, "fifo rect mismatch: addr=%08x/%08x data=%08x/%08x",
                   write_addrs[8], write_addrs[9], writes[8], writes[9]);
        end
        if (write_addrs[10] !== 32'h8000_0010 ||
            write_addrs[11] !== 32'h8000_0014 ||
            write_addrs[12] !== 32'h8000_0008 ||
            write_addrs[13] !== 32'h8000_000c) begin
            $fatal(1, "fifo line addresses mismatch: %08x %08x %08x %08x",
                   write_addrs[10], write_addrs[11], write_addrs[12], write_addrs[13]);
        end
        for (int i = 10; i < 14; i++) begin
            if (writes[i] !== 32'hcccc_0003) begin
                $fatal(1, "fifo line write[%0d] mismatch: %08x", i, writes[i]);
            end
        end
        host_read(32'h1007_003c, status);
        if (status === 32'd0) begin
            $fatal(1, "expected nonzero perf_total_cycles");
        end
        host_read(32'h1007_0040, status);
        if (status === 32'd0) begin
            $fatal(1, "expected nonzero perf_busy_cycles");
        end
        host_read(32'h1007_0048, status);
        if (status !== 32'd26) begin
            $fatal(1, "expected perf_write_count=26, got %08x", status);
        end

        host_write(32'h1007_0000, 32'h8000_0000);
        write_count = 0;
        for (int i = 0; i < 16; i++) begin
            writes[i] = 32'd0;
            write_addrs[i] = 32'd0;
        end
        ddr_mem[16] = 32'h0102_0304;
        ddr_mem[17] = 32'h1112_1314;
        ddr_mem[20] = 32'h2122_2324;
        ddr_mem[21] = 32'h3132_3334;
        host_write(32'h1007_0008, 32'h8000_0000);
        host_write(32'h1007_000c, 32'd16);
        host_write(32'h1007_0010, 32'h0004_0004);
        host_write(32'h1007_0018, 32'h0001_0001);
        host_write(32'h1007_001c, 32'h0002_0002);
        host_write(32'h1007_004c, 32'h8000_0040);
        host_write(32'h1007_0050, 32'd16);
        host_write(32'h1007_0000, 32'h0000_0041);

        repeat (100) begin
            host_read(32'h1007_0004, status);
            if (status[1]) break;
            @(posedge clk);
        end

        if (status !== 32'h0000_0002) begin
            $fatal(1, "GPU unit blit failed, status=%08x", status);
        end
        if (write_count !== 4) begin
            $fatal(1, "expected 4 blit writes, got %0d", write_count);
        end
        if (ddr_mem[5] !== 32'h0102_0304 ||
            ddr_mem[6] !== 32'h1112_1314 ||
            ddr_mem[9] !== 32'h2122_2324 ||
            ddr_mem[10] !== 32'h3132_3334) begin
            $fatal(1, "blit destination mismatch: %08x %08x %08x %08x",
                   ddr_mem[5], ddr_mem[6], ddr_mem[9], ddr_mem[10]);
        end
        host_read(32'h1007_0048, status);
        if (status !== 32'd30) begin
            $fatal(1, "expected perf_write_count=30 after cumulative blit, got %08x", status);
        end

        host_write(32'h1007_0000, 32'h8000_0000);
        write_count = 0;
        for (int i = 0; i < 16; i++) begin
            writes[i] = 32'd0;
            write_addrs[i] = 32'd0;
        end
        ddr_mem[5] = 32'h5566_7788;
        ddr_mem[6] = 32'h5566_7788;
        ddr_mem[9] = 32'h5566_7788;
        ddr_mem[10] = 32'h5566_7788;
        ddr_mem[32] = 32'h0102_0304;
        ddr_mem[33] = 32'h00ff_00ff;
        ddr_mem[36] = 32'h2122_2324;
        ddr_mem[37] = 32'h3132_3334;
        host_write(32'h1007_0008, 32'h8000_0000);
        host_write(32'h1007_000c, 32'd16);
        host_write(32'h1007_0010, 32'h0004_0004);
        host_write(32'h1007_0014, 32'h00ff_00ff);
        host_write(32'h1007_0018, 32'h0001_0001);
        host_write(32'h1007_001c, 32'h0002_0002);
        host_write(32'h1007_004c, 32'h8000_0080);
        host_write(32'h1007_0050, 32'd16);
        host_write(32'h1007_0000, 32'h0000_0051);

        repeat (100) begin
            host_read(32'h1007_0004, status);
            if (status[1]) break;
            @(posedge clk);
        end

        if (status !== 32'h0000_0002) begin
            $fatal(1, "GPU unit color-key blit failed, status=%08x", status);
        end
        if (write_count !== 3) begin
            $fatal(1, "expected 3 color-key blit writes, got %0d", write_count);
        end
        if (ddr_mem[5] !== 32'h0102_0304 ||
            ddr_mem[6] !== 32'h5566_7788 ||
            ddr_mem[9] !== 32'h2122_2324 ||
            ddr_mem[10] !== 32'h3132_3334) begin
            $fatal(1, "color-key blit destination mismatch: %08x %08x %08x %08x",
                   ddr_mem[5], ddr_mem[6], ddr_mem[9], ddr_mem[10]);
        end
        host_read(32'h1007_0048, status);
        if (status !== 32'd33) begin
            $fatal(1, "expected perf_write_count=33 after color-key blit, got %08x", status);
        end

        host_write(32'h1007_0000, 32'h8000_0000);
        write_count = 0;
        for (int i = 0; i < 16; i++) begin
            writes[i] = 32'd0;
            write_addrs[i] = 32'd0;
        end
        for (int i = 0; i < 16; i++) begin
            ddr_mem[i] = 32'd0;
        end
        ddr_mem[64] = 32'h0102_0304;
        ddr_mem[65] = 32'h1112_1314;
        ddr_mem[66] = 32'h2122_2324;
        ddr_mem[67] = 32'h3132_3334;
        host_write(32'h1007_0008, 32'h8000_0000);
        host_write(32'h1007_000c, 32'd16);
        host_write(32'h1007_0010, 32'h0004_0004);
        host_write(32'h1007_0018, 32'h0000_0000);
        host_write(32'h1007_001c, 32'h0004_0004);
        host_write(32'h1007_004c, 32'h8000_0100);
        host_write(32'h1007_0050, 32'd8);
        host_write(32'h1007_0054, 32'h0002_0002);
        host_write(32'h1007_0000, 32'h0000_0061);

        repeat (300) begin
            host_read(32'h1007_0004, status);
            if (status[1]) break;
            @(posedge clk);
        end

        if (status !== 32'h0000_0002) begin
            $fatal(1, "GPU unit scale blit failed, status=%08x", status);
        end
        if (write_count !== 16) begin
            $fatal(1, "expected 16 scale blit writes, got %0d", write_count);
        end
        if (ddr_mem[0] !== 32'h0102_0304 ||
            ddr_mem[1] !== 32'h0102_0304 ||
            ddr_mem[2] !== 32'h1112_1314 ||
            ddr_mem[3] !== 32'h1112_1314 ||
            ddr_mem[4] !== 32'h0102_0304 ||
            ddr_mem[5] !== 32'h0102_0304 ||
            ddr_mem[6] !== 32'h1112_1314 ||
            ddr_mem[7] !== 32'h1112_1314 ||
            ddr_mem[8] !== 32'h2122_2324 ||
            ddr_mem[9] !== 32'h2122_2324 ||
            ddr_mem[10] !== 32'h3132_3334 ||
            ddr_mem[11] !== 32'h3132_3334 ||
            ddr_mem[12] !== 32'h2122_2324 ||
            ddr_mem[13] !== 32'h2122_2324 ||
            ddr_mem[14] !== 32'h3132_3334 ||
            ddr_mem[15] !== 32'h3132_3334) begin
            $fatal(1, "scale blit destination mismatch");
        end
        host_read(32'h1007_0048, status);
        if (status !== 32'd49) begin
            $fatal(1, "expected perf_write_count=49 after scale blit, got %08x", status);
        end

        host_write(32'h1007_0000, 32'h8000_0000);
        write_count = 0;
        for (int i = 0; i < 16; i++) begin
            writes[i] = 32'd0;
            write_addrs[i] = 32'd0;
        end
        ddr_mem[5] = 32'hff20_4060;
        ddr_mem[6] = 32'hff20_4060;
        ddr_mem[9] = 32'hff20_4060;
        ddr_mem[10] = 32'hff20_4060;
        ddr_mem[96] = 32'hffe0_2010;
        ddr_mem[97] = 32'hff10_20e0;
        ddr_mem[100] = 32'hff20_e010;
        ddr_mem[101] = 32'hffe0_e020;
        expected0 = blend_xrgb8888(32'hffe0_2010, 32'hff20_4060, 8'd128);
        expected1 = blend_xrgb8888(32'hff10_20e0, 32'hff20_4060, 8'd128);
        expected2 = blend_xrgb8888(32'hff20_e010, 32'hff20_4060, 8'd128);
        expected3 = blend_xrgb8888(32'hffe0_e020, 32'hff20_4060, 8'd128);
        host_write(32'h1007_0008, 32'h8000_0000);
        host_write(32'h1007_000c, 32'd16);
        host_write(32'h1007_0010, 32'h0004_0004);
        host_write(32'h1007_0018, 32'h0001_0001);
        host_write(32'h1007_001c, 32'h0002_0002);
        host_write(32'h1007_004c, 32'h8000_0180);
        host_write(32'h1007_0050, 32'd16);
        host_write(32'h1007_0058, 32'd128);
        host_read(32'h1007_0058, status);
        if (status !== 32'd128) begin
            $fatal(1, "alpha register readback mismatch: %08x", status);
        end
        host_write(32'h1007_0000, 32'h0000_0071);

        repeat (200) begin
            host_read(32'h1007_0004, status);
            if (status[1]) break;
            @(posedge clk);
        end

        if (status !== 32'h0000_0002) begin
            $fatal(1, "GPU unit alpha blit failed, status=%08x", status);
        end
        if (write_count !== 4) begin
            $fatal(1, "expected 4 alpha blit writes, got %0d", write_count);
        end
        if (ddr_mem[5] !== expected0 ||
            ddr_mem[6] !== expected1 ||
            ddr_mem[9] !== expected2 ||
            ddr_mem[10] !== expected3) begin
            $fatal(1, "alpha blit destination mismatch: %08x/%08x %08x/%08x %08x/%08x %08x/%08x",
                   ddr_mem[5], expected0,
                   ddr_mem[6], expected1,
                   ddr_mem[9], expected2,
                   ddr_mem[10], expected3);
        end
        host_read(32'h1007_0048, status);
        if (status !== 32'd53) begin
            $fatal(1, "expected perf_write_count=53 after alpha blit, got %08x", status);
        end

        $display("PASS");
        $finish;
    end

    always_ff @(posedge clk) begin
        if (ddr_valid && ddr_ready) begin
            if (ddr_we) begin
                ddr_mem[(ddr_addr - 32'h8000_0000) >> 2] <= ddr_wdata;
                write_addrs[write_count] <= ddr_addr;
                writes[write_count] <= ddr_wdata;
                write_count <= write_count + 1;
            end
        end
    end
endmodule
