module tb_mmio_display_ctrl;
    logic clk;
    logic rst_n;
    logic valid;
    logic we;
    logic [3:0] wstrb;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic ready;
    logic [31:0] rdata;
    logic display_enable;
    logic soft_reset;
    logic test_pattern_enable;
    logic [31:0] fb_addr;
    logic [31:0] fb_stride;
    logic [15:0] fb_width;
    logic [15:0] fb_height;
    logic [1:0] mode;
    logic [31:0] bg_color;
    logic text_enable;
    logic text_clear;
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    mmio_display_ctrl u_display (
        .clk(clk),
        .rst_n(rst_n),
        .valid(valid),
        .we(we),
        .wstrb(wstrb),
        .addr(addr),
        .wdata(wdata),
        .ready(ready),
        .rdata(rdata),
        .hpd(1'b1),
        .mode_locked(1'b1),
        .frame_done_i(1'b0),
        .scan_x(16'd12),
        .scan_y(16'd34),
        .display_enable(display_enable),
        .soft_reset(soft_reset),
        .test_pattern_enable(test_pattern_enable),
        .fb_addr(fb_addr),
        .fb_stride(fb_stride),
        .fb_width(fb_width),
        .fb_height(fb_height),
        .mode(mode),
        .bg_color(bg_color),
        .text_enable(text_enable),
        .text_clear(text_clear),
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
        .font_wstrb(font_wstrb)
    );

    task automatic write_reg(input logic [31:0] a, input logic [31:0] d);
        begin
            @(negedge clk);
            valid = 1'b1;
            we = 1'b1;
            wstrb = 4'hf;
            addr = a;
            wdata = d;
            @(negedge clk);
            valid = 1'b0;
            we = 1'b0;
            wstrb = 4'd0;
            addr = 32'd0;
            wdata = 32'd0;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        if (fb_addr !== 32'hbc00_0000 || fb_stride !== 32'd7680) begin
            $fatal(1, "bad framebuffer defaults");
        end
        if (text_enable !== 1'b1 || test_pattern_enable !== 1'b1) begin
            $fatal(1, "bad display text/test defaults");
        end

        @(negedge clk);
        valid = 1'b1;
        we = 1'b1;
        wstrb = 4'hf;
        addr = 32'h0000_0024;
        wdata = 32'h0000_0003;
        #1;
        if (text_enable !== 1'b1 || text_clear !== 1'b1) begin
            $fatal(1, "text control write did not pulse clear");
        end
        @(negedge clk);
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;
        @(posedge clk);
        if (text_clear !== 1'b0) begin
            $fatal(1, "text_clear should be a one-cycle pulse");
        end

        @(negedge clk);
        valid = 1'b1;
        we = 1'b1;
        wstrb = 4'hf;
        addr = 32'h0000_0400;
        wdata = 32'h4443_4241;
        #1;
        if (text_we !== 1'b1 || text_word_addr !== 10'd0 || text_wdata !== 32'h4443_4241 || text_wstrb !== 4'hf) begin
            $fatal(1, "text window write mismatch at base");
        end
        @(negedge clk);
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;

        @(negedge clk);
        valid = 1'b1;
        we = 1'b1;
        wstrb = 4'hf;
        addr = 32'h0000_0404;
        wdata = 32'h4847_4645;
        #1;
        if (text_we !== 1'b1 || text_word_addr !== 10'd1) begin
            $fatal(1, "text window write mismatch at second word");
        end
        @(negedge clk);
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;

        @(negedge clk);
        valid = 1'b1;
        we = 1'b1;
        wstrb = 4'hf;
        addr = 32'h0000_4400;
        wdata = 32'h7777_7779;
        #1;
        if (attr_we !== 1'b1 || attr_word_addr !== 11'd0 || attr_wdata !== 32'h7777_7779 || attr_wstrb !== 4'hf) begin
            $fatal(1, "attr window write mismatch at base");
        end
        @(negedge clk);
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;

        @(negedge clk);
        valid = 1'b1;
        we = 1'b1;
        wstrb = 4'hf;
        addr = 32'h0000_6400;
        wdata = 32'h0302_0100;
        #1;
        if (font_we !== 1'b1 || font_word_addr !== 9'd0 || font_wdata !== 32'h0302_0100 || font_wstrb !== 4'hf) begin
            $fatal(1, "font window write mismatch at base");
        end
        @(negedge clk);
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;

        @(negedge clk);
        valid = 1'b1;
        we = 1'b1;
        wstrb = 4'hf;
        addr = 32'h0000_6424;
        wdata = 32'h0000_0002;
        #1;
        if (font_we !== 1'b1 || font_word_addr !== 9'd9 || text_clear !== 1'b0 || soft_reset !== 1'b0) begin
            $fatal(1, "font window aliases display control pulse");
        end
        @(negedge clk);
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;

        write_reg(32'h0000_0014, 32'd1);
        if (mode !== 2'd1 || fb_width !== 16'd1280 || fb_height !== 16'd720 || fb_stride !== 32'd5120) begin
            $fatal(1, "mode 1 defaults mismatch");
        end

        @(negedge clk);
        valid = 1'b1;
        we = 1'b1;
        wstrb = 4'hf;
        addr = 32'h0000_42cc;
        wdata = 32'h4c4b_4a49;
        #1;
        if (text_we !== 1'b1 || text_word_addr !== 12'd4019) begin
            $fatal(1, "text window write mismatch at 1080p last word");
        end
        @(negedge clk);
        valid = 1'b0;
        we = 1'b0;
        wstrb = 4'd0;
        addr = 32'd0;
        wdata = 32'd0;

        $display("PASS");
        $finish;
    end
endmodule
