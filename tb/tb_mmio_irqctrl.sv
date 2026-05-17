module tb_mmio_irqctrl;
    logic clk;
    logic rst_n;

    logic        valid;
    logic        we;
    logic [3:0]  wstrb;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic        ready;
    logic [31:0] rdata;
    logic [7:0]  source_irq;
    logic        irq_external;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    mmio_irqctrl #(.NUM_SOURCES(8)) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .we(we),
        .wstrb(wstrb),
        .addr(addr),
        .wdata(wdata),
        .ready(ready),
        .rdata(rdata),
        .source_irq(source_irq),
        .irq_external(irq_external)
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
            while (ready !== 1'b1) begin
                @(posedge clk);
            end
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
            while (ready !== 1'b1) begin
                @(posedge clk);
            end
            data = rdata;
            @(negedge clk);
            valid = 1'b0;
        end
    endtask

    initial begin
        logic [31:0] claim;

        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;
        source_irq = 8'd0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        write_reg(32'h0000_0004, 32'h0000_0009);
        write_reg(32'h0000_0000, 32'h0000_0009);

        read_reg(32'h0000_000c, claim);
        if (claim !== 32'd4 || !irq_external) begin
            $fatal(1, "expected claim=4 with irq asserted, got claim=%08x irq=%0d", claim, irq_external);
        end

        write_reg(32'h0000_000c, 32'd4);
        read_reg(32'h0000_000c, claim);
        if (claim !== 32'd1 || !irq_external) begin
            $fatal(1, "expected claim=1 after completing source 4, got claim=%08x irq=%0d", claim, irq_external);
        end

        write_reg(32'h0000_0008, 32'd4);
        read_reg(32'h0000_000c, claim);
        if (claim !== 32'd0 || irq_external) begin
            $fatal(1, "expected claim=0 with threshold=4, got claim=%08x irq=%0d", claim, irq_external);
        end

        write_reg(32'h0000_0008, 32'd0);
        read_reg(32'h0000_000c, claim);
        if (claim !== 32'd1 || !irq_external) begin
            $fatal(1, "expected claim=1 after lowering threshold, got claim=%08x irq=%0d", claim, irq_external);
        end

        write_reg(32'h0000_000c, 32'd1);
        read_reg(32'h0000_000c, claim);
        if (claim !== 32'd0 || irq_external) begin
            $fatal(1, "expected irq to deassert after clearing all pending bits, got claim=%08x irq=%0d", claim, irq_external);
        end

        $display("PASS");
        $finish;
    end
endmodule
