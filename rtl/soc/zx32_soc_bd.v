module zx32_soc_bd (
    input  wire        clk,
    input  wire        rst_n,
    output wire        uart_tx,
    output wire        display_enable,
    output wire        display_test_pattern_enable,
    output wire        display_text_enable,
    output wire        display_text_clear,
    output wire [1:0]  display_mode,
    output wire [31:0] display_bg_color,
    output wire        display_text_we,
    output wire [11:0] display_text_word_addr,
    output wire [31:0] display_text_wdata,
    output wire [3:0]  display_text_wstrb,
    output wire        display_font_we,
    output wire [8:0]  display_font_word_addr,
    output wire [31:0] display_font_wdata,
    output wire [3:0]  display_font_wstrb,

    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [15:0] S_AXI_AWADDR,
    input  wire [2:0]  S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [15:0] S_AXI_ARADDR,
    input  wire [2:0]  S_AXI_ARPROT,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output reg  [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    output wire        dm_mm2s_cmd_valid,
    input  wire        dm_mm2s_cmd_ready,
    output wire [71:0] dm_mm2s_cmd_data,
    input  wire        dm_mm2s_sts_valid,
    output wire        dm_mm2s_sts_ready,
    input  wire [7:0]  dm_mm2s_sts_data,

    output wire        dm_s2mm_cmd_valid,
    input  wire        dm_s2mm_cmd_ready,
    output wire [71:0] dm_s2mm_cmd_data,
    input  wire        dm_s2mm_sts_valid,
    output wire        dm_s2mm_sts_ready,
    input  wire [7:0]  dm_s2mm_sts_data,

    input  wire [31:0] dm_m_axis_mm2s_tdata,
    input  wire [3:0]  dm_m_axis_mm2s_tkeep,
    input  wire        dm_m_axis_mm2s_tlast,
    input  wire        dm_m_axis_mm2s_tvalid,
    output wire        dm_m_axis_mm2s_tready,

    output wire [31:0] dm_s_axis_s2mm_tdata,
    output wire [3:0]  dm_s_axis_s2mm_tkeep,
    output wire        dm_s_axis_s2mm_tlast,
    output wire        dm_s_axis_s2mm_tvalid,
    input  wire        dm_s_axis_s2mm_tready,

    output wire [3:0]  M_AXI_DDR_AWID,
    output wire [31:0] M_AXI_DDR_AWADDR,
    output wire [7:0]  M_AXI_DDR_AWLEN,
    output wire [2:0]  M_AXI_DDR_AWSIZE,
    output wire [1:0]  M_AXI_DDR_AWBURST,
    output wire        M_AXI_DDR_AWLOCK,
    output wire [3:0]  M_AXI_DDR_AWCACHE,
    output wire [2:0]  M_AXI_DDR_AWPROT,
    output wire [3:0]  M_AXI_DDR_AWQOS,
    output wire        M_AXI_DDR_AWVALID,
    input  wire        M_AXI_DDR_AWREADY,
    output wire [31:0] M_AXI_DDR_WDATA,
    output wire [3:0]  M_AXI_DDR_WSTRB,
    output wire        M_AXI_DDR_WLAST,
    output wire        M_AXI_DDR_WVALID,
    input  wire        M_AXI_DDR_WREADY,
    input  wire [3:0]  M_AXI_DDR_BID,
    input  wire [1:0]  M_AXI_DDR_BRESP,
    input  wire        M_AXI_DDR_BVALID,
    output wire        M_AXI_DDR_BREADY,
    output wire [3:0]  M_AXI_DDR_ARID,
    output wire [31:0] M_AXI_DDR_ARADDR,
    output wire [7:0]  M_AXI_DDR_ARLEN,
    output wire [2:0]  M_AXI_DDR_ARSIZE,
    output wire [1:0]  M_AXI_DDR_ARBURST,
    output wire        M_AXI_DDR_ARLOCK,
    output wire [3:0]  M_AXI_DDR_ARCACHE,
    output wire [2:0]  M_AXI_DDR_ARPROT,
    output wire [3:0]  M_AXI_DDR_ARQOS,
    output wire        M_AXI_DDR_ARVALID,
    input  wire        M_AXI_DDR_ARREADY,
    input  wire [3:0]  M_AXI_DDR_RID,
    input  wire [31:0] M_AXI_DDR_RDATA,
    input  wire [1:0]  M_AXI_DDR_RRESP,
    input  wire        M_AXI_DDR_RLAST,
    input  wire        M_AXI_DDR_RVALID,
    output wire        M_AXI_DDR_RREADY
);
    localparam AXI_IDLE  = 2'd0;
    localparam AXI_WRITE = 2'd1;
    localparam AXI_READ  = 2'd2;

    reg [1:0]  axi_state;
    reg [15:0] awaddr_q;
    reg [15:0] araddr_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        aw_seen;
    reg        w_seen;

    wire        host_valid;
    wire        host_we;
    wire [31:0] host_addr;
    wire [31:0] host_wdata;
    wire [3:0]  host_wstrb;
    wire        host_ready;
    wire [31:0] host_rdata;

    assign S_AXI_AWREADY = (axi_state == AXI_IDLE) && !aw_seen && !S_AXI_BVALID && !S_AXI_RVALID;
    assign S_AXI_WREADY  = (axi_state == AXI_IDLE) && !w_seen && !S_AXI_BVALID && !S_AXI_RVALID;
    assign S_AXI_ARREADY = (axi_state == AXI_IDLE) && !aw_seen && !w_seen && !S_AXI_BVALID && !S_AXI_RVALID;
    assign S_AXI_BRESP = 2'b00;
    assign S_AXI_RRESP = 2'b00;

    assign host_valid = (axi_state == AXI_WRITE) || (axi_state == AXI_READ);
    assign host_we = (axi_state == AXI_WRITE);
    assign host_wdata = wdata_q;
    assign host_wstrb = wstrb_q;
    assign host_addr = translate_addr((axi_state == AXI_READ) ? araddr_q : awaddr_q);

    function [31:0] translate_addr;
        input [15:0] axi_addr;
        begin
            case (axi_addr[15:12])
                4'h0: translate_addr = 32'h1002_0000 + {20'd0, axi_addr[11:0]};
                4'h1: translate_addr = 32'h2000_0000 + {20'd0, axi_addr[11:0]};
                4'h2: translate_addr = 32'h2001_0000 + {20'd0, axi_addr[11:0]};
                4'h3,
                4'h4,
                4'h5,
                4'h6: translate_addr = {16'd0, axi_addr - 16'h3000};
                4'h7: translate_addr = 32'h1003_0000 + {20'd0, axi_addr[11:0]};
                4'h8: translate_addr = 32'h1001_0000 + {20'd0, axi_addr[11:0]};
                4'h9,
                4'ha,
                4'hb,
                4'hc,
                4'hd,
                4'he,
                4'hf: translate_addr = 32'h1008_0000 + {16'd0, axi_addr - 16'h9000};
                default: translate_addr = 32'hffff_0000 + {16'd0, axi_addr};
            endcase
        end
    endfunction

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            axi_state <= AXI_IDLE;
            awaddr_q <= 16'd0;
            araddr_q <= 16'd0;
            wdata_q <= 32'd0;
            wstrb_q <= 4'd0;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
            S_AXI_BVALID <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA <= 32'd0;
        end else begin
            if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end

            if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                awaddr_q <= S_AXI_AWADDR;
                aw_seen <= 1'b1;
            end
            if (S_AXI_WREADY && S_AXI_WVALID) begin
                wdata_q <= S_AXI_WDATA;
                wstrb_q <= S_AXI_WSTRB;
                w_seen <= 1'b1;
            end
            if (S_AXI_ARREADY && S_AXI_ARVALID) begin
                araddr_q <= S_AXI_ARADDR;
                axi_state <= AXI_READ;
            end else if (axi_state == AXI_IDLE && (aw_seen || S_AXI_AWVALID) && (w_seen || S_AXI_WVALID)) begin
                if (!aw_seen && S_AXI_AWVALID) begin
                    awaddr_q <= S_AXI_AWADDR;
                end
                if (!w_seen && S_AXI_WVALID) begin
                    wdata_q <= S_AXI_WDATA;
                    wstrb_q <= S_AXI_WSTRB;
                end
                axi_state <= AXI_WRITE;
            end else if (axi_state == AXI_WRITE && host_ready) begin
                axi_state <= AXI_IDLE;
                aw_seen <= 1'b0;
                w_seen <= 1'b0;
                S_AXI_BVALID <= 1'b1;
            end else if (axi_state == AXI_READ && host_ready) begin
                axi_state <= AXI_IDLE;
                S_AXI_RDATA <= host_rdata;
                S_AXI_RVALID <= 1'b1;
            end
        end
    end

    zx32_soc u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx(uart_tx),
        .display_enable_o(display_enable),
        .display_test_pattern_enable_o(display_test_pattern_enable),
        .display_text_enable_o(display_text_enable),
        .display_text_clear_o(display_text_clear),
        .display_mode_o(display_mode),
        .display_bg_color_o(display_bg_color),
        .display_text_we_o(display_text_we),
        .display_text_word_addr_o(display_text_word_addr),
        .display_text_wdata_o(display_text_wdata),
        .display_text_wstrb_o(display_text_wstrb),
        .display_font_we_o(display_font_we),
        .display_font_word_addr_o(display_font_word_addr),
        .display_font_wdata_o(display_font_wdata),
        .display_font_wstrb_o(display_font_wstrb),
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
endmodule
