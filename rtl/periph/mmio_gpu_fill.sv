module mmio_gpu_fill (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        valid,
    input  logic        we,
    input  logic [3:0]  wstrb,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic        ready,
    output logic [31:0] rdata,

    output logic        ddr_valid,
    output logic        ddr_we,
    output logic [31:0] ddr_addr,
    output logic [31:0] ddr_wdata,
    input  logic [31:0] ddr_rdata,
    input  logic        ddr_ready
);
    localparam logic [3:0] OP_CLEAR = 4'h1;
    localparam logic [3:0] OP_FILL_RECT = 4'h2;
    localparam logic [3:0] OP_DRAW_LINE = 4'h3;
    localparam logic [3:0] OP_BLIT = 4'h4;
    localparam logic [23:0] DDR_WAIT_TIMEOUT = 24'hff_ffff;
    localparam int CMD_FIFO_DEPTH = 4;
    localparam logic [2:0] CMD_FIFO_DEPTH_U = 3'd4;

    logic [31:0] fb_addr_q;
    logic [31:0] fb_stride_q;
    logic [15:0] fb_width_q;
    logic [15:0] fb_height_q;
    logic [31:0] color_q;
    logic [31:0] active_color_q;
    logic [15:0] rect_x_q;
    logic [15:0] rect_y_q;
    logic [15:0] rect_w_q;
    logic [15:0] rect_h_q;
    logic [31:0] src_addr_q;
    logic [31:0] src_stride_q;
    logic [3:0]  op_q;
    logic        busy_q;
    logic        done_q;
    logic        error_q;
    logic [15:0] cur_x_q;
    logic [15:0] cur_y_q;
    logic [15:0] draw_start_x_q;
    logic [15:0] end_x_q;
    logic [15:0] end_y_q;
    logic [31:0] cur_addr_q;
    logic [31:0] cur_src_addr_q;
    logic [31:0] row_start_addr_q;
    logic [31:0] src_row_start_addr_q;
    logic        addr_init_q;
    logic [15:0] addr_init_rows_q;
    logic        blit_write_phase_q;
    logic [31:0] blit_pixel_q;
    logic [23:0] ddr_wait_q;
    logic [31:0] pixel_count_q;
    logic [31:0] last_ctrl_q;
    logic [15:0] line_dx_q;
    logic [15:0] line_dy_q;
    logic        line_sx_inc_q;
    logic        line_sy_inc_q;
    logic signed [19:0] line_err_q;
    logic [3:0]  fifo_op_q [0:CMD_FIFO_DEPTH-1];
    logic [31:0] fifo_color_q [0:CMD_FIFO_DEPTH-1];
    logic [15:0] fifo_x_q [0:CMD_FIFO_DEPTH-1];
    logic [15:0] fifo_y_q [0:CMD_FIFO_DEPTH-1];
    logic [15:0] fifo_w_q [0:CMD_FIFO_DEPTH-1];
    logic [15:0] fifo_h_q [0:CMD_FIFO_DEPTH-1];
    logic [31:0] fifo_src_addr_q [0:CMD_FIFO_DEPTH-1];
    logic [31:0] fifo_src_stride_q [0:CMD_FIFO_DEPTH-1];
    logic [2:0]  fifo_wr_q;
    logic [2:0]  fifo_rd_q;
    logic [2:0]  fifo_count_q;
    logic [31:0] cmd_done_count_q;
    logic [31:0] perf_total_cycles_q;
    logic [31:0] perf_busy_cycles_q;
    logic [31:0] perf_ddr_stall_cycles_q;
    logic [31:0] perf_write_count_q;

    logic [15:0] start_x;
    logic [15:0] start_y;
    logic [15:0] draw_w;
    logic [15:0] draw_h;
    logic [15:0] line_dx_start;
    logic [15:0] line_dy_start;
    logic        line_sx_inc_start;
    logic        line_sy_inc_start;
    logic signed [19:0] line_err2;
    logic signed [19:0] line_dx_s;
    logic signed [19:0] line_dy_s;
    logic signed [32:0] line_addr_delta;
    logic        line_move_x;
    logic        line_move_y;
    logic        op_is_clear;
    logic        op_is_fill_rect;
    logic        op_is_draw_line;
    logic        op_is_blit;
    logic        unsupported_op;
    logic        invalid_rect_start;
    logic        invalid_line_start;
    logic        invalid_blit_start;
    logic [31:0] start_addr_base;
    logic        start_req;
    logic        start_accept_req;
    logic        submit_req;
    logic        soft_reset_req;
    logic        perf_clear_req;
    logic        invalid_start;
    logic        invalid_submit;
    logic        launch_req;
    logic        capture_start_req;
    logic        capture_fifo_req;
    logic [3:0]  launch_op;
    logic [31:0] launch_color;
    logic [15:0] launch_x;
    logic [15:0] launch_y;
    logic [15:0] launch_w;
    logic [15:0] launch_h;
    logic        launch_pending_q;
    logic        launch_from_fifo_q;
    logic        start_wait_q;
    logic [3:0]  launch_op_q;
    logic [31:0] launch_color_q;
    logic [15:0] launch_x_q;
    logic [15:0] launch_y_q;
    logic [15:0] launch_w_q;
    logic [15:0] launch_h_q;
    logic [31:0] launch_src_addr_q;
    logic [31:0] launch_src_stride_q;
    logic [31:0] launch_ctrl_q;
    logic        launch_is_clear;
    logic        launch_is_fill_rect;
    logic        launch_is_draw_line;
    logic        launch_is_blit;
    logic        launch_unsupported;
    logic        launch_invalid_rect;
    logic        launch_invalid_line;
    logic        launch_invalid_blit;
    logic        launch_invalid;
    logic [15:0] launch_start_x;
    logic [15:0] launch_start_y;
    logic [15:0] launch_draw_w;
    logic [15:0] launch_draw_h;
    logic [15:0] launch_line_dx;
    logic [15:0] launch_line_dy;
    logic        launch_line_sx_inc;
    logic        launch_line_sy_inc;
    logic [31:0] launch_start_addr_base;
    logic [31:0] launch_src_addr_base;
    logic        engine_busy;

    assign ready = valid && !(capture_start_req && !start_wait_q);
    assign start_req = valid && we && addr[7:2] == 6'h00 && wstrb[0] && wdata[0];
    assign start_accept_req = start_req && !start_wait_q;
    assign submit_req = valid && we && addr[7:2] == 6'h0d && wstrb[0] && wdata[0];
    assign soft_reset_req = valid && we && addr[7:2] == 6'h00 && wstrb[3] && wdata[31];
    assign perf_clear_req = valid && we && addr[7:2] == 6'h00 && wstrb[3] && wdata[30];
    assign engine_busy = busy_q || launch_pending_q || fifo_count_q != 3'd0;

    assign op_is_clear = wdata[7:4] == OP_CLEAR;
    assign op_is_fill_rect = wdata[7:4] == OP_FILL_RECT;
    assign op_is_draw_line = wdata[7:4] == OP_DRAW_LINE;
    assign op_is_blit = wdata[7:4] == OP_BLIT;
    assign unsupported_op = !op_is_clear && !op_is_fill_rect && !op_is_draw_line && !op_is_blit;
    assign start_x = op_is_clear ? 16'd0 : rect_x_q;
    assign start_y = op_is_clear ? 16'd0 : rect_y_q;
    assign draw_w = op_is_clear ? fb_width_q : rect_w_q;
    assign draw_h = op_is_clear ? fb_height_q : rect_h_q;
    assign line_sx_inc_start = rect_w_q >= rect_x_q;
    assign line_sy_inc_start = rect_h_q >= rect_y_q;
    assign line_dx_start = line_sx_inc_start ? (rect_w_q - rect_x_q) : (rect_x_q - rect_w_q);
    assign line_dy_start = line_sy_inc_start ? (rect_h_q - rect_y_q) : (rect_y_q - rect_h_q);
    assign invalid_rect_start = draw_w == 16'd0 || draw_h == 16'd0;
    assign invalid_line_start = rect_x_q >= fb_width_q || rect_y_q >= fb_height_q ||
                                rect_w_q >= fb_width_q || rect_h_q >= fb_height_q;
    assign invalid_blit_start = src_addr_q[31:30] != 2'b10 ||
                                src_stride_q == 32'd0 ||
                                src_addr_q[1:0] != 2'b00 ||
                                start_addr_base[1:0] != 2'b00;
    assign invalid_start = engine_busy ||
                           unsupported_op ||
                           fb_addr_q[31:30] != 2'b10 ||
                           fb_stride_q == 32'd0 ||
                           (op_is_draw_line ? invalid_line_start :
                            op_is_blit ? (invalid_rect_start || invalid_blit_start) :
                            invalid_rect_start);
    assign invalid_submit = fifo_count_q == CMD_FIFO_DEPTH_U ||
                            unsupported_op ||
                            fb_addr_q[31:30] != 2'b10 ||
                            fb_stride_q == 32'd0 ||
                            (op_is_draw_line ? invalid_line_start :
                             op_is_blit ? (invalid_rect_start || invalid_blit_start) :
                             invalid_rect_start);

    assign capture_start_req = start_accept_req && !invalid_start;
    assign capture_fifo_req = !start_req && !busy_q && !launch_pending_q &&
                              fifo_count_q != 3'd0 && !submit_req;
    assign launch_req = launch_pending_q;
    assign launch_op = launch_op_q;
    assign launch_color = launch_color_q;
    assign launch_x = launch_x_q;
    assign launch_y = launch_y_q;
    assign launch_w = launch_w_q;
    assign launch_h = launch_h_q;
    assign launch_is_clear = launch_op == OP_CLEAR;
    assign launch_is_fill_rect = launch_op == OP_FILL_RECT;
    assign launch_is_draw_line = launch_op == OP_DRAW_LINE;
    assign launch_is_blit = launch_op == OP_BLIT;
    assign launch_unsupported = !launch_is_clear && !launch_is_fill_rect &&
                                !launch_is_draw_line && !launch_is_blit;
    assign launch_start_x = launch_is_clear ? 16'd0 : launch_x;
    assign launch_start_y = launch_is_clear ? 16'd0 : launch_y;
    assign launch_draw_w = launch_is_clear ? fb_width_q : launch_w;
    assign launch_draw_h = launch_is_clear ? fb_height_q : launch_h;
    assign launch_line_sx_inc = launch_w >= launch_x;
    assign launch_line_sy_inc = launch_h >= launch_y;
    assign launch_line_dx = launch_line_sx_inc ? (launch_w - launch_x) : (launch_x - launch_w);
    assign launch_line_dy = launch_line_sy_inc ? (launch_h - launch_y) : (launch_y - launch_h);
    assign launch_invalid_rect = launch_draw_w == 16'd0 || launch_draw_h == 16'd0;
    assign launch_invalid_line = launch_x >= fb_width_q || launch_y >= fb_height_q ||
                                 launch_w >= fb_width_q || launch_h >= fb_height_q;
    assign launch_invalid_blit = launch_src_addr_q[31:30] != 2'b10 ||
                                 launch_src_stride_q == 32'd0 ||
                                 launch_src_addr_q[1:0] != 2'b00 ||
                                 launch_start_addr_base[1:0] != 2'b00;
    assign launch_invalid = launch_unsupported ||
                            fb_addr_q[31:30] != 2'b10 ||
                            fb_stride_q == 32'd0 ||
                            (launch_is_draw_line ? launch_invalid_line :
                             launch_is_blit ? (launch_invalid_rect || launch_invalid_blit) :
                             launch_invalid_rect);

    assign start_addr_base = fb_addr_q + {14'd0, start_x, 2'b00};
    assign launch_start_addr_base = fb_addr_q + {14'd0, launch_start_x, 2'b00};
    assign launch_src_addr_base = launch_src_addr_q;
    assign ddr_valid = busy_q && !addr_init_q;
    assign ddr_we = !(op_q == OP_BLIT && !blit_write_phase_q);
    assign ddr_addr = (op_q == OP_BLIT && !blit_write_phase_q) ? cur_src_addr_q : cur_addr_q;
    assign ddr_wdata = (op_q == OP_BLIT) ? blit_pixel_q : active_color_q;
    assign line_dx_s = $signed({4'd0, line_dx_q});
    assign line_dy_s = $signed({4'd0, line_dy_q});
    assign line_err2 = line_err_q <<< 1;
    assign line_move_x = line_err2 > -line_dy_s;
    assign line_move_y = line_err2 < line_dx_s;
    assign line_addr_delta =
        (line_move_x ? (line_sx_inc_q ? 33'sd4 : -33'sd4) : 33'sd0) +
        (line_move_y ? (line_sy_inc_q ? $signed({1'b0, fb_stride_q}) : -$signed({1'b0, fb_stride_q})) : 33'sd0);

    always_comb begin
        rdata = 32'd0;
        case (addr[7:2])
            6'h00: rdata = {24'd0, op_q, 3'd0, busy_q};
            6'h01: rdata = {29'd0, error_q, done_q, engine_busy};
            6'h02: rdata = fb_addr_q;
            6'h03: rdata = fb_stride_q;
            6'h04: rdata = {fb_height_q, fb_width_q};
            6'h05: rdata = color_q;
            6'h06: rdata = {rect_y_q, rect_x_q};
            6'h07: rdata = {rect_h_q, rect_w_q};
            6'h08: rdata = {cur_y_q, cur_x_q};
            6'h09: rdata = {8'd0, ddr_wait_q};
            6'h0a: rdata = pixel_count_q;
            6'h0b: rdata = last_ctrl_q;
            6'h0c: rdata = cur_addr_q;
            6'h0d: rdata = {24'd0, fifo_count_q, 3'd0, fifo_count_q == CMD_FIFO_DEPTH_U, fifo_count_q == 3'd0};
            6'h0e: rdata = cmd_done_count_q;
            6'h0f: rdata = perf_total_cycles_q;
            6'h10: rdata = perf_busy_cycles_q;
            6'h11: rdata = perf_ddr_stall_cycles_q;
            6'h12: rdata = perf_write_count_q;
            6'h13: rdata = src_addr_q;
            6'h14: rdata = src_stride_q;
            default: rdata = 32'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fb_addr_q <= 32'd0;
            fb_stride_q <= 32'd0;
            fb_width_q <= 16'd0;
            fb_height_q <= 16'd0;
            color_q <= 32'd0;
            active_color_q <= 32'd0;
            rect_x_q <= 16'd0;
            rect_y_q <= 16'd0;
            rect_w_q <= 16'd0;
            rect_h_q <= 16'd0;
            src_addr_q <= 32'd0;
            src_stride_q <= 32'd0;
            op_q <= 4'd0;
            busy_q <= 1'b0;
            done_q <= 1'b0;
            error_q <= 1'b0;
            cur_x_q <= 16'd0;
            cur_y_q <= 16'd0;
            draw_start_x_q <= 16'd0;
            end_x_q <= 16'd0;
            end_y_q <= 16'd0;
            cur_addr_q <= 32'd0;
            cur_src_addr_q <= 32'd0;
            row_start_addr_q <= 32'd0;
            src_row_start_addr_q <= 32'd0;
            addr_init_q <= 1'b0;
            addr_init_rows_q <= 16'd0;
            blit_write_phase_q <= 1'b0;
            blit_pixel_q <= 32'd0;
            ddr_wait_q <= 24'd0;
            pixel_count_q <= 32'd0;
            last_ctrl_q <= 32'd0;
            line_dx_q <= 16'd0;
            line_dy_q <= 16'd0;
            line_sx_inc_q <= 1'b1;
            line_sy_inc_q <= 1'b1;
            line_err_q <= 20'sd0;
            launch_pending_q <= 1'b0;
            launch_from_fifo_q <= 1'b0;
            start_wait_q <= 1'b0;
            launch_op_q <= 4'd0;
            launch_color_q <= 32'd0;
            launch_x_q <= 16'd0;
            launch_y_q <= 16'd0;
            launch_w_q <= 16'd0;
            launch_h_q <= 16'd0;
            launch_src_addr_q <= 32'd0;
            launch_src_stride_q <= 32'd0;
            launch_ctrl_q <= 32'd0;
            fifo_wr_q <= 3'd0;
            fifo_rd_q <= 3'd0;
            fifo_count_q <= 3'd0;
            cmd_done_count_q <= 32'd0;
            perf_total_cycles_q <= 32'd0;
            perf_busy_cycles_q <= 32'd0;
            perf_ddr_stall_cycles_q <= 32'd0;
            perf_write_count_q <= 32'd0;
            for (int i = 0; i < CMD_FIFO_DEPTH; i++) begin
                fifo_op_q[i] <= 4'd0;
                fifo_color_q[i] <= 32'd0;
                fifo_x_q[i] <= 16'd0;
                fifo_y_q[i] <= 16'd0;
                fifo_w_q[i] <= 16'd0;
                fifo_h_q[i] <= 16'd0;
                fifo_src_addr_q[i] <= 32'd0;
                fifo_src_stride_q[i] <= 32'd0;
            end
        end else if (soft_reset_req) begin
            busy_q <= 1'b0;
            done_q <= 1'b0;
            error_q <= 1'b0;
            cur_x_q <= 16'd0;
            cur_y_q <= 16'd0;
            draw_start_x_q <= 16'd0;
            end_x_q <= 16'd0;
            end_y_q <= 16'd0;
            cur_addr_q <= 32'd0;
            cur_src_addr_q <= 32'd0;
            row_start_addr_q <= 32'd0;
            src_row_start_addr_q <= 32'd0;
            addr_init_q <= 1'b0;
            addr_init_rows_q <= 16'd0;
            blit_write_phase_q <= 1'b0;
            blit_pixel_q <= 32'd0;
            ddr_wait_q <= 24'd0;
            pixel_count_q <= 32'd0;
            last_ctrl_q <= wdata;
            line_dx_q <= 16'd0;
            line_dy_q <= 16'd0;
            line_sx_inc_q <= 1'b1;
            line_sy_inc_q <= 1'b1;
            line_err_q <= 20'sd0;
            launch_pending_q <= 1'b0;
            launch_from_fifo_q <= 1'b0;
            start_wait_q <= 1'b0;
            launch_op_q <= 4'd0;
            launch_color_q <= 32'd0;
            launch_x_q <= 16'd0;
            launch_y_q <= 16'd0;
            launch_w_q <= 16'd0;
            launch_h_q <= 16'd0;
            launch_src_addr_q <= 32'd0;
            launch_src_stride_q <= 32'd0;
            launch_ctrl_q <= 32'd0;
            fifo_wr_q <= 3'd0;
            fifo_rd_q <= 3'd0;
            fifo_count_q <= 3'd0;
            cmd_done_count_q <= 32'd0;
        end else begin
            perf_total_cycles_q <= perf_total_cycles_q + 32'd1;
            if (engine_busy) begin
                perf_busy_cycles_q <= perf_busy_cycles_q + 32'd1;
            end
            if (ddr_valid && !ddr_ready) begin
                perf_ddr_stall_cycles_q <= perf_ddr_stall_cycles_q + 32'd1;
            end
            if (ddr_valid && ddr_ready && ddr_we) begin
                perf_write_count_q <= perf_write_count_q + 32'd1;
            end
            if (perf_clear_req) begin
                perf_total_cycles_q <= 32'd0;
                perf_busy_cycles_q <= 32'd0;
                perf_ddr_stall_cycles_q <= 32'd0;
                perf_write_count_q <= 32'd0;
            end

            if (valid && we) begin
                case (addr[7:2])
                    6'h01: begin
                        if (wstrb[0] && wdata[1]) done_q <= 1'b0;
                        if (wstrb[0] && wdata[2]) error_q <= 1'b0;
                    end
                    6'h02: fb_addr_q <= merge_word(fb_addr_q, wdata, wstrb);
                    6'h03: fb_stride_q <= merge_word(fb_stride_q, wdata, wstrb);
                    6'h04: begin
                        if (wstrb[0]) fb_width_q[7:0] <= wdata[7:0];
                        if (wstrb[1]) fb_width_q[15:8] <= wdata[15:8];
                        if (wstrb[2]) fb_height_q[7:0] <= wdata[23:16];
                        if (wstrb[3]) fb_height_q[15:8] <= wdata[31:24];
                    end
                    6'h05: color_q <= merge_word(color_q, wdata, wstrb);
                    6'h06: begin
                        if (wstrb[0]) rect_x_q[7:0] <= wdata[7:0];
                        if (wstrb[1]) rect_x_q[15:8] <= wdata[15:8];
                        if (wstrb[2]) rect_y_q[7:0] <= wdata[23:16];
                        if (wstrb[3]) rect_y_q[15:8] <= wdata[31:24];
                    end
                    6'h07: begin
                        if (wstrb[0]) rect_w_q[7:0] <= wdata[7:0];
                        if (wstrb[1]) rect_w_q[15:8] <= wdata[15:8];
                        if (wstrb[2]) rect_h_q[7:0] <= wdata[23:16];
                        if (wstrb[3]) rect_h_q[15:8] <= wdata[31:24];
                    end
                    6'h13: src_addr_q <= merge_word(src_addr_q, wdata, wstrb);
                    6'h14: src_stride_q <= merge_word(src_stride_q, wdata, wstrb);
                    default: begin
                    end
                endcase
            end

            if (start_accept_req) begin
                last_ctrl_q <= wdata;
                done_q <= 1'b0;
                error_q <= invalid_start;
            end

            if (submit_req) begin
                last_ctrl_q <= wdata;
                done_q <= 1'b0;
                error_q <= invalid_submit;
                if (!invalid_submit) begin
                    fifo_op_q[fifo_wr_q[1:0]] <= wdata[7:4];
                    fifo_color_q[fifo_wr_q[1:0]] <= color_q;
                    fifo_x_q[fifo_wr_q[1:0]] <= rect_x_q;
                    fifo_y_q[fifo_wr_q[1:0]] <= rect_y_q;
                    fifo_w_q[fifo_wr_q[1:0]] <= rect_w_q;
                    fifo_h_q[fifo_wr_q[1:0]] <= rect_h_q;
                    fifo_src_addr_q[fifo_wr_q[1:0]] <= src_addr_q;
                    fifo_src_stride_q[fifo_wr_q[1:0]] <= src_stride_q;
                    fifo_wr_q <= fifo_wr_q == 3'd3 ? 3'd0 : (fifo_wr_q + 3'd1);
                    fifo_count_q <= fifo_count_q + 3'd1;
                end
            end

            if (capture_start_req) begin
                launch_pending_q <= 1'b1;
                launch_from_fifo_q <= 1'b0;
                start_wait_q <= 1'b1;
                launch_op_q <= wdata[7:4];
                launch_color_q <= color_q;
                launch_x_q <= rect_x_q;
                launch_y_q <= rect_y_q;
                launch_w_q <= rect_w_q;
                launch_h_q <= rect_h_q;
                launch_src_addr_q <= src_addr_q;
                launch_src_stride_q <= src_stride_q;
                launch_ctrl_q <= wdata;
            end else if (capture_fifo_req) begin
                launch_pending_q <= 1'b1;
                launch_from_fifo_q <= 1'b1;
                launch_op_q <= fifo_op_q[fifo_rd_q[1:0]];
                launch_color_q <= fifo_color_q[fifo_rd_q[1:0]];
                launch_x_q <= fifo_x_q[fifo_rd_q[1:0]];
                launch_y_q <= fifo_y_q[fifo_rd_q[1:0]];
                launch_w_q <= fifo_w_q[fifo_rd_q[1:0]];
                launch_h_q <= fifo_h_q[fifo_rd_q[1:0]];
                launch_src_addr_q <= fifo_src_addr_q[fifo_rd_q[1:0]];
                launch_src_stride_q <= fifo_src_stride_q[fifo_rd_q[1:0]];
                launch_ctrl_q <= {24'd0, fifo_op_q[fifo_rd_q[1:0]], 3'd0, 1'b1};
                fifo_rd_q <= fifo_rd_q == 3'd3 ? 3'd0 : (fifo_rd_q + 3'd1);
                fifo_count_q <= fifo_count_q - 3'd1;
            end

            if (launch_req) begin
                launch_pending_q <= 1'b0;
                launch_from_fifo_q <= 1'b0;
                start_wait_q <= 1'b0;
                last_ctrl_q <= launch_ctrl_q;
                done_q <= 1'b0;
                error_q <= launch_invalid;
                ddr_wait_q <= 24'd0;
                pixel_count_q <= 32'd0;
                if (!launch_invalid) begin
                    if (launch_from_fifo_q) begin
                        last_ctrl_q <= {24'd0, launch_op, 3'd0, 1'b1};
                    end
                    op_q <= launch_op;
                    active_color_q <= launch_color;
                    busy_q <= 1'b1;
                    cur_x_q <= launch_start_x;
                    cur_y_q <= launch_start_y;
                    draw_start_x_q <= launch_start_x;
                    end_x_q <= launch_is_draw_line ? launch_w : (launch_start_x + launch_draw_w);
                    end_y_q <= launch_is_draw_line ? launch_h : (launch_start_y + launch_draw_h);
                    cur_addr_q <= launch_start_addr_base;
                    cur_src_addr_q <= launch_src_addr_base;
                    row_start_addr_q <= launch_start_addr_base;
                    src_row_start_addr_q <= launch_src_addr_base;
                    addr_init_q <= launch_start_y != 16'd0;
                    addr_init_rows_q <= launch_start_y;
                    blit_write_phase_q <= 1'b0;
                    blit_pixel_q <= 32'd0;
                    line_dx_q <= launch_line_dx;
                    line_dy_q <= launch_line_dy;
                    line_sx_inc_q <= launch_line_sx_inc;
                    line_sy_inc_q <= launch_line_sy_inc;
                    line_err_q <= $signed({4'd0, launch_line_dx}) - $signed({4'd0, launch_line_dy});
                end
            end else if (busy_q && addr_init_q) begin
                cur_addr_q <= cur_addr_q + fb_stride_q;
                row_start_addr_q <= row_start_addr_q + fb_stride_q;
                addr_init_rows_q <= addr_init_rows_q - 16'd1;
                if (addr_init_rows_q == 16'd1) begin
                    addr_init_q <= 1'b0;
                end
            end else if (busy_q && ddr_ready) begin
                ddr_wait_q <= 24'd0;
                if (op_q == OP_BLIT && !blit_write_phase_q) begin
                    blit_pixel_q <= ddr_rdata;
                    blit_write_phase_q <= 1'b1;
                end else begin
                    pixel_count_q <= pixel_count_q + 32'd1;
                    if (op_q == OP_BLIT) begin
                        blit_write_phase_q <= 1'b0;
                    end
                    if (op_q == OP_DRAW_LINE) begin
                        if (cur_x_q == end_x_q && cur_y_q == end_y_q) begin
                            busy_q <= 1'b0;
                            done_q <= fifo_count_q == 3'd0;
                            cmd_done_count_q <= cmd_done_count_q + 32'd1;
                        end else begin
                            if (line_move_x) begin
                                cur_x_q <= line_sx_inc_q ? (cur_x_q + 16'd1) : (cur_x_q - 16'd1);
                            end
                            if (line_move_y) begin
                                cur_y_q <= line_sy_inc_q ? (cur_y_q + 16'd1) : (cur_y_q - 16'd1);
                            end
                            line_err_q <= line_err_q +
                                          (line_move_x ? -line_dy_s : 20'sd0) +
                                          (line_move_y ? line_dx_s : 20'sd0);
                            cur_addr_q <= cur_addr_q + line_addr_delta[31:0];
                        end
                    end else if ((cur_x_q + 16'd1) >= end_x_q) begin
                        cur_x_q <= draw_start_x_q;
                        if ((cur_y_q + 16'd1) >= end_y_q) begin
                            busy_q <= 1'b0;
                            done_q <= fifo_count_q == 3'd0;
                            cmd_done_count_q <= cmd_done_count_q + 32'd1;
                        end else begin
                            cur_y_q <= cur_y_q + 16'd1;
                            row_start_addr_q <= row_start_addr_q + fb_stride_q;
                            cur_addr_q <= row_start_addr_q + fb_stride_q;
                            if (op_q == OP_BLIT) begin
                                src_row_start_addr_q <= src_row_start_addr_q + src_stride_q;
                                cur_src_addr_q <= src_row_start_addr_q + src_stride_q;
                            end
                        end
                    end else begin
                        cur_x_q <= cur_x_q + 16'd1;
                        cur_addr_q <= cur_addr_q + 32'd4;
                        if (op_q == OP_BLIT) begin
                            cur_src_addr_q <= cur_src_addr_q + 32'd4;
                        end
                    end
                end
            end else if (busy_q) begin
                if (ddr_wait_q == DDR_WAIT_TIMEOUT) begin
                    busy_q <= 1'b0;
                    error_q <= 1'b1;
                end else begin
                    ddr_wait_q <= ddr_wait_q + 24'd1;
                end
            end
        end
    end

    function automatic logic [31:0] merge_word(
        input logic [31:0] data,
        input logic [31:0] new_data,
        input logic [3:0] strb
    );
        logic [31:0] merged;
        merged = data;
        for (int i = 0; i < 4; i++) begin
            if (strb[i]) begin
                merged[i * 8 +: 8] = new_data[i * 8 +: 8];
            end
        end
        merge_word = merged;
    endfunction
endmodule
