// Slim MMIO front-end for the 480x272 LCD console (display2 @ 0x1009_0000).
// Register layout mirrors mmio_display_ctrl (the HDMI one) so the PS firmware
// can reuse the same access pattern: 0x00 CONTROL (b0 enable), 0x04 STATUS,
// 0x18 BG, 0x24 TEXT_CTRL (b0 text_en, b1 clear). Framebuffer/test-pattern
// registers are dropped -- the LCD path is text-only.
//
// Windows (byte offsets): TEXT 0x400..0x7FF (255 words), ATTR 0x800..0x9FF
// (128 words), FONT 0xA00..0x11FF (512 words).
module mmio_lcd_display_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        valid,
    input  logic        we,
    input  logic [3:0]  wstrb,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic        ready,
    output logic [31:0] rdata,

    input  logic        frame_done_i,

    output logic        display_enable,
    output logic [31:0] bg_color,
    output logic        text_enable,
    output logic        text_clear,
    output logic        text_we,
    output logic [7:0]  text_word_addr,
    output logic [31:0] text_wdata,
    output logic [3:0]  text_wstrb,
    output logic        attr_we,
    output logic [6:0]  attr_word_addr,
    output logic [31:0] attr_wdata,
    output logic [3:0]  attr_wstrb,
    output logic        font_we,
    output logic [8:0]  font_word_addr,
    output logic [31:0] font_wdata,
    output logic [3:0]  font_wstrb
);
    localparam logic [31:0] TEXT_BASE = 32'h0000_0400;
    localparam logic [31:0] TEXT_BYTES = 32'd1020;
    localparam logic [31:0] ATTR_BASE = 32'h0000_0800;
    localparam logic [31:0] ATTR_BYTES = 32'd512;
    localparam logic [31:0] FONT_BASE = 32'h0000_0A00;
    localparam logic [31:0] FONT_BYTES = 32'd2048;

    logic frame_done_q;
    logic text_window;
    logic attr_window;
    logic font_window;
    logic [31:0] text_offset;
    logic [31:0] attr_offset;
    logic [31:0] font_offset;

    assign ready = valid;
    assign text_window = addr >= TEXT_BASE && addr < TEXT_BASE + TEXT_BYTES;
    assign attr_window = addr >= ATTR_BASE && addr < ATTR_BASE + ATTR_BYTES;
    assign font_window = addr >= FONT_BASE && addr < FONT_BASE + FONT_BYTES;
    assign text_offset = addr - TEXT_BASE;
    assign attr_offset = addr - ATTR_BASE;
    assign font_offset = addr - FONT_BASE;
    assign text_clear = valid && we && !text_window && !attr_window && !font_window &&
                        addr[7:2] == 6'h09 && wstrb[0] && wdata[1];
    assign text_we = valid && we && text_window;
    assign text_word_addr = text_offset[9:2];
    assign text_wdata = wdata;
    assign text_wstrb = wstrb;
    assign attr_we = valid && we && attr_window;
    assign attr_word_addr = attr_offset[8:2];
    assign attr_wdata = wdata;
    assign attr_wstrb = wstrb;
    assign font_we = valid && we && font_window;
    assign font_word_addr = font_offset[10:2];
    assign font_wdata = wdata;
    assign font_wstrb = wstrb;

    always_comb begin
        rdata = 32'd0;
        if (!text_window && !attr_window && !font_window) begin
            unique case (addr[7:2])
                6'h00: rdata = {31'd0, display_enable};
                6'h01: rdata = {30'd0, frame_done_q, display_enable};
                6'h06: rdata = bg_color;
                6'h09: rdata = {31'd0, text_enable};
                default: rdata = 32'd0;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_enable <= 1'b0;
            bg_color <= 32'h0000_0000;
            text_enable <= 1'b1;
            frame_done_q <= 1'b0;
        end else begin
            if (frame_done_i) begin
                frame_done_q <= 1'b1;
            end

            if (valid && we && !text_window && !attr_window && !font_window) begin
                unique case (addr[7:2])
                    6'h00: begin
                        if (wstrb[0]) begin
                            display_enable <= wdata[0];
                            if (wdata[1]) begin
                                frame_done_q <= 1'b0;
                            end
                        end
                    end
                    6'h01: begin
                        if (wstrb[0] && wdata[4]) begin
                            frame_done_q <= 1'b0;
                        end
                    end
                    6'h06: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) bg_color[i * 8 +: 8] <= wdata[i * 8 +: 8];
                        end
                    end
                    6'h09: begin
                        if (wstrb[0]) begin
                            text_enable <= wdata[0];
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
