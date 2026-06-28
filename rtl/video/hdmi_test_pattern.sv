module hdmi_test_pattern (
    input  logic [15:0] x,
    input  logic [15:0] y,
    input  logic [15:0] width,
    input  logic [15:0] height,
    input  logic        active,
    input  logic [31:0] bg_color,

    output logic [7:0] red,
    output logic [7:0] green,
    output logic [7:0] blue
);
    logic [15:0] bar_width;
    logic [2:0]  bar;
    logic        border;
    logic        grid;

    assign bar_width = (width >= 16'd8) ? (width >> 3) : 16'd1;
    assign bar = (x < bar_width) ? 3'd0 :
                 (x < bar_width * 16'd2) ? 3'd1 :
                 (x < bar_width * 16'd3) ? 3'd2 :
                 (x < bar_width * 16'd4) ? 3'd3 :
                 (x < bar_width * 16'd5) ? 3'd4 :
                 (x < bar_width * 16'd6) ? 3'd5 :
                 (x < bar_width * 16'd7) ? 3'd6 : 3'd7;
    assign border = x == 16'd0 || y == 16'd0 || x == width - 16'd1 || y == height - 16'd1;
    assign grid = x[6:0] == 7'd0 || y[6:0] == 7'd0;

    always_comb begin
        red = bg_color[23:16];
        green = bg_color[15:8];
        blue = bg_color[7:0];

        if (active) begin
            unique case (bar)
                3'd0: {red, green, blue} = 24'hffffff;
                3'd1: {red, green, blue} = 24'hffff00;
                3'd2: {red, green, blue} = 24'h00ffff;
                3'd3: {red, green, blue} = 24'h00ff00;
                3'd4: {red, green, blue} = 24'hff00ff;
                3'd5: {red, green, blue} = 24'hff0000;
                3'd6: {red, green, blue} = 24'h0000ff;
                default: {red, green, blue} = 24'h202020;
            endcase
            if (grid) begin
                red = red >> 1;
                green = green >> 1;
                blue = blue >> 1;
            end
            if (border) begin
                {red, green, blue} = 24'hffffff;
            end
        end
    end
endmodule
