// TB for the LCD console path (core-level).
//
// After reset the clear scan fills text RAM with spaces and attr RAM with 0x7
// nibbles. Upload a glyph + one cell, let the console stream, and measure
// signals over exactly ONE frame -- the counting window opens at the first
// frame_done and closes at the second (the output regs trail the timing
// counters by 4 pixels, and DE/HS are blank at the frame wrap, so the window
// contains exactly one frame's worth of outputs).
//
// Expected (measured against h_count/v_count, i.e. counter coords + 4):
//   DE 480*272 px, first DE at (4,0)
//   HS low-active: 304 pulses of 10 px at h in [504,514)
//   VS low-active: 1 falling edge, 2120 px low, window v in [280,285)
//   Cell (0,0) 'A' attr 15 renders white pixels at h in [8,12), v in [0,4)
`timescale 1ns/1ps
module tb_lcd_console;
    logic sys_clk;
    logic pix_clk;
    initial sys_clk = 1'b0;
    always #6.667 sys_clk = ~sys_clk;   // 75 MHz
    initial pix_clk = 1'b0;
    always #53.333 pix_clk = ~pix_clk;  // 9.375 MHz

    integer error_count;
    initial error_count = 0;

    function void check(input integer cond, input string msg);
        if (cond) $display("TB_LCD_CONSOLE: PASS %s", msg);
        else begin
            $display("TB_LCD_CONSOLE: FAIL %s", msg);
            error_count = error_count + 1;
        end
    endfunction

    logic rst_n, pix_rst_n;
    logic enable, text_enable, text_clear;

    // ======================================================================
    // Stage 2: zx32_soc host-bus path to display2 (0x1009_0000)
    // ======================================================================
    logic        soc_host_valid;
    logic        soc_host_we;
    logic [3:0]  soc_host_wstrb;
    logic [31:0] soc_host_addr;
    logic [31:0] soc_host_wdata;
    logic        soc_host_ready;
    logic [31:0] soc_host_rdata;
    logic        soc_uart_tx;

    logic        soc_lcd_text_we;
    logic [7:0]  soc_lcd_text_word_addr;
    logic [31:0] soc_lcd_text_wdata;
    logic [3:0]  soc_lcd_text_wstrb;
    logic        soc_lcd_font_we;
    logic [8:0]  soc_lcd_font_word_addr;
    logic [31:0] soc_lcd_font_wdata;
    logic [3:0]  soc_lcd_font_wstrb;
    logic        soc_lcd_attr_we;
    logic [6:0]  soc_lcd_attr_word_addr;
    logic [31:0] soc_lcd_attr_wdata;
    logic [3:0]  soc_lcd_attr_wstrb;
    logic        soc_lcd_enable;
    logic [31:0] soc_lcd_bg;
    logic        soc_lcd_text_en;
    logic        soc_lcd_text_clear;

    logic        saw_soc_text_we;
    logic [7:0]  soc_text_word_addr_q;
    logic [31:0] soc_text_wdata_q;
    always @(posedge sys_clk) begin
        if (rst_n && soc_lcd_text_we) begin
            saw_soc_text_we = 1'b1;
            soc_text_word_addr_q = soc_lcd_text_word_addr;
            soc_text_wdata_q = soc_lcd_text_wdata;
        end
    end
    zx32_soc #(.BRAM_WORDS(1024), .CLK_HZ(75_000_000)) u_soc (
        .clk(sys_clk),
        .rst_n(rst_n),
        .uart_tx(soc_uart_tx),
        .host_valid(soc_host_valid),
        .host_we(soc_host_we),
        .host_wstrb(soc_host_wstrb),
        .host_addr(soc_host_addr),
        .host_wdata(soc_host_wdata),
        .host_ready(soc_host_ready),
        .host_rdata(soc_host_rdata),
        .lcd_display_text_we_o(soc_lcd_text_we),
        .lcd_display_text_word_addr_o(soc_lcd_text_word_addr),
        .lcd_display_text_wdata_o(soc_lcd_text_wdata),
        .lcd_display_text_wstrb_o(soc_lcd_text_wstrb),
        .lcd_display_font_we_o(soc_lcd_font_we),
        .lcd_display_font_word_addr_o(soc_lcd_font_word_addr),
        .lcd_display_font_wdata_o(soc_lcd_font_wdata),
        .lcd_display_font_wstrb_o(soc_lcd_font_wstrb),
        .lcd_display_attr_we_o(soc_lcd_attr_we),
        .lcd_display_attr_word_addr_o(soc_lcd_attr_word_addr),
        .lcd_display_attr_wdata_o(soc_lcd_attr_wdata),
        .lcd_display_attr_wstrb_o(soc_lcd_attr_wstrb),
        .lcd_display_enable_o(soc_lcd_enable),
        .lcd_display_bg_color_o(soc_lcd_bg),
        .lcd_display_text_enable_o(soc_lcd_text_en),
        .lcd_display_text_clear_o(soc_lcd_text_clear)
    );

    logic [31:0] bg_color;
    logic text_we, attr_we, font_we;
    logic [7:0] text_word_addr;
    logic [6:0] attr_word_addr;
    logic [8:0] font_word_addr;
    logic [31:0] text_wdata, attr_wdata, font_wdata;
    logic [3:0] text_wstrb, attr_wstrb, font_wstrb;
    logic [7:0] lcd_r, lcd_g, lcd_b;
    logic lcd_de, lcd_hs, lcd_vs;
    logic [15:0] h_count, v_count;
    logic frame_done;

    lcd_text_console_core u_core (
        .sys_clk(sys_clk),
        .pix_clk(pix_clk),
        .rst_n(rst_n),
        .pix_rst_n(pix_rst_n),
        .enable(enable),
        .text_enable(text_enable),
        .text_clear(text_clear),
        .mode(2'd3),
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
        .lcd_r(lcd_r),
        .lcd_g(lcd_g),
        .lcd_b(lcd_b),
        .lcd_de(lcd_de),
        .lcd_hs(lcd_hs),
        .lcd_vs(lcd_vs),
        .h_count(h_count),
        .v_count(v_count),
        .frame_done(frame_done)
    );

    task automatic wr_text(input logic [7:0] wa, input logic [31:0] wd);
        begin
            @(negedge sys_clk);
            text_we = 1'b1; text_word_addr = wa; text_wdata = wd; text_wstrb = 4'hf;
            @(negedge sys_clk);
            text_we = 1'b0; text_wstrb = 4'h0;
        end
    endtask

    task automatic wr_attr(input logic [6:0] wa, input logic [31:0] wd);
        begin
            @(negedge sys_clk);
            attr_we = 1'b1; attr_word_addr = wa; attr_wdata = wd; attr_wstrb = 4'hf;
            @(negedge sys_clk);
            attr_we = 1'b0; attr_wstrb = 4'h0;
        end
    endtask

    task automatic wr_font(input logic [8:0] wa, input logic [31:0] wd);
        begin
            @(negedge sys_clk);
            font_we = 1'b1; font_word_addr = wa; font_wdata = wd; font_wstrb = 4'hf;
            @(negedge sys_clk);
            font_we = 1'b0; font_wstrb = 4'h0;
        end
    endtask

    // Pixel-domain frame monitors. frame_open brackets exactly one frame
    // (opens at 1st frame_done, closes at 2nd).
    integer de_count, hs_pulses, hs_low_total, vs_edges, vs_low_total;
    integer frames_seen;
    logic frame_open;
    logic hs_d, vs_d;
    integer first_de_x, first_de_y;
    logic got_first_de;
    logic saw_white;

    always @(posedge pix_clk) begin
        hs_d <= lcd_hs;
        vs_d <= lcd_vs;
    end

    always @(posedge pix_clk) begin
        if (pix_rst_n && enable) begin
            if (frame_open) begin
                if (lcd_de) begin
                    de_count = de_count + 1;
                    if (!got_first_de) begin
                        got_first_de = 1'b1;
                        first_de_x = h_count;
                        first_de_y = v_count;
                    end
                end
                if (!lcd_hs) begin
                    hs_low_total = hs_low_total + 1;
                    if (hs_d) hs_pulses = hs_pulses + 1;
                    if (!(h_count >= 504 && h_count < 514)) begin
                        $display("TB_LCD_CONSOLE: FAIL HS low at h=%0d (window [504,514))", h_count);
                        error_count = error_count + 1;
                    end
                end
                if (!lcd_vs) begin
                    vs_low_total = vs_low_total + 1;
                    if (vs_d) vs_edges = vs_edges + 1;
                    if (!(v_count >= 280 && v_count < 285)) begin
                        $display("TB_LCD_CONSOLE: FAIL VS low at v=%0d (window [280,285))", v_count);
                        error_count = error_count + 1;
                    end
                end
                // Cell (0,0) 'A' rows 0..3 bit pattern 0x0F -> white pixels
                // at glyph columns 4..7 => counter coords h in [8,12), v in [0,4).
                if (lcd_de && h_count >= 8 && h_count < 12 && v_count < 4 &&
                    lcd_r == 8'hff && lcd_g == 8'hff && lcd_b == 8'hff) begin
                    saw_white = 1'b1;
                end
            end
            // bookkeeping AFTER counting: the frame_done tick itself only
            // carries trailing blank (no DE/HS activity), so it is safe to
            // open/close the window here.
            if (frame_done) begin
                frames_seen = frames_seen + 1;
                if (frames_seen == 1) frame_open = 1'b1;
                else frame_open = 1'b0;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        pix_rst_n = 1'b0;
        enable = 1'b0;
        text_enable = 1'b1;
        text_clear = 1'b0;
        bg_color = 32'h0000_0000;
        text_we = 1'b0; attr_we = 1'b0; font_we = 1'b0;
        text_word_addr = 8'd0; attr_word_addr = 7'd0; font_word_addr = 9'd0;
        text_wdata = 32'd0; attr_wdata = 32'd0; font_wdata = 32'd0;
        text_wstrb = 4'd0; attr_wstrb = 4'd0; font_wstrb = 4'd0;
        de_count = 0; hs_pulses = 0; hs_low_total = 0;
        vs_edges = 0; vs_low_total = 0;
        frames_seen = 0; frame_open = 1'b0;
        got_first_de = 1'b0; saw_white = 1'b0;
        first_de_x = -1; first_de_y = -1;

        repeat (10) @(negedge sys_clk);
        rst_n = 1'b1;
        pix_rst_n = 1'b1;
        // clear scan: 256 words at 75 MHz
        repeat (400) @(negedge sys_clk);

        check(u_core.clear_active == 1'b0, "clear scan finished");
        check(u_core.u_text_ram.mem[0] == 32'h2020_2020, "text RAM cleared to spaces");
        check(u_core.u_attr_ram.mem[0] == 32'h7777_7777, "attr RAM cleared to 0x7");
        check(u_core.u_attr_ram.mem[127] == 32'h7777_7777, "attr RAM word 127 covered (scan 0..255)");

        // font for 'A' (0x41): byte addr {0x41,0..3} -> word addr 9'h104
        wr_font(9'h104, 32'h0F0F_0F0F);
        // cell(0,0) = 'A', attr nibble 15 = white
        wr_text(8'd0, 32'h2020_2041);
        wr_attr(7'd0, 32'h0000_000F);

        enable = 1'b1;
        // two full frames: window opens at end of frame 1, closes at end of
        // frame 2; +100 ticks margin for the trailing pipeline
        repeat (2 * 530 * 304 + 100) @(negedge pix_clk);

        check(frames_seen == 2, $sformatf("frame_done pulses %0d == 2", frames_seen));
        check(de_count == 480 * 272, $sformatf("DE pixels %0d == 130560", de_count));
        check(hs_pulses == 304, $sformatf("HS pulses %0d == 304", hs_pulses));
        check(hs_low_total == 304 * 10, $sformatf("HS low total %0d == 3040", hs_low_total));
        check(vs_edges == 1, $sformatf("VS falling edges %0d == 1 per frame", vs_edges));
        check(vs_low_total == 4 * 530, $sformatf("VS low pixels %0d == 2120", vs_low_total));
        check(got_first_de, "DE active seen");
        check(first_de_x == 4 && first_de_y == 0,
              $sformatf("first DE at (%0d,%0d) == (4,0)", first_de_x, first_de_y));
        check(saw_white, "white glyph pixel rendered at cell (0,0)");

        // ------------------------------------------------------------------
        // Stage 2: PS-style host write through zx32_soc to display2. The SoC
        // routes the write to its lcd_display_*_o ports (the console RAMs
        // live in the board top, not in the SoC), so we assert the ports
        // fire with the right address/data and strobes.
        // ------------------------------------------------------------------
        soc_host_valid = 1'b0;
        soc_host_we = 1'b0;
        soc_host_wstrb = 4'd0;
        soc_host_addr = 32'd0;
        soc_host_wdata = 32'd0;
        saw_soc_text_we = 1'b0;

        // text word 0 at 0x1009_0400 -> cells " Z " (0x5A in cell 0)
        @(negedge sys_clk);
        soc_host_addr = 32'h1009_0400;
        soc_host_wdata = 32'h2020_205A;
        soc_host_wstrb = 4'hf;
        soc_host_we = 1'b1;
        soc_host_valid = 1'b1;
        do begin
            @(posedge sys_clk);
        end while (soc_host_ready !== 1'b1);
        @(negedge sys_clk);
        soc_host_valid = 1'b0;
        soc_host_we = 1'b0;
        soc_host_wstrb = 4'd0;

        repeat (2) @(negedge sys_clk);
        check(saw_soc_text_we, "display2 text write pulsed on lcd_display_text_we_o");
        check(soc_text_word_addr_q == 8'd0, "text word addr decoded as 0 (0x400/4)");
        check(soc_text_wdata_q == 32'h2020_205A, "text wdata passed through");
        check(soc_lcd_text_wstrb == 4'hf, "text wstrb passed through");

        // STATUS readback: bit0 = display_enable (0, never enabled)
        @(negedge sys_clk);
        soc_host_addr = 32'h1009_0004;
        soc_host_we = 1'b0;
        soc_host_wstrb = 4'd0;
        soc_host_valid = 1'b1;
        do begin
            @(posedge sys_clk);
        end while (soc_host_ready !== 1'b1);
        #1;
        check(soc_host_rdata[0] == 1'b0, "display2 STATUS display_enable reads 0");
        @(negedge sys_clk);
        soc_host_valid = 1'b0;

        $display("TB_LCD_CONSOLE: stage1 done, errors=%0d", error_count);
        $finish;
    end
endmodule
