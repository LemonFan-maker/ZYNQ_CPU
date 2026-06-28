module hdmi_test_pattern_top_xilinx (
    input  wire clk_75mhz,
    input  wire rst_n,
    input  wire display_enable,
    input  wire test_pattern_enable,
    input  wire text_enable,
    input  wire text_clear,
    input  wire [1:0] mode,
    input  wire [31:0] bg_color,
    input  wire text_we,
    input  wire [11:0] text_word_addr,
    input  wire [31:0] text_wdata,
    input  wire [3:0] text_wstrb,
    input  wire attr_we,
    input  wire [10:0] attr_word_addr,
    input  wire [31:0] attr_wdata,
    input  wire [3:0] attr_wstrb,
    input  wire font_we,
    input  wire [8:0] font_word_addr,
    input  wire [31:0] font_wdata,
    input  wire [3:0] font_wstrb,

    output wire HDMI_CLK_P,
    output wire HDMI_CLK_N,
    output wire HDMI_D0_P,
    output wire HDMI_D0_N,
    output wire HDMI_D1_P,
    output wire HDMI_D1_N,
    output wire HDMI_D2_P,
    output wire HDMI_D2_N
);
    wire clk_fb;
    wire clk_fb_buf;
    wire pix_5x_raw;
    wire pix_clk;
    wire pix_5x_clk;
    wire mmcm_locked;
    wire mmcm_unlocked;
    wire [9:0] tmds_red;
    wire [9:0] tmds_green;
    wire [9:0] tmds_blue;
    wire [1:0] video_mode;
    wire [15:0] h_count;
    wire [15:0] v_count;
    wire frame_done;
    wire rst_video_n;
    wire tmds_clk_se;
    reg [2:0] rst_video_sync;
    reg [2:0] rst_serdes_sync;

    assign mmcm_unlocked = !mmcm_locked;
    assign rst_video_n = rst_video_sync[2];
    assign video_mode = 2'd2;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(13.333),
        .DIVCLK_DIVIDE(5),
        .CLKFBOUT_MULT_F(49.500),
        .CLKFBOUT_PHASE(0.000),
        .CLKOUT0_DIVIDE_F(10.000),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT1_DIVIDE(2),
        .CLKOUT1_PHASE(0.000),
        .CLKOUT1_DUTY_CYCLE(0.500)
    ) u_mmcm (
        .CLKIN1(clk_75mhz),
        .CLKFBIN(clk_fb_buf),
        .RST(!rst_n),
        .PWRDWN(1'b0),
        .CLKFBOUT(clk_fb),
        .CLKFBOUTB(),
        .CLKOUT0(),
        .CLKOUT0B(),
        .CLKOUT1(pix_5x_raw),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(mmcm_locked)
    );

    BUFG u_fb_buf (.I(clk_fb), .O(clk_fb_buf));
    BUFIO u_pix_5x_buf (.I(pix_5x_raw), .O(pix_5x_clk));
    BUFR #(
        .BUFR_DIVIDE("5"),
        .SIM_DEVICE("7SERIES")
    ) u_pix_div_buf (
        .I(pix_5x_raw),
        .CE(1'b1),
        .CLR(mmcm_unlocked),
        .O(pix_clk)
    );

    initial begin
        rst_video_sync = 3'b000;
        rst_serdes_sync = 3'b111;
    end

    always @(posedge pix_clk) begin
        if (!rst_n || !mmcm_locked) begin
            rst_video_sync <= 3'b000;
        end else begin
            rst_video_sync <= {rst_video_sync[1:0], 1'b1};
        end
    end

    always @(posedge pix_clk) begin
        if (!rst_video_n) begin
            rst_serdes_sync <= 3'b111;
        end else begin
            rst_serdes_sync <= {rst_serdes_sync[1:0], 1'b0};
        end
    end

    hdmi_text_console_core u_core (
        .sys_clk(clk_75mhz),
        .pix_clk(pix_clk),
        .rst_n(rst_n),
        .pix_rst_n(rst_video_n),
        .enable(display_enable),
        .test_pattern_enable(test_pattern_enable),
        .text_enable(text_enable),
        .text_clear(text_clear),
        .mode(video_mode),
        .bg_color(bg_color),
        .text_we(text_we),
        .text_word_addr(text_word_addr),
        .text_wdata(text_wdata),
        .text_wstrb(text_wstrb),
        .attr_we(attr_we),
        .attr_word_addr(attr_word_addr),
        .attr_wdata(attr_wdata),
        .attr_wstrb(attr_wstrb),
        .font_we(font_we),
        .font_word_addr(font_word_addr),
        .font_wdata(font_wdata),
        .font_wstrb(font_wstrb),
        .tmds_red(tmds_red),
        .tmds_green(tmds_green),
        .tmds_blue(tmds_blue),
        .h_count(h_count),
        .v_count(v_count),
        .frame_done(frame_done)
    );

    hdmi_tmds_oserdes_xilinx u_ser_red (
        .pix_clk(pix_clk),
        .pix_5x_clk(pix_5x_clk),
        .rst(rst_serdes_sync[2]),
        .data(tmds_red),
        .out_p(HDMI_D2_P),
        .out_n(HDMI_D2_N)
    );

    hdmi_tmds_oserdes_xilinx u_ser_green (
        .pix_clk(pix_clk),
        .pix_5x_clk(pix_5x_clk),
        .rst(rst_serdes_sync[2]),
        .data(tmds_green),
        .out_p(HDMI_D1_P),
        .out_n(HDMI_D1_N)
    );

    hdmi_tmds_oserdes_xilinx u_ser_blue (
        .pix_clk(pix_clk),
        .pix_5x_clk(pix_5x_clk),
        .rst(rst_serdes_sync[2]),
        .data(tmds_blue),
        .out_p(HDMI_D0_P),
        .out_n(HDMI_D0_N)
    );

    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE")
    ) u_clk_oddr (
        .C(pix_clk),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(rst_serdes_sync[2]),
        .S(1'b0),
        .Q(tmds_clk_se)
    );

    OBUFDS #(.IOSTANDARD("TMDS_33")) u_clk_obuf (
        .I(tmds_clk_se),
        .O(HDMI_CLK_P),
        .OB(HDMI_CLK_N)
    );
endmodule
