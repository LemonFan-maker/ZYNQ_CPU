module video_timing (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic [1:0]  mode,

    output logic [15:0] h_count,
    output logic [15:0] v_count,
    output logic [15:0] active_width,
    output logic [15:0] active_height,
    output logic        hsync,
    output logic        vsync,
    output logic        active,
    output logic        frame_start,
    output logic        frame_done
);
    logic [11:0] h_ctr;
    logic [11:0] v_ctr;
    logic [11:0] h_active_last;
    logic [11:0] v_active_last;
    logic [11:0] h_sync_start;
    logic [11:0] h_sync_end;
    logic [11:0] v_sync_start;
    logic [11:0] v_sync_end;
    logic [11:0] h_total_last;
    logic [11:0] v_total_last;
    logic        h_sync_pos;
    logic        v_sync_pos;

    logic        at_line_end;
    logic        at_frame_end;
    logic        hsync_raw;
    logic        vsync_raw;

    always_comb begin
        unique case (mode)
            2'd1: begin
                h_active_last = 12'd1279;
                v_active_last = 12'd719;
                h_sync_start = 12'd1390;
                h_sync_end = 12'd1429;
                v_sync_start = 12'd725;
                v_sync_end = 12'd729;
                h_total_last = 12'd1649;
                v_total_last = 12'd749;
                h_sync_pos = 1'b1;
                v_sync_pos = 1'b1;
            end
            2'd2: begin
                h_active_last = 12'd1919;
                v_active_last = 12'd1079;
                h_sync_start = 12'd1928;
                h_sync_end = 12'd1959;
                v_sync_start = 12'd1083;
                v_sync_end = 12'd1087;
                h_total_last = 12'd1999;
                v_total_last = 12'd1110;
                h_sync_pos = 1'b1;
                v_sync_pos = 1'b0;
            end
            default: begin
                h_active_last = 12'd639;
                v_active_last = 12'd479;
                h_sync_start = 12'd656;
                h_sync_end = 12'd751;
                v_sync_start = 12'd490;
                v_sync_end = 12'd491;
                h_total_last = 12'd799;
                v_total_last = 12'd524;
                h_sync_pos = 1'b0;
                v_sync_pos = 1'b0;
            end
        endcase
    end

    assign h_count = {4'd0, h_ctr};
    assign v_count = {4'd0, v_ctr};
    assign at_line_end = h_ctr == h_total_last;
    assign at_frame_end = at_line_end && v_ctr == v_total_last;
    assign active = enable && h_ctr <= h_active_last && v_ctr <= v_active_last;
    assign active_width = {4'd0, h_active_last} + 16'd1;
    assign active_height = {4'd0, v_active_last} + 16'd1;
    assign hsync_raw = h_ctr >= h_sync_start && h_ctr <= h_sync_end;
    assign vsync_raw = v_ctr >= v_sync_start && v_ctr <= v_sync_end;
    assign hsync = h_sync_pos ? hsync_raw : !hsync_raw;
    assign vsync = v_sync_pos ? vsync_raw : !vsync_raw;
    assign frame_start = enable && h_ctr == 12'd0 && v_ctr == 12'd0;
    assign frame_done = enable && at_frame_end;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_ctr <= 12'd0;
            v_ctr <= 12'd0;
        end else if (!enable) begin
            h_ctr <= 12'd0;
            v_ctr <= 12'd0;
        end else if (at_line_end) begin
            h_ctr <= 12'd0;
            v_ctr <= at_frame_end ? 12'd0 : v_ctr + 12'd1;
        end else begin
            h_ctr <= h_ctr + 12'd1;
        end
    end
endmodule
