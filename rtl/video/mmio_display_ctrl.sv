module mmio_display_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        valid,
    input  logic        we,
    input  logic [3:0]  wstrb,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic        ready,
    output logic [31:0] rdata,

    input  logic        hpd,
    input  logic        mode_locked,
    input  logic        frame_done_i,
    input  logic [15:0] scan_x,
    input  logic [15:0] scan_y,

    output logic        display_enable,
    output logic        soft_reset,
    output logic        test_pattern_enable,
    output logic [31:0] fb_addr,
    output logic [31:0] fb_stride,
    output logic [15:0] fb_width,
    output logic [15:0] fb_height,
    output logic [1:0]  mode,
    output logic [31:0] bg_color,

    output logic        text_enable,
    output logic        text_clear,
    output logic        text_we,
    output logic [11:0] text_word_addr,
    output logic [31:0] text_wdata,
    output logic [3:0]  text_wstrb,
    output logic        font_we,
    output logic [8:0]  font_word_addr,
    output logic [31:0] font_wdata,
    output logic [3:0]  font_wstrb
);
    localparam logic [31:0] TEXT_BASE = 32'h0000_0400;
    localparam logic [31:0] TEXT_BYTES = 32'd16080;
    localparam logic [31:0] FONT_BASE = 32'h0000_5000;
    localparam logic [31:0] FONT_BYTES = 32'd2048;

    logic underflow_q;
    logic frame_done_q;
    logic [31:0] underflow_count_q;
    logic text_window;
    logic font_window;
    logic [31:0] text_offset;
    logic [31:0] font_offset;

    assign ready = valid;
    assign text_window = addr >= TEXT_BASE && addr < TEXT_BASE + TEXT_BYTES;
    assign font_window = addr >= FONT_BASE && addr < FONT_BASE + FONT_BYTES;
    assign text_offset = addr - TEXT_BASE;
    assign font_offset = addr - FONT_BASE;
    assign soft_reset = valid && we && !text_window && !font_window && addr[7:2] == 6'h00 && wstrb[0] && wdata[1];
    assign text_clear = valid && we && !text_window && !font_window && addr[7:2] == 6'h09 && wstrb[0] && wdata[1];
    assign text_we = valid && we && text_window;
    assign text_word_addr = text_offset[13:2];
    assign text_wdata = wdata;
    assign text_wstrb = wstrb;
    assign font_we = valid && we && font_window;
    assign font_word_addr = font_offset[10:2];
    assign font_wdata = wdata;
    assign font_wstrb = wstrb;

    always_comb begin
        rdata = 32'd0;
        if (!text_window && !font_window) begin
            unique case (addr[7:2])
                6'h00: rdata = {29'd0, test_pattern_enable, 1'b0, display_enable};
                6'h01: rdata = {27'd0, frame_done_q, underflow_q, hpd, mode_locked, display_enable};
                6'h02: rdata = fb_addr;
                6'h03: rdata = fb_stride;
                6'h04: rdata = {fb_height, fb_width};
                6'h05: rdata = {30'd0, mode};
                6'h06: rdata = bg_color;
                6'h07: rdata = underflow_count_q;
                6'h08: rdata = {scan_y, scan_x};
                6'h09: rdata = {31'd0, text_enable};
                default: rdata = 32'd0;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_enable <= 1'b0;
            test_pattern_enable <= 1'b1;
            fb_addr <= 32'hbc00_0000;
            fb_stride <= 32'd7680;
            fb_width <= 16'd1920;
            fb_height <= 16'd1080;
            mode <= 2'd2;
            bg_color <= 32'h0000_0000;
            text_enable <= 1'b1;
            underflow_q <= 1'b0;
            frame_done_q <= 1'b0;
            underflow_count_q <= 32'd0;
        end else begin
            if (frame_done_i) begin
                frame_done_q <= 1'b1;
            end

            if (valid && we && !text_window && !font_window) begin
                unique case (addr[7:2])
                    6'h00: begin
                        if (wstrb[0]) begin
                            display_enable <= wdata[0];
                            if (wdata[1]) begin
                                underflow_q <= 1'b0;
                                frame_done_q <= 1'b0;
                                underflow_count_q <= 32'd0;
                            end
                            test_pattern_enable <= wdata[2];
                        end
                    end
                    6'h01: begin
                        if (wstrb[0]) begin
                            if (wdata[3]) underflow_q <= 1'b0;
                            if (wdata[4]) frame_done_q <= 1'b0;
                        end
                    end
                    6'h02: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) fb_addr[i * 8 +: 8] <= wdata[i * 8 +: 8];
                        end
                    end
                    6'h03: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) fb_stride[i * 8 +: 8] <= wdata[i * 8 +: 8];
                        end
                    end
                    6'h04: begin
                        if (wstrb[0]) fb_width[7:0] <= wdata[7:0];
                        if (wstrb[1]) fb_width[15:8] <= wdata[15:8];
                        if (wstrb[2]) fb_height[7:0] <= wdata[23:16];
                        if (wstrb[3]) fb_height[15:8] <= wdata[31:24];
                    end
                    6'h05: begin
                        if (wstrb[0]) begin
                            mode <= wdata[1:0];
                            unique case (wdata[1:0])
                                2'd1: begin
                                    fb_width <= 16'd1280;
                                    fb_height <= 16'd720;
                                    fb_stride <= 32'd5120;
                                end
                                2'd2: begin
                                    fb_width <= 16'd1920;
                                    fb_height <= 16'd1080;
                                    fb_stride <= 32'd7680;
                                end
                                default: begin
                                    fb_width <= 16'd640;
                                    fb_height <= 16'd480;
                                    fb_stride <= 32'd2560;
                                end
                            endcase
                        end
                    end
                    6'h06: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) bg_color[i * 8 +: 8] <= wdata[i * 8 +: 8];
                        end
                    end
                    6'h07: begin
                        if (wstrb != 4'd0) begin
                            underflow_q <= 1'b0;
                            underflow_count_q <= 32'd0;
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
