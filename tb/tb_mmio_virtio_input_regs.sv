module tb_mmio_virtio_input_regs;
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
    logic [7:0]  device_status;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    mmio_virtio_input_regs #(
        .QUEUE_NUM_MAX(64)
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
        .backend_vring_irq(backend_vring_irq),
        .backend_notify_ack(backend_notify_ack),
        .notify_pulse(notify_pulse),
        .notify_queue(notify_queue),
        .notify_pending(notify_pending),
        .irq_pending(irq_pending),
        .notify_count(notify_count),
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

    task automatic write_byte(input logic [31:0] reg_addr, input logic [7:0] data);
        begin
            @(negedge clk);
            addr = reg_addr;
            wdata = {24'd0, data};
            wstrb = 4'h1;
            we = 1'b1;
            valid = 1'b1;
            @(posedge clk);
            if (!ready) $fatal(1, "byte write did not complete");
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
        if (value !== 32'd18) $fatal(1, "bad virtio input device id: %08x", value);
        write_reg(32'h0000_0014, 32'd1);
        read_reg(32'h0000_0010, value);
        if (value !== 32'h0000_0001) $fatal(1, "missing VERSION_1 feature: %08x", value);

        write_byte(32'h0000_0100, 8'h01);
        write_byte(32'h0000_0101, 8'h00);
        read_reg(32'h0000_0102, value);
        if (value[7:0] !== 8'd20) $fatal(1, "bad input name size: %08x", value);
        read_reg(32'h0000_0108, value);
        if (value !== 32'h3436_585a) $fatal(1, "bad input name prefix: %08x", value);

        write_byte(32'h0000_0100, 8'h11);
        write_byte(32'h0000_0101, 8'd1);
        read_reg(32'h0000_0102, value);
        if (value[7:0] !== 8'd7) $fatal(1, "bad EV_KEY bitmap size: %08x", value);
        read_reg(32'h0000_0108, value);
        if (value[31:24] !== 8'h50) $fatal(1, "missing KEY_ENTER/KEY_A bits: %08x", value);
        read_reg(32'h0000_010c, value);
        if (value[23:16] !== 8'h01) $fatal(1, "missing KEY_B bit: %08x", value);

        write_reg(32'h0000_0030, 32'd0);
        write_reg(32'h0000_0038, 32'd128);
        read_reg(32'h0000_0038, value);
        if (value !== 32'd64) $fatal(1, "queue 0 num was not clamped: %08x", value);
        write_reg(32'h0000_0030, 32'd1);
        write_reg(32'h0000_0038, 32'd32);
        read_reg(32'h0000_0038, value);
        if (value !== 32'd32) $fatal(1, "queue 1 num mismatch: %08x", value);

        write_reg(32'h0000_0050, 32'd1);
        if (!notify_pulse || !notify_pending || notify_queue !== 16'd1 || notify_count !== 32'd1) begin
            $fatal(1, "notify mismatch pulse=%0d pending=%0d queue=%0d count=%0d",
                   notify_pulse, notify_pending, notify_queue, notify_count);
        end

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

        $display("tb_mmio_virtio_input_regs: PASS");
        $finish;
    end
endmodule
