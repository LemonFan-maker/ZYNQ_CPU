module tb_video_timing;
    logic clk;
    logic rst_n;
    logic enable;
    logic [1:0] mode;
    logic [15:0] h_count;
    logic [15:0] v_count;
    logic [15:0] active_width;
    logic [15:0] active_height;
    logic hsync;
    logic vsync;
    logic active;
    logic frame_start;
    logic frame_done;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    video_timing u_timing (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .mode(mode),
        .h_count(h_count),
        .v_count(v_count),
        .active_width(active_width),
        .active_height(active_height),
        .hsync(hsync),
        .vsync(vsync),
        .active(active),
        .frame_start(frame_start),
        .frame_done(frame_done)
    );

    task automatic expect_mode(
        input logic [1:0] m,
        input logic [15:0] width,
        input logic [15:0] height,
        input int h_total,
        input int v_total
    );
        int cycles;
        begin
            mode = m;
            enable = 1'b0;
            repeat (2) @(posedge clk);
            enable = 1'b1;
            @(posedge clk);

            if (active_width !== width || active_height !== height) begin
                $fatal(1, "mode %0d size mismatch: %0d x %0d", m, active_width, active_height);
            end

            cycles = 0;
            while (!frame_done && cycles < h_total * v_total + 4) begin
                @(posedge clk);
                cycles++;
            end
            if (!frame_done) begin
                $fatal(1, "mode %0d did not finish a frame", m);
            end
            if (cycles != h_total * v_total - 2) begin
                $fatal(1, "mode %0d frame cycles mismatch: got %0d expected %0d",
                       m, cycles, h_total * v_total - 2);
            end
        end
    endtask

    initial begin
        rst_n = 1'b0;
        enable = 1'b0;
        mode = 2'd0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        expect_mode(2'd0, 16'd640, 16'd480, 800, 525);
        expect_mode(2'd1, 16'd1280, 16'd720, 1650, 750);
        expect_mode(2'd2, 16'd1920, 16'd1080, 2000, 1111);

        $display("PASS");
        $finish;
    end
endmodule
