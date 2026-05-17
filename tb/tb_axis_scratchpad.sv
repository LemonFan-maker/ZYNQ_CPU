module tb_axis_scratchpad;
    logic clk;
    logic rst_n;

    logic        cpu_valid;
    logic        cpu_we;
    logic [3:0]  cpu_wstrb;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_wdata;
    logic        cpu_ready;
    logic [31:0] cpu_rdata;

    logic        mm2s_start;
    logic [31:0] mm2s_local_addr;
    logic [31:0] mm2s_length_bytes;
    logic        mm2s_ready;
    logic        mm2s_done;
    logic        mm2s_error;
    logic [31:0] s_axis_mm2s_tdata;
    logic [3:0]  s_axis_mm2s_tkeep;
    logic        s_axis_mm2s_tlast;
    logic        s_axis_mm2s_tvalid;
    logic        s_axis_mm2s_tready;

    logic        s2mm_start;
    logic [31:0] s2mm_local_addr;
    logic [31:0] s2mm_length_bytes;
    logic        s2mm_ready;
    logic        s2mm_done;
    logic        s2mm_error;
    logic [31:0] m_axis_s2mm_tdata;
    logic [3:0]  m_axis_s2mm_tkeep;
    logic        m_axis_s2mm_tlast;
    logic        m_axis_s2mm_tvalid;
    logic        m_axis_s2mm_tready;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    axis_scratchpad #(.WORDS(64)) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_valid(cpu_valid),
        .cpu_we(cpu_we),
        .cpu_wstrb(cpu_wstrb),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready),
        .cpu_rdata(cpu_rdata),
        .mm2s_start(mm2s_start),
        .mm2s_local_addr(mm2s_local_addr),
        .mm2s_length_bytes(mm2s_length_bytes),
        .mm2s_ready(mm2s_ready),
        .mm2s_done(mm2s_done),
        .mm2s_error(mm2s_error),
        .s_axis_mm2s_tdata(s_axis_mm2s_tdata),
        .s_axis_mm2s_tkeep(s_axis_mm2s_tkeep),
        .s_axis_mm2s_tlast(s_axis_mm2s_tlast),
        .s_axis_mm2s_tvalid(s_axis_mm2s_tvalid),
        .s_axis_mm2s_tready(s_axis_mm2s_tready),
        .s2mm_start(s2mm_start),
        .s2mm_local_addr(s2mm_local_addr),
        .s2mm_length_bytes(s2mm_length_bytes),
        .s2mm_ready(s2mm_ready),
        .s2mm_done(s2mm_done),
        .s2mm_error(s2mm_error),
        .m_axis_s2mm_tdata(m_axis_s2mm_tdata),
        .m_axis_s2mm_tkeep(m_axis_s2mm_tkeep),
        .m_axis_s2mm_tlast(m_axis_s2mm_tlast),
        .m_axis_s2mm_tvalid(m_axis_s2mm_tvalid),
        .m_axis_s2mm_tready(m_axis_s2mm_tready)
    );

    task automatic cpu_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            cpu_valid = 1'b1;
            cpu_we = 1'b1;
            cpu_wstrb = 4'b1111;
            cpu_addr = addr;
            cpu_wdata = data;
            wait (cpu_ready);
            @(negedge clk);
            cpu_valid = 1'b0;
            cpu_we = 1'b0;
        end
    endtask

    initial begin
        cpu_valid = 1'b0;
        cpu_we = 1'b0;
        cpu_wstrb = 4'd0;
        cpu_addr = 32'd0;
        cpu_wdata = 32'd0;
        mm2s_start = 1'b0;
        mm2s_local_addr = 32'd0;
        mm2s_length_bytes = 32'd0;
        s_axis_mm2s_tdata = 32'd0;
        s_axis_mm2s_tkeep = 4'd0;
        s_axis_mm2s_tlast = 1'b0;
        s_axis_mm2s_tvalid = 1'b0;
        s2mm_start = 1'b0;
        s2mm_local_addr = 32'd0;
        s2mm_length_bytes = 32'd0;
        m_axis_s2mm_tready = 1'b1;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        mm2s_local_addr = 32'd0;
        mm2s_length_bytes = 32'd5;
        @(negedge clk);
        mm2s_start = 1'b1;
        @(negedge clk);
        mm2s_start = 1'b0;

        wait (s_axis_mm2s_tready);
        s_axis_mm2s_tvalid = 1'b1;
        s_axis_mm2s_tdata = 32'haabb_ccdd;
        s_axis_mm2s_tkeep = 4'b1111;
        s_axis_mm2s_tlast = 1'b0;
        @(negedge clk);
        s_axis_mm2s_tdata = 32'h0000_00ee;
        s_axis_mm2s_tkeep = 4'b0001;
        s_axis_mm2s_tlast = 1'b1;
        @(negedge clk);
        s_axis_mm2s_tvalid = 1'b0;
        s_axis_mm2s_tlast = 1'b0;

        repeat (2) @(posedge clk);
        if (!mm2s_done || mm2s_error) begin
            $fatal(1, "MM2S scratch write did not complete cleanly");
        end
        if (u_dut.rx_mem[0] !== 32'haabb_ccdd || u_dut.rx_mem[1][7:0] !== 8'hee) begin
            $fatal(1, "unexpected MM2S scratch contents");
        end

        cpu_write(32'h0001_0008, 32'h1122_3344);
        cpu_write(32'h0001_000c, 32'h5566_7788);

        s2mm_local_addr = 32'd8;
        s2mm_length_bytes = 32'd6;
        @(negedge clk);
        s2mm_start = 1'b1;
        @(negedge clk);
        s2mm_start = 1'b0;

        wait (m_axis_s2mm_tvalid);
        if (m_axis_s2mm_tdata !== 32'h1122_3344 || m_axis_s2mm_tkeep !== 4'b1111 || m_axis_s2mm_tlast) begin
            $fatal(1, "unexpected S2MM beat 0");
        end
        @(posedge clk);
        #1;
        if (m_axis_s2mm_tdata !== 32'h5566_7788 || m_axis_s2mm_tkeep !== 4'b0011 || !m_axis_s2mm_tlast) begin
            $fatal(1, "unexpected S2MM beat 1");
        end

        repeat (2) @(posedge clk);
        if (!s2mm_done || s2mm_error) begin
            $fatal(1, "S2MM scratch read did not complete cleanly");
        end

        $display("PASS");
        $finish;
    end
endmodule
