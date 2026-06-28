module hdmi_test_pattern_core (
    input  logic       pix_clk,
    input  logic       rst_n,
    input  logic       enable,
    input  logic [1:0] mode,
    input  logic [31:0] bg_color,

    output logic [9:0] tmds_red,
    output logic [9:0] tmds_green,
    output logic [9:0] tmds_blue,
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
    logic [7:0]  red;
    logic [7:0]  green;
    logic [7:0]  blue;

    video_timing u_timing (
        .clk(pix_clk),
        .rst_n(rst_n),
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

    hdmi_test_pattern u_pattern (
        .x(h_count),
        .y(v_count),
        .width(width),
        .height(height),
        .active(active),
        .bg_color(bg_color),
        .red(red),
        .green(green),
        .blue(blue)
    );

    tmds_encoder u_red (
        .clk(pix_clk),
        .rst_n(rst_n),
        .data(red),
        .control(2'b00),
        .de(active),
        .encoded(tmds_red)
    );

    tmds_encoder u_green (
        .clk(pix_clk),
        .rst_n(rst_n),
        .data(green),
        .control(2'b00),
        .de(active),
        .encoded(tmds_green)
    );

    tmds_encoder u_blue (
        .clk(pix_clk),
        .rst_n(rst_n),
        .data(blue),
        .control({vsync, hsync}),
        .de(active),
        .encoded(tmds_blue)
    );
endmodule
