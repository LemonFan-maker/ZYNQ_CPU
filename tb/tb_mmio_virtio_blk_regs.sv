module tb_mmio_virtio_blk_regs;
    logic clk;
    logic rst_n;
    logic valid;
    logic we;
    logic [3:0]  wstrb;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic        ready;
    logic [31:0] rdata;
    logic        backend_vring_irq;
    logic        backend_notify_ack;
    logic        notify_pulse;
    logic [15:0] notify_queue;
    logic        notify_pending;
    logic        irq_pending;
    logic [31:0] notify_count;
    logic [31:0] queue_num;
    logic        queue_ready;
    logic [63:0] queue_desc_addr;
    logic [63:0] queue_avail_addr;
    logic [63:0] queue_used_addr;
    logic [7:0]  device_status;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    mmio_virtio_blk_regs #(
        .DEFAULT_CAPACITY_SECTORS(64'd4096),
        .QUEUE_NUM_MAX(128)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .we(we),
        .wstrb(wstrb),
        .addr(addr),
        .wdata(wdata),
        .ready(ready),
        .rdata(rdata),
        .capacity_sectors(64'd0),
        .backend_vring_irq(backend_vring_irq),
        .backend_notify_ack(backend_notify_ack),
        .notify_pulse(notify_pulse),
        .notify_queue(notify_queue),
        .notify_pending(notify_pending),
        .irq_pending(irq_pending),
        .notify_count(notify_count),
        .queue_num(queue_num),
        .queue_ready(queue_ready),
        .queue_desc_addr(queue_desc_addr),
        .queue_avail_addr(queue_avail_addr),
        .queue_used_addr(queue_used_addr),
        .device_status(device_status)
    );

    task automatic write_reg(input logic [31:0] reg_addr, input logic [31:0] data);
        begin
            @(negedge clk);
            addr = reg_addr;
            wdata = data;
            wstrb = 4'hf;
            we = 1'b1;
            valid = 1'b1;
            @(posedge clk);
            if (!ready) $fatal(1, "write did not complete");
            @(negedge clk);
            valid = 1'b0;
            we = 1'b0;
            wstrb = 4'd0;
        end
    endtask

    task automatic read_reg(input logic [31:0] reg_addr, output logic [31:0] data);
        begin
            @(negedge clk);
            addr = reg_addr;
            wdata = 32'd0;
            wstrb = 4'd0;
            we = 1'b0;
            valid = 1'b1;
            @(posedge clk);
            if (!ready) $fatal(1, "read did not complete");
            data = rdata;
            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    initial begin
        logic [31:0] value;

        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;
        backend_vring_irq = 1'b0;
        backend_notify_ack = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        read_reg(32'h0000_0000, value);
        if (value !== 32'h7472_6976) $fatal(1, "bad virtio magic: %08x", value);
        read_reg(32'h0000_0004, value);
        if (value !== 32'd2) $fatal(1, "bad virtio version: %08x", value);
        read_reg(32'h0000_0008, value);
        if (value !== 32'd2) $fatal(1, "bad virtio device id: %08x", value);
        read_reg(32'h0000_0010, value);
        if (value !== 32'd0) $fatal(1, "unexpected feature word 0: %08x", value);
        write_reg(32'h0000_0014, 32'd1);
        read_reg(32'h0000_0010, value);
        if (value !== 32'h0000_0001) $fatal(1, "missing VERSION_1 feature: %08x", value);
        read_reg(32'h0000_0100, value);
        if (value !== 32'd4096) $fatal(1, "bad capacity lo: %08x", value);

        write_reg(32'h0000_0038, 32'd256);
        read_reg(32'h0000_0038, value);
        if (value !== 32'd128) $fatal(1, "queue num was not clamped: %08x", value);
        write_reg(32'h0000_0080, 32'h89ab_cdef);
        write_reg(32'h0000_0084, 32'h0123_4567);
        read_reg(32'h0000_0080, value);
        if (value !== 32'h89ab_cdef) $fatal(1, "bad desc lo: %08x", value);
        read_reg(32'h0000_0084, value);
        if (value !== 32'h0123_4567) $fatal(1, "bad desc hi: %08x", value);

        write_reg(32'h0000_0050, 32'd3);
        if (!notify_pulse || !notify_pending || notify_queue !== 16'd3 || notify_count !== 32'd1) begin
            $fatal(1, "notify mismatch pulse=%0d pending=%0d queue=%0d count=%0d",
                   notify_pulse, notify_pending, notify_queue, notify_count);
        end
        read_reg(32'h0000_00fc, value);
        if (value !== 32'd1) $fatal(1, "bad notify count: %08x", value);
        backend_notify_ack = 1'b1;
        @(negedge clk);
        backend_notify_ack = 1'b0;
        @(negedge clk);
        if (notify_pending) $fatal(1, "notify ack did not clear pending");

        @(negedge clk);
        backend_vring_irq = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk);
        backend_vring_irq = 1'b0;
        read_reg(32'h0000_0060, value);
        if (value !== 32'd1 || !irq_pending) begin
            $fatal(1, "interrupt status mismatch status=%08x pending=%0d", value, irq_pending);
        end
        write_reg(32'h0000_0064, 32'd1);
        read_reg(32'h0000_0060, value);
        if (value !== 32'd0 || irq_pending) begin
            $fatal(1, "interrupt ack failed status=%08x pending=%0d", value, irq_pending);
        end

        write_reg(32'h0000_0070, 32'd0);
        read_reg(32'h0000_00fc, value);
        if (value !== 32'd0) $fatal(1, "reset did not clear notify count: %08x", value);

        $display("tb_mmio_virtio_blk_regs: PASS");
        $finish;
    end
endmodule
