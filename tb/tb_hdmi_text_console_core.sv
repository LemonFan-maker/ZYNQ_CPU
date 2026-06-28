module tb_hdmi_text_console_core;
    logic sys_clk;
    logic pix_clk;
    logic rst_n;
    logic pix_rst_n;
    logic enable;
    logic test_pattern_enable;
    logic text_enable;
    logic text_clear;
    logic [1:0] mode;
    logic [31:0] bg_color;
    logic text_we;
    logic [11:0] text_word_addr;
    logic [31:0] text_wdata;
    logic [3:0] text_wstrb;
    logic attr_we;
    logic [10:0] attr_word_addr;
    logic [31:0] attr_wdata;
    logic [3:0] attr_wstrb;
    logic font_we;
    logic [8:0] font_word_addr;
    logic [31:0] font_wdata;
    logic [3:0] font_wstrb;
    logic [9:0] tmds_red;
    logic [9:0] tmds_green;
    logic [9:0] tmds_blue;
    logic [15:0] h_count;
    logic [15:0] v_count;
    logic frame_done;

    initial sys_clk = 1'b0;
    always #5 sys_clk = ~sys_clk;

    initial pix_clk = 1'b0;
    always #20 pix_clk = ~pix_clk;

    hdmi_text_console_core u_core (
        .sys_clk(sys_clk),
        .pix_clk(pix_clk),
        .rst_n(rst_n),
        .pix_rst_n(pix_rst_n),
        .enable(enable),
        .test_pattern_enable(test_pattern_enable),
        .text_enable(text_enable),
        .text_clear(text_clear),
        .mode(mode),
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

    initial begin
        rst_n = 1'b0;
        pix_rst_n = 1'b0;
        enable = 1'b1;
        test_pattern_enable = 1'b0;
        text_enable = 1'b1;
        text_clear = 1'b0;
        mode = 2'd0;
        bg_color = 32'd0;
        text_we = 1'b0;
        text_word_addr = 12'd0;
        text_wdata = 32'd0;
        text_wstrb = 4'd0;
        attr_we = 1'b0;
        attr_word_addr = 11'd0;
        attr_wdata = 32'd0;
        attr_wstrb = 4'd0;
        font_we = 1'b0;
        font_word_addr = 9'd0;
        font_wdata = 32'd0;
        font_wstrb = 4'd0;

        repeat (4) @(posedge sys_clk);
        rst_n = 1'b1;
        pix_rst_n = 1'b1;
        @(negedge sys_clk);

        if (u_core.clear_active !== 1'b1) begin
            $fatal(1, "expected text clear to be active after reset");
        end

        font_we = 1'b1;
        font_word_addr = 9'd180;
        font_wdata = 32'h5a5a_a55a;
        font_wstrb = 4'hf;
        @(negedge sys_clk);
        font_we = 1'b0;
        font_wstrb = 4'd0;

        repeat (4) @(posedge sys_clk);
        if (u_core.u_font_ram.mem[180] !== 32'h5a5a_a55a) begin
            $fatal(1, "font write was lost while text clear was active");
        end

        repeat (4500) @(posedge sys_clk);
        @(negedge sys_clk);
        text_we = 1'b1;
        text_word_addr = 10'd0;
        text_wdata = 32'h2020_2041;
        text_wstrb = 4'hf;
        attr_we = 1'b1;
        attr_word_addr = 11'd0;
        attr_wdata = 32'h7777_7779;
        attr_wstrb = 4'hf;
        font_we = 1'b1;
        font_word_addr = 9'd260;
        font_wdata = 32'hffff_ffff;
        font_wstrb = 4'hf;
        @(negedge sys_clk);
        text_we = 1'b0;
        text_wstrb = 4'd0;
        attr_we = 1'b0;
        attr_wstrb = 4'd0;
        font_we = 1'b0;
        font_wstrb = 4'd0;

        repeat (2) @(posedge sys_clk);
        if (u_core.u_text_ram.mem[0] !== 32'h2020_2041) begin
            $fatal(1, "text write did not update text memory");
        end
        if (u_core.u_attr_ram.mem[0] !== 32'h7777_7779) begin
            $fatal(1, "attr write did not update attr memory");
        end
        if (u_core.u_font_ram.mem[260] !== 32'hffff_ffff) begin
            $fatal(1, "glyph write did not update font memory");
        end

        begin
            int seen_text_pixel;

            seen_text_pixel = 0;
            for (int i = 0; i < 800 * 525 * 2; i++) begin
                @(posedge pix_clk);
                if (u_core.text_pixel === 1'b1) begin
                    seen_text_pixel = 1;
                end
            end
            if (seen_text_pixel == 0) begin
                $fatal(1, "text overlay did not produce a visible pixel");
            end
        end

        $display("PASS");
        $finish;
    end
endmodule
