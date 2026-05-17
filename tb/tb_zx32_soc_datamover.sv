module tb_zx32_soc_datamover;
    logic clk;
    logic rst_n;
    logic uart_tx;

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

    logic        host_valid;
    logic        host_we;
    logic [3:0]  host_wstrb;
    logic [31:0] host_addr;
    logic [31:0] host_wdata;
    logic        host_ready;
    logic [31:0] host_rdata;

    logic [31:0] src_words [0:15];
    logic [31:0] dst_words [0:15];
    integer i;

    localparam logic [31:0] DM_BASE = 32'h1002_0000;
    localparam logic [31:0] TIMER_BASE = 32'h1001_0000;
    localparam logic [31:0] CTRL_BASE = 32'h1003_0000;
    localparam logic [31:0] IMEM_BASE = 32'h0000_0000;
    localparam logic [31:0] TX_BASE = 32'h2001_0000;
    localparam logic [31:0] MAIL_START = TX_BASE + 32'h3e0;
    localparam logic [31:0] MAIL_SRC = TX_BASE + 32'h3e4;
    localparam logic [31:0] MAIL_DST = TX_BASE + 32'h3e8;
    localparam logic [31:0] MAIL_LEN = TX_BASE + 32'h3ec;
    localparam logic [31:0] MAIL_STATUS = TX_BASE + 32'h3f0;
    localparam logic [31:0] MAIL_MM2S_STATUS = TX_BASE + 32'h3f4;
    localparam logic [31:0] MAIL_S2MM_STATUS = TX_BASE + 32'h3f8;
    localparam logic [31:0] MAIL_COPIED = TX_BASE + 32'h3fc;
    localparam logic [31:0] CPU_START_MAGIC = 32'h4350_5521;
    localparam logic [31:0] CPU_PASS = 32'h0000_0222;
    localparam logic [31:0] CPU_FAIL = 32'h0000_0333;
    localparam logic [31:0] LOAD_TEST_PASS = 32'habcd_1234;

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
        .dm_s_axis_s2mm_tready(dm_s_axis_s2mm_tready)
    );

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
            data = host_rdata;
            @(negedge clk);
            host_valid = 1'b0;
        end
    endtask

    initial begin
        logic [31:0] status;
        logic [31:0] copied;

        host_valid = 1'b0;
        host_we = 1'b0;
        host_wstrb = 4'd0;
        host_addr = 32'd0;
        host_wdata = 32'd0;
        dm_mm2s_cmd_ready = 1'b1;
        dm_mm2s_sts_valid = 1'b0;
        dm_mm2s_sts_data = 8'd0;
        dm_s2mm_cmd_ready = 1'b1;
        dm_s2mm_sts_valid = 1'b0;
        dm_s2mm_sts_data = 8'd0;
        dm_m_axis_mm2s_tdata = 32'd0;
        dm_m_axis_mm2s_tkeep = 4'd0;
        dm_m_axis_mm2s_tlast = 1'b0;
        dm_m_axis_mm2s_tvalid = 1'b0;
        dm_s_axis_s2mm_tready = 1'b1;

        for (i = 0; i < 16; i = i + 1) begin
            src_words[i] = 32'h5a00_0000 | (i * 32'h0001_0101) | i[31:0];
            dst_words[i] = 32'd0;
        end

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        host_write(TIMER_BASE + 32'h0008, 32'd20);
        host_write(TIMER_BASE + 32'h000c, 32'd0);
        repeat (30) @(posedge clk);
        host_read(TIMER_BASE + 32'h0010, status);
        if (status[0] !== 1'b1) begin
            $fatal(1, "timer irq did not assert, status=%08x", status);
        end

        host_write(MAIL_STATUS, 32'd0);
        host_write(MAIL_MM2S_STATUS, 32'd0);
        host_write(MAIL_S2MM_STATUS, 32'd0);
        host_write(MAIL_COPIED, 32'd0);
        host_write(MAIL_START, 32'd0);
        host_write(MAIL_SRC, 32'h8000_0000);
        host_write(MAIL_DST, 32'h8000_0100);
        host_write(MAIL_LEN, 32'd64);
        host_write(MAIL_START, CPU_START_MAGIC);
        host_read(MAIL_START, status);
        if (status !== CPU_START_MAGIC) begin
            $fatal(1, "mailbox start readback mismatch: %08x", status);
        end

        repeat (4000) begin
            host_read(MAIL_STATUS, status);
            if (status == CPU_PASS || status == CPU_FAIL) begin
                break;
            end
            @(posedge clk);
        end

        if (status !== CPU_PASS) begin
            $fatal(1, "CPU DataMover program failed or timed out, status=%08x start_mem=%08x pc=%08x x4=%08x x5=%08x",
                   status, u_soc.u_scratchpad.tx_mem[248], u_soc.u_core.pc,
                   u_soc.u_core.u_regfile.regs[4], u_soc.u_core.u_regfile.regs[5]);
        end

        host_read(MAIL_COPIED, copied);
        if (copied !== 32'd16) begin
            $fatal(1, "expected copied word count 16, got %08x", copied);
        end

        for (i = 0; i < 16; i = i + 1) begin
            if (dst_words[i] !== src_words[i]) begin
                $fatal(1, "dst[%0d] mismatch: expected %08x got %08x", i, src_words[i], dst_words[i]);
            end
        end

        host_write(CTRL_BASE, 32'd1);
        host_write(MAIL_STATUS, 32'd0);
        host_write(IMEM_BASE + 32'd0,  32'h2001_00b7);
        host_write(IMEM_BASE + 32'd4,  32'habcd_1137);
        host_write(IMEM_BASE + 32'd8,  32'h2341_0113);
        host_write(IMEM_BASE + 32'd12, 32'h3e20_a823);
        host_write(IMEM_BASE + 32'd16, 32'h0000_006f);
        host_write(CTRL_BASE, 32'd0);

        repeat (1000) begin
            host_read(MAIL_STATUS, status);
            if (status == LOAD_TEST_PASS) begin
                break;
            end
            @(posedge clk);
        end
        if (status !== LOAD_TEST_PASS) begin
            $fatal(1, "CPU BRAM load/run test failed, status=%08x", status);
        end

        for (i = 0; i < 16; i = i + 1) begin
            src_words[i] = 32'h6b00_0000 | (i * 32'h0001_0101) | i[31:0];
            dst_words[i] = 32'd0;
        end

        host_write(CTRL_BASE, 32'd1);
        host_write(MAIL_STATUS, 32'd0);
        host_write(MAIL_MM2S_STATUS, 32'd0);
        host_write(MAIL_S2MM_STATUS, 32'd0);
        host_write(MAIL_COPIED, 32'd0);
        host_write(MAIL_START, 32'd0);
        host_write(MAIL_SRC, 32'h8000_0000);
        host_write(MAIL_DST, 32'h8000_0100);
        host_write(MAIL_LEN, 32'd64);
        host_write(IMEM_BASE + 32'd0,  32'h2001_00b7);
        host_write(IMEM_BASE + 32'd4,  32'h2001_0137);
        host_write(IMEM_BASE + 32'd8,  32'h2000_01b7);
        host_write(IMEM_BASE + 32'd12, 32'h4350_5237);
        host_write(IMEM_BASE + 32'd16, 32'h5212_0213);
        host_write(IMEM_BASE + 32'd20, 32'h1110_0293);
        host_write(IMEM_BASE + 32'd24, 32'h3e51_2823);
        host_write(IMEM_BASE + 32'd28, 32'h3e01_2283);
        host_write(IMEM_BASE + 32'd32, 32'hfe42_9ee3);
        host_write(IMEM_BASE + 32'd36, 32'h3e41_2303);
        host_write(IMEM_BASE + 32'd40, 32'h3e81_2383);
        host_write(IMEM_BASE + 32'd44, 32'h3ec1_2403);
        host_write(IMEM_BASE + 32'd48, 32'h0083_148b);
        host_write(IMEM_BASE + 32'd52, 32'h3e91_2a23);
        host_write(IMEM_BASE + 32'd56, 32'h0104_f513);
        host_write(IMEM_BASE + 32'd60, 32'h0805_1063);
        host_write(IMEM_BASE + 32'd64, 32'h0001_8593);
        host_write(IMEM_BASE + 32'd68, 32'h0001_0613);
        host_write(IMEM_BASE + 32'd72, 32'h0004_0693);
        host_write(IMEM_BASE + 32'd76, 32'h0000_0793);
        host_write(IMEM_BASE + 32'd80, 32'h0005_a703);
        host_write(IMEM_BASE + 32'd84, 32'h00e6_2023);
        host_write(IMEM_BASE + 32'd88, 32'h0045_8593);
        host_write(IMEM_BASE + 32'd92, 32'h0046_0613);
        host_write(IMEM_BASE + 32'd96, 32'hffc6_8693);
        host_write(IMEM_BASE + 32'd100, 32'h0017_8793);
        host_write(IMEM_BASE + 32'd104, 32'hfe06_94e3);
        host_write(IMEM_BASE + 32'd108, 32'h0083_a48b);
        host_write(IMEM_BASE + 32'd112, 32'h3e91_2c23);
        host_write(IMEM_BASE + 32'd116, 32'h0204_f513);
        host_write(IMEM_BASE + 32'd120, 32'h3ef1_2e23);
        host_write(IMEM_BASE + 32'd124, 32'h2220_0293);
        host_write(IMEM_BASE + 32'd128, 32'h3e51_2823);
        host_write(IMEM_BASE + 32'd132, 32'h0000_006f);
        host_write(IMEM_BASE + 32'd136, 32'h3330_0293);
        host_write(IMEM_BASE + 32'd140, 32'h3e51_2823);
        host_write(IMEM_BASE + 32'd144, 32'h0000_006f);
        host_write(CTRL_BASE, 32'd0);
        host_write(MAIL_START, CPU_START_MAGIC);

        repeat (4000) begin
            host_read(MAIL_STATUS, status);
            if (status == CPU_PASS || status == CPU_FAIL) begin
                break;
            end
            @(posedge clk);
        end

        if (status !== CPU_PASS) begin
            $fatal(1, "CPU custom DataMover program failed or timed out, status=%08x", status);
        end

        host_read(MAIL_COPIED, copied);
        if (copied !== 32'd16) begin
            $fatal(1, "expected custom copied word count 16, got %08x", copied);
        end

        for (i = 0; i < 16; i = i + 1) begin
            if (dst_words[i] !== src_words[i]) begin
                $fatal(1, "custom dst[%0d] mismatch: expected %08x got %08x", i, src_words[i], dst_words[i]);
            end
        end

        $display("PASS");
        $finish;
    end

    always @(posedge clk) begin
        if (dm_mm2s_cmd_valid && dm_mm2s_cmd_ready) begin
            if (dm_mm2s_cmd_data !== 72'h01_8000_0000_4080_0040) begin
                $fatal(1, "unexpected MM2S command %018x", dm_mm2s_cmd_data);
            end

            for (i = 0; i < 16; i = i + 1) begin
                @(negedge clk);
                dm_m_axis_mm2s_tdata = src_words[i];
                dm_m_axis_mm2s_tkeep = 4'b1111;
                dm_m_axis_mm2s_tlast = (i == 15);
                dm_m_axis_mm2s_tvalid = 1'b1;
            end
            @(negedge clk);
            dm_m_axis_mm2s_tvalid = 1'b0;
            dm_m_axis_mm2s_tlast = 1'b0;
            @(negedge clk);
            dm_mm2s_sts_data = 8'd0;
            dm_mm2s_sts_valid = 1'b1;
            @(negedge clk);
            dm_mm2s_sts_valid = 1'b0;
        end

        if (dm_s2mm_cmd_valid && dm_s2mm_cmd_ready) begin
            if (dm_s2mm_cmd_data !== 72'h02_8000_0100_c080_0040) begin
                $fatal(1, "unexpected S2MM command %018x", dm_s2mm_cmd_data);
            end

            for (i = 0; i < 16; i = i + 1) begin
                do begin
                    @(posedge clk);
                end while (!dm_s_axis_s2mm_tvalid);
                dst_words[i] = dm_s_axis_s2mm_tdata;
            end
            @(negedge clk);
            dm_s2mm_sts_data = 8'd0;
            dm_s2mm_sts_valid = 1'b1;
            @(negedge clk);
            dm_s2mm_sts_valid = 1'b0;
        end
    end
endmodule
