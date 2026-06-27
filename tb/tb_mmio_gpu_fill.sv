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
    logic [31:0] ddr_addr;
    logic [31:0] ddr_wdata;
    logic ddr_ready;
    logic [31:0] writes [0:15];
    logic [31:0] write_addrs [0:15];
    int write_count;

    initial clk = 1'b0;
    always #5 clk = ~clk;

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
        .ddr_addr(ddr_addr),
        .ddr_wdata(ddr_wdata),
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

    initial begin
        logic [31:0] status;

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

        $display("PASS");
        $finish;
    end

    always_ff @(posedge clk) begin
        if (ddr_valid && ddr_ready) begin
            write_addrs[write_count] <= ddr_addr;
            writes[write_count] <= ddr_wdata;
            write_count <= write_count + 1;
        end
    end
endmodule
