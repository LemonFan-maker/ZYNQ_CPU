// Board top for the 480x272 DE-mode LCD on J20 (AX7020B, BANK35 LVCMOS33).
// This is a Xilinx-primitives file (hence .v): MMCM + BUFG + ODDR only, no
// vendor-independent simulation.
//
// Clocking recipe is the classes-project one that measured clean on an
// AN340-class panel: MMCM from the 75 MHz system clock (VCO 675 MHz),
// pclk 9.375 MHz phase 0 for the console pipeline, and LCD_DCLK driven by
// ODDR from a 180-degree tap -- the panel latches on the opposite edge, so
// every RGB/DE/HS/VS bit gets a half pixel period of setup and hold.
// Feedback is direct CLKFBOUT->CLKFBIN (no BUFG), matching the HDMI top.
module lcd_console_top_xilinx (
    input  wire clk_75mhz,
    input  wire rst_n,

    input  wire        lcd_display_enable,
    input  wire [31:0] lcd_display_bg_color,
    input  wire        lcd_display_text_enable,
    input  wire        lcd_display_text_clear,
    input  wire        lcd_display_text_we,
    input  wire [7:0]  lcd_display_text_word_addr,
    input  wire [31:0] lcd_display_text_wdata,
    input  wire [3:0]  lcd_display_text_wstrb,
    input  wire        lcd_display_attr_we,
    input  wire [6:0]  lcd_display_attr_word_addr,
    input  wire [31:0] lcd_display_attr_wdata,
    input  wire [3:0]  lcd_display_attr_wstrb,
    input  wire        lcd_display_font_we,
    input  wire [8:0]  lcd_display_font_word_addr,
    input  wire [31:0] lcd_display_font_wdata,
    input  wire [3:0]  lcd_display_font_wstrb,

    output wire [7:0] LCD_R,
    output wire [7:0] LCD_G,
    output wire [7:0] LCD_B,
    output wire       LCD_DCLK,
    output wire       LCD_HS,
    output wire       LCD_VS,
    output wire       LCD_DE
);
    wire clkfb_w;
    wire clkfbout_w;
    wire mmcm_locked;
    wire pclk_unbuf;
    wire dclk180_n;
    wire pclk;
    wire dclk180;

    // 75 MHz in, VCO = 75 * 45 / 5 = 675 MHz (legal: 600-1200 for -2 speed)
    // CLKOUT0 = 675 / 72 = 9.375 MHz (pixel clock)
    // CLKOUT1 = 675 / 72 = 9.375 MHz, 180 degrees (DCLK source)
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(45.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(13.333),
        .CLKOUT0_DIVIDE_F(72.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(72),
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(180.0),
        .DIVCLK_DIVIDE(5),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKOUT0(pclk_unbuf),
        .CLKOUT1(dclk180_n),
        .CLKOUT2(),
        .CLKOUT3(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clkfbout_w),
        .CLKFBIN(clkfb_w),
        .LOCKED(mmcm_locked),
        .CLKIN1(clk_75mhz),
        .PWRDWN(1'b0),
        .RST(1'b0)
    );

    assign clkfb_w = clkfbout_w;

    BUFG bufg_pclk (
        .I(pclk_unbuf),
        .O(pclk)
    );

    BUFG bufg_dclk (
        .I(dclk180_n),
        .O(dclk180)
    );

    // Release the pixel-domain reset only after the MMCM locks; 3-stage
    // synchronizer mirrors hdmi_test_pattern_top_xilinx.
    reg [2:0] rst_video_sync;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            rst_video_sync <= 3'b000;
        end else if (!mmcm_locked) begin
            rst_video_sync <= 3'b000;
        end else begin
            rst_video_sync <= {rst_video_sync[1:0], 1'b1};
        end
    end
    wire rst_video_n = rst_video_sync[2];

    wire [7:0] lcd_r;
    wire [7:0] lcd_g;
    wire [7:0] lcd_b;
    wire lcd_de;
    wire lcd_hs;
    wire lcd_vs;

    lcd_text_console_core u_core (
        .sys_clk(clk_75mhz),
        .pix_clk(pclk),
        .rst_n(rst_n),
        .pix_rst_n(rst_video_n),
        .enable(lcd_display_enable),
        .text_enable(lcd_display_text_enable),
        .text_clear(lcd_display_text_clear),
        .mode(2'd3),
        .bg_color(lcd_display_bg_color),
        .text_we(lcd_display_text_we),
        .text_word_addr(lcd_display_text_word_addr),
        .text_wdata(lcd_display_text_wdata),
        .text_wstrb(lcd_display_text_wstrb),
        .attr_we(lcd_display_attr_we),
        .attr_word_addr(lcd_display_attr_word_addr),
        .attr_wdata(lcd_display_attr_wdata),
        .attr_wstrb(lcd_display_attr_wstrb),
        .font_we(lcd_display_font_we),
        .font_word_addr(lcd_display_font_word_addr),
        .font_wdata(lcd_display_font_wdata),
        .font_wstrb(lcd_display_font_wstrb),
        .lcd_r(lcd_r),
        .lcd_g(lcd_g),
        .lcd_b(lcd_b),
        .lcd_de(lcd_de),
        .lcd_hs(lcd_hs),
        .lcd_vs(lcd_vs),
        .h_count(),
        .v_count(),
        .frame_done()
    );

    assign LCD_R = lcd_r;
    assign LCD_G = lcd_g;
    assign LCD_B = lcd_b;
    assign LCD_HS = lcd_hs;
    assign LCD_VS = lcd_vs;
    assign LCD_DE = lcd_de;

    // DCLK: constant-1 on the rising (180-degree) edge, constant-0 on the
    // falling edge -> a clean 9.375 MHz square wave half a period out of
    // phase with the pixel-clock edge that updates the RGB/DE/HS/VS regs.
    ODDR #(
        .DDR_CLK_EDGE("OPPOSITE_EDGE"),
        .SRTYPE("SYNC")
    ) u_dclk_oddr (
        .Q(LCD_DCLK),
        .C(dclk180),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(1'b0),
        .S(1'b0)
    );
endmodule
