module tb_zx64_soc_bd_host;
    logic clk;
    logic rst_n;

    logic [15:0] S_AXI_AWADDR;
    logic [2:0]  S_AXI_AWPROT;
    logic        S_AXI_AWVALID;
    logic        S_AXI_AWREADY;
    logic [31:0] S_AXI_WDATA;
    logic [3:0]  S_AXI_WSTRB;
    logic        S_AXI_WVALID;
    logic        S_AXI_WREADY;
    logic [1:0]  S_AXI_BRESP;
    logic        S_AXI_BVALID;
    logic        S_AXI_BREADY;
    logic [15:0] S_AXI_ARADDR;
    logic [2:0]  S_AXI_ARPROT;
    logic        S_AXI_ARVALID;
    logic        S_AXI_ARREADY;
    logic [31:0] S_AXI_RDATA;
    logic [1:0]  S_AXI_RRESP;
    logic        S_AXI_RVALID;
    logic        S_AXI_RREADY;

    wire        uart_tx;
    wire        display_enable;
    wire        display_test_pattern_enable;
    wire        display_text_enable;
    wire        display_text_clear;
    wire [1:0]  display_mode;
    wire [31:0] display_bg_color;
    wire        display_text_we;
    wire [11:0] display_text_word_addr;
    wire [31:0] display_text_wdata;
    wire [3:0]  display_text_wstrb;
    wire        display_attr_we;
    wire [10:0] display_attr_word_addr;
    wire [31:0] display_attr_wdata;
    wire [3:0]  display_attr_wstrb;
    wire        display_font_we;
    wire [8:0]  display_font_word_addr;
    wire [31:0] display_font_wdata;
    wire [3:0]  display_font_wstrb;

    wire        dm_mm2s_cmd_valid;
    logic       dm_mm2s_cmd_ready;
    wire [71:0] dm_mm2s_cmd_data;
    logic       dm_mm2s_sts_valid;
    wire        dm_mm2s_sts_ready;
    logic [7:0] dm_mm2s_sts_data;
    wire        dm_s2mm_cmd_valid;
    logic       dm_s2mm_cmd_ready;
    wire [71:0] dm_s2mm_cmd_data;
    logic       dm_s2mm_sts_valid;
    wire        dm_s2mm_sts_ready;
    logic [7:0] dm_s2mm_sts_data;
    logic [31:0] dm_m_axis_mm2s_tdata;
    logic [3:0]  dm_m_axis_mm2s_tkeep;
    logic        dm_m_axis_mm2s_tlast;
    logic        dm_m_axis_mm2s_tvalid;
    wire         dm_m_axis_mm2s_tready;
    wire [31:0] dm_s_axis_s2mm_tdata;
    wire [3:0]  dm_s_axis_s2mm_tkeep;
    wire        dm_s_axis_s2mm_tlast;
    wire        dm_s_axis_s2mm_tvalid;
    logic       dm_s_axis_s2mm_tready;

    wire [3:0]  M_AXI_DDR_AWID;
    wire [31:0] M_AXI_DDR_AWADDR;
    wire [7:0]  M_AXI_DDR_AWLEN;
    wire [2:0]  M_AXI_DDR_AWSIZE;
    wire [1:0]  M_AXI_DDR_AWBURST;
    wire        M_AXI_DDR_AWLOCK;
    wire [3:0]  M_AXI_DDR_AWCACHE;
    wire [2:0]  M_AXI_DDR_AWPROT;
    wire [3:0]  M_AXI_DDR_AWQOS;
    wire        M_AXI_DDR_AWVALID;
    logic       M_AXI_DDR_AWREADY;
    wire [31:0] M_AXI_DDR_WDATA;
    wire [3:0]  M_AXI_DDR_WSTRB;
    wire        M_AXI_DDR_WLAST;
    wire        M_AXI_DDR_WVALID;
    logic       M_AXI_DDR_WREADY;
    logic [3:0] M_AXI_DDR_BID;
    logic [1:0] M_AXI_DDR_BRESP;
    logic       M_AXI_DDR_BVALID;
    wire        M_AXI_DDR_BREADY;
    wire [3:0]  M_AXI_DDR_ARID;
    wire [31:0] M_AXI_DDR_ARADDR;
    wire [7:0]  M_AXI_DDR_ARLEN;
    wire [2:0]  M_AXI_DDR_ARSIZE;
    wire [1:0]  M_AXI_DDR_ARBURST;
    wire        M_AXI_DDR_ARLOCK;
    wire [3:0]  M_AXI_DDR_ARCACHE;
    wire [2:0]  M_AXI_DDR_ARPROT;
    wire [3:0]  M_AXI_DDR_ARQOS;
    wire        M_AXI_DDR_ARVALID;
    logic       M_AXI_DDR_ARREADY;
    logic [3:0] M_AXI_DDR_RID;
    logic [31:0] M_AXI_DDR_RDATA;
    logic [1:0] M_AXI_DDR_RRESP;
    logic       M_AXI_DDR_RLAST;
    logic       M_AXI_DDR_RVALID;
    wire        M_AXI_DDR_RREADY;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    zx64_soc_bd u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx(uart_tx),
        .display_enable(display_enable),
        .display_test_pattern_enable(display_test_pattern_enable),
        .display_text_enable(display_text_enable),
        .display_text_clear(display_text_clear),
        .display_mode(display_mode),
        .display_bg_color(display_bg_color),
        .display_text_we(display_text_we),
        .display_text_word_addr(display_text_word_addr),
        .display_text_wdata(display_text_wdata),
        .display_text_wstrb(display_text_wstrb),
        .display_attr_we(display_attr_we),
        .display_attr_word_addr(display_attr_word_addr),
        .display_attr_wdata(display_attr_wdata),
        .display_attr_wstrb(display_attr_wstrb),
        .display_font_we(display_font_we),
        .display_font_word_addr(display_font_word_addr),
        .display_font_wdata(display_font_wdata),
        .display_font_wstrb(display_font_wstrb),
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWPROT(S_AXI_AWPROT),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARPROT(S_AXI_ARPROT),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
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

    assign S_AXI_AWPROT = 3'd0;
    assign S_AXI_ARPROT = 3'd0;

    task automatic axi_write(input logic [15:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            S_AXI_AWADDR = addr;
            S_AXI_WDATA = data;
            S_AXI_WSTRB = 4'hf;
            S_AXI_AWVALID = 1'b1;
            S_AXI_WVALID = 1'b1;
            S_AXI_BREADY = 1'b1;
            do begin
                @(posedge clk);
            end while (!(S_AXI_AWREADY && S_AXI_WREADY));
            @(negedge clk);
            S_AXI_AWVALID = 1'b0;
            S_AXI_WVALID = 1'b0;
            do begin
                @(posedge clk);
            end while (!S_AXI_BVALID);
            @(negedge clk);
            S_AXI_BREADY = 1'b0;
        end
    endtask

    task automatic axi_read(input logic [15:0] addr, output logic [31:0] data);
        begin
            @(negedge clk);
            S_AXI_ARADDR = addr;
            S_AXI_ARVALID = 1'b1;
            S_AXI_RREADY = 1'b1;
            do begin
                @(posedge clk);
            end while (!S_AXI_ARREADY);
            @(negedge clk);
            S_AXI_ARVALID = 1'b0;
            do begin
                @(posedge clk);
            end while (!S_AXI_RVALID);
            data = S_AXI_RDATA;
            @(negedge clk);
            S_AXI_RREADY = 1'b0;
        end
    endtask

    task automatic expect_read(input logic [15:0] addr,
                               input logic [31:0] expected,
                               input string label);
        logic [31:0] got;
        begin
            axi_read(addr, got);
            if (got !== expected) begin
                $fatal(1, "%s read %04x expected=%08x got=%08x", label, addr, expected, got);
            end
        end
    endtask

    initial begin
        logic [31:0] status;

        rst_n = 1'b0;
        S_AXI_AWADDR = 16'd0;
        S_AXI_AWVALID = 1'b0;
        S_AXI_WDATA = 32'd0;
        S_AXI_WSTRB = 4'd0;
        S_AXI_WVALID = 1'b0;
        S_AXI_BREADY = 1'b0;
        S_AXI_ARADDR = 16'd0;
        S_AXI_ARVALID = 1'b0;
        S_AXI_RREADY = 1'b0;
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
        M_AXI_DDR_AWREADY = 1'b0;
        M_AXI_DDR_WREADY = 1'b0;
        M_AXI_DDR_BID = 4'd0;
        M_AXI_DDR_BRESP = 2'd0;
        M_AXI_DDR_BVALID = 1'b0;
        M_AXI_DDR_ARREADY = 1'b0;
        M_AXI_DDR_RID = 4'd0;
        M_AXI_DDR_RDATA = 32'd0;
        M_AXI_DDR_RRESP = 2'd0;
        M_AXI_DDR_RLAST = 1'b0;
        M_AXI_DDR_RVALID = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        expect_read(16'h7000, 32'h0000_0001, "CPU_CTRL reset default");
        expect_read(16'h7008, 32'd4096, "BRAM_WORDS");
        expect_read(16'h700c, 32'd256, "SCRATCH_WORDS");

        axi_write(16'h7010, 32'h1234_5678);
        expect_read(16'h7010, 32'h1234_5678, "RESET_VECTOR");
        axi_write(16'h7000, 32'h0000_0000);
        expect_read(16'h7000, 32'h0000_0000, "CPU_CTRL release");

        axi_write(16'h2300, 32'h8020_0000);
        expect_read(16'h2300, 32'h8020_0000, "TX scratch translate");
        axi_write(16'h1300, 32'hfeed_beef);
        expect_read(16'h1300, 32'hfeed_beef, "RX scratch translate");
        axi_write(16'h3000, 32'h0bad_cafe);
        expect_read(16'h3000, 32'h0bad_cafe, "IMEM translate");

        expect_read(16'h7100, 32'h0000_0000, "virtio backend status reset");
        expect_read(16'h7104, 32'h0000_0000, "virtio notify count reset");
        expect_read(16'h7108, 32'h0000_0000, "virtio notify queue reset");
        expect_read(16'h710c, 32'h0000_0000, "virtio queue num reset");
        expect_read(16'h7110, 32'h0000_0000, "virtio queue ready reset");
        expect_read(16'h70e0, 32'h0000_0000, "cache invalidates reset");
        axi_write(16'h712c, 32'h0000_1000);
        axi_write(16'h7130, 32'h0000_0001);
        expect_read(16'h712c, 32'h0000_1000, "virtio capacity lo");
        expect_read(16'h7130, 32'h0000_0001, "virtio capacity hi");
        axi_write(16'h7134, 32'h0000_0002);
        expect_read(16'h7100, 32'h0000_0002, "virtio backend irq status");
        expect_read(16'h70e0, 32'h0000_0001, "cache invalidates after virtio irq");

        axi_read(16'h7004, status);
        if (status[1:0] === 2'bxx) begin
            $fatal(1, "CPU_STATUS returned X");
        end
        if (display_enable || display_text_we || dm_mm2s_cmd_valid || dm_s2mm_cmd_valid ||
            dm_s_axis_s2mm_tvalid || !dm_mm2s_sts_ready || !dm_s2mm_sts_ready) begin
            $fatal(1, "compatibility pins are not tied to safe idle values");
        end

        $display("tb_zx64_soc_bd_host: PASS");
        $finish;
    end
endmodule
