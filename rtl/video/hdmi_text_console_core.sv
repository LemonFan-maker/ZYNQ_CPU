module hdmi_text_console_core #(
    parameter int TEXT_COLS = 240,
    parameter int TEXT_ROWS = 67,
    parameter int TEXT_CELLS = TEXT_COLS * TEXT_ROWS,
    parameter int TEXT_WORDS = TEXT_CELLS / 4,
    parameter int TEXT_X_OFFSET = 0,
    parameter int TEXT_Y_OFFSET = 0
) (
    input  logic        sys_clk,
    input  logic        pix_clk,
    input  logic        rst_n,
    input  logic        pix_rst_n,
    input  logic        enable,
    input  logic        test_pattern_enable,
    input  logic        text_enable,
    input  logic        text_clear,
    input  logic [1:0]  mode,
    input  logic [31:0] bg_color,

    input  logic        text_we,
    input  logic [11:0] text_word_addr,
    input  logic [31:0] text_wdata,
    input  logic [3:0]  text_wstrb,
    input  logic        font_we,
    input  logic [8:0]  font_word_addr,
    input  logic [31:0] font_wdata,
    input  logic [3:0]  font_wstrb,

    output logic [9:0]  tmds_red,
    output logic [9:0]  tmds_green,
    output logic [9:0]  tmds_blue,
    output logic [15:0] h_count,
    output logic [15:0] v_count,
    output logic        frame_done
);
    logic [15:0] width;
    logic [15:0] height;
    logic        hsync;
    logic        vsync;
    logic        active;
    logic        frame_start;
    logic [7:0]  base_red;
    logic [7:0]  base_green;
    logic [7:0]  base_blue;

    (* ram_style = "block" *) logic [31:0] text_mem [0:TEXT_WORDS-1];
    (* ram_style = "block" *) logic [31:0] font_mem [0:511];
    logic        clear_active;
    logic [11:0] clear_index;

    logic [13:0] text_read_cell_addr;
    logic [11:0] text_read_word_addr;
    logic [1:0]  text_read_byte_lane;
    logic [1:0]  text_byte_lane;
    logic [31:0] text_word;
    logic [7:0]  text_ch;
    logic [2:0]  glyph_x;
    logic [3:0]  glyph_row;
    logic [10:0] font_read_byte_addr;
    logic [8:0]  font_read_word_addr;
    logic [1:0]  font_read_byte_lane;
    logic [1:0]  glyph_byte_lane_q;
    logic [31:0] glyph_word;
    logic [7:0]  glyph_bits;
    logic [7:0]  text_ch_q;
    logic [2:0]  glyph_x_q;
    logic        text_pixel;
    logic        text_active_d;
    logic        text_active_q;
    logic        active_d;
    logic        active_q;
    logic        hsync_d;
    logic        hsync_q;
    logic        vsync_d;
    logic        vsync_q;
    logic [7:0]  red_d;
    logic [7:0]  red_q;
    logic [7:0]  green_d;
    logic [7:0]  green_q;
    logic [7:0]  blue_d;
    logic [7:0]  blue_q;
    logic [7:0]  out_red;
    logic [7:0]  out_green;
    logic [7:0]  out_blue;
    logic [15:0] text_x;
    logic [15:0] text_y;
    logic        text_visible;
    logic [6:0]  text_row_index;
    logic [7:0]  text_col_index;
    logic [13:0] text_cell_addr_calc;

    video_timing u_timing (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .enable(enable),
        .mode(mode),
        .h_count(h_count),
        .v_count(v_count),
        .active_width(width),
        .active_height(height),
        .hsync(hsync),
        .vsync(vsync),
        .active(active),
        .frame_start(frame_start),
        .frame_done(frame_done)
    );

    always_comb begin
        if (!active) begin
            base_red = 8'd0;
            base_green = 8'd0;
            base_blue = 8'd0;
        end else if (test_pattern_enable) begin
            unique case (h_count[10:8])
                3'd0: {base_red, base_green, base_blue} = 24'hffffff;
                3'd1: {base_red, base_green, base_blue} = 24'hff0000;
                3'd2: {base_red, base_green, base_blue} = 24'h00ff00;
                3'd3: {base_red, base_green, base_blue} = 24'h0000ff;
                3'd4: {base_red, base_green, base_blue} = 24'hffff00;
                3'd5: {base_red, base_green, base_blue} = 24'h00ffff;
                3'd6: {base_red, base_green, base_blue} = 24'hff00ff;
                default: {base_red, base_green, base_blue} = 24'h202020;
            endcase
        end else begin
            base_red = bg_color[23:16];
            base_green = bg_color[15:8];
            base_blue = bg_color[7:0];
        end
    end

    always_ff @(posedge sys_clk) begin
        if (!rst_n) begin
            clear_active <= 1'b1;
            clear_index <= 12'd0;
        end else begin
            if (text_clear) begin
                clear_active <= 1'b1;
                clear_index <= 12'd0;
            end else if (clear_active) begin
                text_mem[clear_index] <= 32'h2020_2020;
                if (clear_index == TEXT_WORDS - 1) begin
                    clear_active <= 1'b0;
                end else begin
                    clear_index <= clear_index + 12'd1;
                end
            end else if (text_we && text_word_addr < TEXT_WORDS && text_wstrb != 4'd0) begin
                text_mem[text_word_addr] <= text_wdata;
            end
        end
    end

    always_ff @(posedge sys_clk) begin
        if (font_we && font_wstrb != 4'd0) begin
            font_mem[font_word_addr] <= font_wdata;
        end
    end

    assign text_x = h_count;
    assign text_y = v_count;
    assign text_visible = h_count < (TEXT_COLS[15:0] * 16'd8) &&
                          v_count < (TEXT_ROWS[15:0] * 16'd16);
    assign text_row_index = text_y[10:4];
    assign text_col_index = text_x[10:3];

    generate
        if (TEXT_COLS == 240) begin : gen_text_addr_240
            assign text_cell_addr_calc =
                ({text_row_index, 8'd0} - {text_row_index, 4'd0}) +
                {6'd0, text_col_index};
        end else begin : gen_text_addr_generic
            assign text_cell_addr_calc = (text_row_index * TEXT_COLS) + text_col_index;
        end
    endgenerate

    always_comb begin
        text_read_cell_addr = 14'd0;
        if (text_visible) begin
            text_read_cell_addr = text_cell_addr_calc;
        end
        text_read_word_addr = text_read_cell_addr[13:2];
        text_read_byte_lane = text_read_cell_addr[1:0];
    end

    always_comb begin
        font_read_byte_addr = {text_ch[6:0], glyph_row};
        font_read_word_addr = font_read_byte_addr[10:2];
        font_read_byte_lane = font_read_byte_addr[1:0];
    end

    always_ff @(posedge pix_clk) begin
        text_word <= text_mem[text_read_word_addr];
        glyph_word <= font_mem[font_read_word_addr];
    end

    always_ff @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            text_byte_lane <= 2'd0;
            glyph_x <= 3'd0;
            glyph_row <= 3'd0;
            glyph_byte_lane_q <= 2'd0;
            text_ch_q <= 8'h20;
            glyph_x_q <= 3'd0;
            text_active_d <= 1'b0;
            text_active_q <= 1'b0;
            active_d <= 1'b0;
            active_q <= 1'b0;
            hsync_d <= 1'b0;
            hsync_q <= 1'b0;
            vsync_d <= 1'b0;
            vsync_q <= 1'b0;
            red_d <= 8'd0;
            red_q <= 8'd0;
            green_d <= 8'd0;
            green_q <= 8'd0;
            blue_d <= 8'd0;
            blue_q <= 8'd0;
        end else begin
            text_byte_lane <= text_read_byte_lane;
            glyph_x <= text_x[2:0];
            glyph_row <= text_y[3:0];
            glyph_byte_lane_q <= font_read_byte_lane;
            text_ch_q <= text_ch;
            glyph_x_q <= glyph_x;
            text_active_d <= text_enable && active && text_visible;
            text_active_q <= text_active_d;
            active_d <= active;
            active_q <= active_d;
            hsync_d <= hsync;
            hsync_q <= hsync_d;
            vsync_d <= vsync;
            vsync_q <= vsync_d;
            red_d <= base_red;
            red_q <= red_d;
            green_d <= base_green;
            green_q <= green_d;
            blue_d <= base_blue;
            blue_q <= blue_d;
        end
    end

    always_comb begin
        unique case (text_byte_lane)
            2'd0: text_ch = text_word[7:0];
            2'd1: text_ch = text_word[15:8];
            2'd2: text_ch = text_word[23:16];
            default: text_ch = text_word[31:24];
        endcase
    end

    always_comb begin
        unique case (glyph_byte_lane_q)
            2'd0: glyph_bits = glyph_word[7:0];
            2'd1: glyph_bits = glyph_word[15:8];
            2'd2: glyph_bits = glyph_word[23:16];
            default: glyph_bits = glyph_word[31:24];
        endcase
    end

    assign text_pixel = text_active_q && (text_ch_q != 8'h20) && glyph_bits[3'd7 - glyph_x_q];
    assign out_red = text_pixel ? 8'hf0 : red_q;
    assign out_green = text_pixel ? 8'hf0 : green_q;
    assign out_blue = text_pixel ? 8'hf0 : blue_q;

    tmds_encoder u_red (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .data(out_red),
        .control(2'b00),
        .de(active_q),
        .encoded(tmds_red)
    );

    tmds_encoder u_green (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .data(out_green),
        .control(2'b00),
        .de(active_q),
        .encoded(tmds_green)
    );

    tmds_encoder u_blue (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .data(out_blue),
        .control({vsync_q, hsync_q}),
        .de(active_q),
        .encoded(tmds_blue)
    );
endmodule
