module hdmi_text_console_core #(
    parameter int TEXT_COLS = 240,
    parameter int TEXT_ROWS = 67,
    parameter int TEXT_CELLS = TEXT_COLS * TEXT_ROWS,
    parameter int TEXT_WORDS = TEXT_CELLS / 4,
    parameter int ATTR_WORDS = (TEXT_CELLS + 7) / 8,
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
    input  logic        attr_we,
    input  logic [10:0] attr_word_addr,
    input  logic [31:0] attr_wdata,
    input  logic [3:0]  attr_wstrb,
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

    logic        clear_active;
    logic [11:0] clear_index;
    logic [10:0] attr_clear_index;
    logic        text_ram_we;
    logic [11:0] text_ram_waddr;
    logic [31:0] text_ram_wdata;
    logic        attr_ram_we;
    logic [10:0] attr_ram_waddr;
    logic [31:0] attr_ram_wdata;

    logic [13:0] text_read_cell_addr;
    logic [11:0] text_read_word_addr;
    logic [10:0] attr_read_word_addr;
    logic [1:0]  text_read_byte_lane;
    logic [2:0]  attr_nibble_lane;
    logic [1:0]  text_byte_lane;
    logic [2:0]  attr_lane_q;
    logic [31:0] text_word;
    logic [31:0] attr_word;
    logic [7:0]  text_ch;
    logic [3:0]  text_attr;
    logic [2:0]  glyph_x;
    logic [3:0]  glyph_row;
    logic [10:0] font_read_byte_addr;
    logic [8:0]  font_read_word_addr;
    logic [1:0]  font_read_byte_lane;
    logic [1:0]  glyph_byte_lane_q;
    logic [31:0] glyph_word;
    logic [7:0]  glyph_bits;
    logic [7:0]  glyph_bits_q;
    logic [7:0]  text_ch_q;
    logic [7:0]  text_ch_qq;
    logic [3:0]  text_attr_q;
    logic [3:0]  text_attr_qq;
    logic [2:0]  glyph_x_q;
    logic [2:0]  glyph_x_qq;
    logic        text_pixel;
    logic [7:0]  glyph_red;
    logic [7:0]  glyph_green;
    logic [7:0]  glyph_blue;
    logic [7:0]  cell_bg_red;
    logic [7:0]  cell_bg_green;
    logic [7:0]  cell_bg_blue;
    logic        text_active_d;
    logic        text_active_q;
    logic        text_active_qq;
    logic        active_d;
    logic        active_q;
    logic        active_qq;
    logic        hsync_d;
    logic        hsync_q;
    logic        hsync_qq;
    logic        vsync_d;
    logic        vsync_q;
    logic        vsync_qq;
    logic [7:0]  red_d;
    logic [7:0]  red_q;
    logic [7:0]  red_qq;
    logic [7:0]  green_d;
    logic [7:0]  green_q;
    logic [7:0]  green_qq;
    logic [7:0]  blue_d;
    logic [7:0]  blue_q;
    logic [7:0]  blue_qq;
    logic [7:0]  out_red;
    logic [7:0]  out_green;
    logic [7:0]  out_blue;
    logic [7:0]  tmds_red_data;
    logic [7:0]  tmds_green_data;
    logic [7:0]  tmds_blue_data;
    logic [1:0]  tmds_blue_control;
    logic        tmds_de;
    logic        enable_meta;
    logic        enable_pix;
    logic        test_pattern_meta;
    logic        test_pattern_pix;
    logic        text_enable_meta;
    logic        text_enable_pix;
    logic [31:0] bg_color_meta;
    logic [31:0] bg_color_pix;
    logic [15:0] text_x;
    logic [15:0] text_y;
    logic        text_visible;
    logic [6:0]  text_row_index;
    logic [7:0]  text_col_index;
    logic [13:0] text_cell_addr_calc;

    video_timing u_timing (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .enable(enable_pix),
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
        end else if (test_pattern_pix) begin
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
            base_red = bg_color_pix[23:16];
            base_green = bg_color_pix[15:8];
            base_blue = bg_color_pix[7:0];
        end
    end

    assign text_ram_we = clear_active || (text_we && text_word_addr < TEXT_WORDS && text_wstrb != 4'd0);
    assign text_ram_waddr = clear_active ? clear_index : text_word_addr;
    assign text_ram_wdata = clear_active ? 32'h2020_2020 : text_wdata;
    assign attr_clear_index = clear_index[11:1];
    assign attr_ram_we = (clear_active && clear_index[0]) ||
                         (attr_we && attr_word_addr < ATTR_WORDS && attr_wstrb != 4'd0);
    assign attr_ram_waddr = clear_active ? attr_clear_index : attr_word_addr;
    assign attr_ram_wdata = clear_active ? 32'h7777_7777 : attr_wdata;

    always_ff @(posedge sys_clk) begin
        if (!rst_n) begin
            clear_active <= 1'b1;
            clear_index <= 12'd0;
        end else begin
            if (text_clear) begin
                clear_active <= 1'b1;
                clear_index <= 12'd0;
            end else if (clear_active) begin
                if (clear_index == TEXT_WORDS - 1) begin
                    clear_active <= 1'b0;
                end else begin
                    clear_index <= clear_index + 12'd1;
                end
            end
        end
    end

    hdmi_console_ram #(
        .ADDR_WIDTH(12),
        .DATA_WIDTH(32),
        .DEPTH(TEXT_WORDS)
    ) u_text_ram (
        .wr_clk(sys_clk),
        .wr_en(text_ram_we),
        .wr_addr(text_ram_waddr),
        .wr_data(text_ram_wdata),
        .rd_clk(pix_clk),
        .rd_addr(text_read_word_addr),
        .rd_data(text_word)
    );

    hdmi_console_ram #(
        .ADDR_WIDTH(11),
        .DATA_WIDTH(32),
        .DEPTH(ATTR_WORDS)
    ) u_attr_ram (
        .wr_clk(sys_clk),
        .wr_en(attr_ram_we),
        .wr_addr(attr_ram_waddr),
        .wr_data(attr_ram_wdata),
        .rd_clk(pix_clk),
        .rd_addr(attr_read_word_addr),
        .rd_data(attr_word)
    );

    hdmi_console_ram #(
        .ADDR_WIDTH(9),
        .DATA_WIDTH(32),
        .DEPTH(512)
    ) u_font_ram (
        .wr_clk(sys_clk),
        .wr_en(font_we && font_wstrb != 4'd0),
        .wr_addr(font_word_addr),
        .wr_data(font_wdata),
        .rd_clk(pix_clk),
        .rd_addr(font_read_word_addr),
        .rd_data(glyph_word)
    );

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
        attr_read_word_addr = text_read_cell_addr[13:3];
        text_read_byte_lane = text_read_cell_addr[1:0];
        attr_nibble_lane = text_read_cell_addr[2:0];
    end

    always_comb begin
        font_read_byte_addr = {text_ch[6:0], glyph_row};
        font_read_word_addr = font_read_byte_addr[10:2];
        font_read_byte_lane = font_read_byte_addr[1:0];
    end

    always_ff @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            enable_meta <= 1'b0;
            enable_pix <= 1'b0;
            test_pattern_meta <= 1'b0;
            test_pattern_pix <= 1'b0;
            text_enable_meta <= 1'b0;
            text_enable_pix <= 1'b0;
            bg_color_meta <= 32'd0;
            bg_color_pix <= 32'd0;
        end else begin
            enable_meta <= enable;
            enable_pix <= enable_meta;
            test_pattern_meta <= test_pattern_enable;
            test_pattern_pix <= test_pattern_meta;
            text_enable_meta <= text_enable;
            text_enable_pix <= text_enable_meta;
            bg_color_meta <= bg_color;
            bg_color_pix <= bg_color_meta;
        end
    end

    always_ff @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            text_byte_lane <= 2'd0;
            attr_lane_q <= 3'd0;
            glyph_x <= 3'd0;
            glyph_row <= 3'd0;
            glyph_byte_lane_q <= 2'd0;
            glyph_bits_q <= 8'd0;
            text_ch_q <= 8'h20;
            text_ch_qq <= 8'h20;
            text_attr_q <= 4'h7;
            text_attr_qq <= 4'h7;
            glyph_x_q <= 3'd0;
            glyph_x_qq <= 3'd0;
            text_active_d <= 1'b0;
            text_active_q <= 1'b0;
            text_active_qq <= 1'b0;
            active_d <= 1'b0;
            active_q <= 1'b0;
            active_qq <= 1'b0;
            hsync_d <= 1'b0;
            hsync_q <= 1'b0;
            hsync_qq <= 1'b0;
            vsync_d <= 1'b0;
            vsync_q <= 1'b0;
            vsync_qq <= 1'b0;
            red_d <= 8'd0;
            red_q <= 8'd0;
            red_qq <= 8'd0;
            green_d <= 8'd0;
            green_q <= 8'd0;
            green_qq <= 8'd0;
            blue_d <= 8'd0;
            blue_q <= 8'd0;
            blue_qq <= 8'd0;
            tmds_red_data <= 8'd0;
            tmds_green_data <= 8'd0;
            tmds_blue_data <= 8'd0;
            tmds_blue_control <= 2'b00;
            tmds_de <= 1'b0;
        end else begin
            text_byte_lane <= text_read_byte_lane;
            attr_lane_q <= attr_nibble_lane;
            glyph_x <= text_x[2:0];
            glyph_row <= text_y[3:0];
            glyph_byte_lane_q <= font_read_byte_lane;
            glyph_bits_q <= glyph_bits;
            text_ch_q <= text_ch;
            text_ch_qq <= text_ch_q;
            text_attr_q <= text_attr;
            text_attr_qq <= text_attr_q;
            glyph_x_q <= glyph_x;
            glyph_x_qq <= glyph_x_q;
            text_active_d <= text_enable_pix && active && text_visible;
            text_active_q <= text_active_d;
            text_active_qq <= text_active_q;
            active_d <= active;
            active_q <= active_d;
            active_qq <= active_q;
            hsync_d <= hsync;
            hsync_q <= hsync_d;
            hsync_qq <= hsync_q;
            vsync_d <= vsync;
            vsync_q <= vsync_d;
            vsync_qq <= vsync_q;
            red_d <= base_red;
            red_q <= red_d;
            red_qq <= red_q;
            green_d <= base_green;
            green_q <= green_d;
            green_qq <= green_q;
            blue_d <= base_blue;
            blue_q <= blue_d;
            blue_qq <= blue_q;
            tmds_red_data <= out_red;
            tmds_green_data <= out_green;
            tmds_blue_data <= out_blue;
            tmds_blue_control <= {vsync_qq, hsync_qq};
            tmds_de <= active_qq;
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
        unique case (attr_lane_q)
            3'd0: text_attr = attr_word[3:0];
            3'd1: text_attr = attr_word[7:4];
            3'd2: text_attr = attr_word[11:8];
            3'd3: text_attr = attr_word[15:12];
            3'd4: text_attr = attr_word[19:16];
            3'd5: text_attr = attr_word[23:20];
            3'd6: text_attr = attr_word[27:24];
            default: text_attr = attr_word[31:28];
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

    always_comb begin
        unique case (text_attr_qq)
            4'd0: {glyph_red, glyph_green, glyph_blue} = 24'h000000;
            4'd1: {glyph_red, glyph_green, glyph_blue} = 24'haa0000;
            4'd2: {glyph_red, glyph_green, glyph_blue} = 24'h00aa00;
            4'd3: {glyph_red, glyph_green, glyph_blue} = 24'haa5500;
            4'd4: {glyph_red, glyph_green, glyph_blue} = 24'h0000aa;
            4'd5: {glyph_red, glyph_green, glyph_blue} = 24'haa00aa;
            4'd6: {glyph_red, glyph_green, glyph_blue} = 24'h00aaaa;
            4'd8: {glyph_red, glyph_green, glyph_blue} = 24'h555555;
            4'd9: {glyph_red, glyph_green, glyph_blue} = 24'hff5555;
            4'd10: {glyph_red, glyph_green, glyph_blue} = 24'h55ff55;
            4'd11: {glyph_red, glyph_green, glyph_blue} = 24'hffff55;
            4'd12: {glyph_red, glyph_green, glyph_blue} = 24'h5555ff;
            4'd13: {glyph_red, glyph_green, glyph_blue} = 24'hff55ff;
            4'd14: {glyph_red, glyph_green, glyph_blue} = 24'h55ffff;
            4'd15: {glyph_red, glyph_green, glyph_blue} = 24'hffffff;
            default: {glyph_red, glyph_green, glyph_blue} = 24'he0e0e0;
        endcase
    end

    assign cell_bg_red = 8'h00;
    assign cell_bg_green = 8'h00;
    assign cell_bg_blue = 8'h00;

    assign text_pixel = text_active_qq && (text_ch_qq != 8'h20) && glyph_bits_q[3'd7 - glyph_x_qq];
    assign out_red = text_pixel ? glyph_red : (text_active_qq ? cell_bg_red : red_qq);
    assign out_green = text_pixel ? glyph_green : (text_active_qq ? cell_bg_green : green_qq);
    assign out_blue = text_pixel ? glyph_blue : (text_active_qq ? cell_bg_blue : blue_qq);

    tmds_encoder u_red (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .data(tmds_red_data),
        .control(2'b00),
        .de(tmds_de),
        .encoded(tmds_red)
    );

    tmds_encoder u_green (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .data(tmds_green_data),
        .control(2'b00),
        .de(tmds_de),
        .encoded(tmds_green)
    );

    tmds_encoder u_blue (
        .clk(pix_clk),
        .rst_n(pix_rst_n),
        .data(tmds_blue_data),
        .control(tmds_blue_control),
        .de(tmds_de),
        .encoded(tmds_blue)
    );
endmodule
