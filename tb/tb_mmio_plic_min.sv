module tb_mmio_plic_min;
    logic clk;
    logic rst_n;
    logic valid;
    logic we;
    logic [3:0]  wstrb;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic        ready;
    logic [31:0] rdata;
    logic [0:0]  source_irq;
    logic        irq_external;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    mmio_plic_min #(.NUM_SOURCES(1)) u_dut (
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
        source_irq = 1'b0;
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        write_reg(32'h0000_0004, 32'd1); // source 1 priority
        write_reg(32'h0000_2000, 32'h0000_0002); // source 1 enable bit

		source_irq = 1'b1;
		repeat (2) @(posedge clk);

		read_reg(32'h0000_1000, value);
		if (value !== 32'h0000_0002) begin
			$fatal(1, "pending bit mismatch: %08x", value);
		end
        read_reg(32'h0020_0004, value);
        if (value !== 32'd1 || irq_external) begin
            $fatal(1, "claim should return 1 and clear irq, claim=%08x irq=%0d", value, irq_external);
        end
		read_reg(32'h0020_0004, value);
		if (value !== 32'd0 || irq_external) begin
			$fatal(1, "claim should stay empty while source is in-flight, claim=%08x irq=%0d", value, irq_external);
		end
		write_reg(32'h0020_0004, 32'd1);
		repeat (2) @(posedge clk);
		read_reg(32'h0020_0004, value);
		if (value !== 32'd1 || irq_external) begin
			$fatal(1, "claim should re-pend after complete with source high, claim=%08x irq=%0d", value, irq_external);
		end
		source_irq = 1'b0;
		write_reg(32'h0020_0004, 32'd1);
		repeat (2) @(posedge clk);
		read_reg(32'h0020_0004, value);
		if (value !== 32'd0 || irq_external) begin
			$fatal(1, "claim should be empty after source drops and completes, claim=%08x irq=%0d", value, irq_external);
		end

		source_irq = 1'b1;
		repeat (2) @(posedge clk);
		source_irq = 1'b0;
        write_reg(32'h0020_0000, 32'd1); // threshold == priority blocks source 1
        read_reg(32'h0020_0004, value);
        if (value !== 32'd0 || irq_external) begin
            $fatal(1, "threshold should block source 1, claim=%08x irq=%0d", value, irq_external);
        end

        $display("tb_mmio_plic_min: PASS");
        $finish;
    end
endmodule
