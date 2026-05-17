module datamover_ctrl #(
    parameter int ADDR_WIDTH = 32,
    parameter int BTT_WIDTH  = 23,
    parameter int TAG_WIDTH  = 4,
    parameter int CMD_WIDTH  = 72
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        valid,
    input  logic        we,
    input  logic [3:0]  wstrb,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic        ready,
    output logic [31:0] rdata,

    output logic                  mm2s_cmd_valid,
    input  logic                  mm2s_cmd_ready,
    output logic [CMD_WIDTH-1:0]  mm2s_cmd_data,
    input  logic                  mm2s_sts_valid,
    output logic                  mm2s_sts_ready,
    input  logic [7:0]            mm2s_sts_data,

    output logic                  s2mm_cmd_valid,
    input  logic                  s2mm_cmd_ready,
    output logic [CMD_WIDTH-1:0]  s2mm_cmd_data,
    input  logic                  s2mm_sts_valid,
    output logic                  s2mm_sts_ready,
    input  logic [7:0]            s2mm_sts_data,

    output logic [31:0]           local_addr_o,
    output logic [31:0]           length_bytes_o,
    output logic                  mm2s_local_start,
    input  logic                  mm2s_local_ready,
    output logic                  s2mm_local_start,
    input  logic                  s2mm_local_ready
);
    localparam logic [31:0] STATUS_MM2S_BUSY  = 32'h0000_0001;
    localparam logic [31:0] STATUS_S2MM_BUSY  = 32'h0000_0002;
    localparam logic [31:0] STATUS_MM2S_DONE  = 32'h0000_0004;
    localparam logic [31:0] STATUS_S2MM_DONE  = 32'h0000_0008;
    localparam logic [31:0] STATUS_MM2S_ERR   = 32'h0000_0010;
    localparam logic [31:0] STATUS_S2MM_ERR   = 32'h0000_0020;
    localparam logic [31:0] STATUS_MM2S_CREADY = 32'h0000_0040;
    localparam logic [31:0] STATUS_S2MM_CREADY = 32'h0000_0080;

    logic [31:0] ddr_addr;
    logic [31:0] local_addr;
    logic [31:0] length_bytes;
    logic [3:0]  tag;
    logic        mm2s_busy;
    logic        s2mm_busy;
    logic        mm2s_done;
    logic        s2mm_done;
    logic        mm2s_err;
    logic        s2mm_err;

    logic write_hit;
    logic request_mm2s;
    logic request_s2mm;
    logic start_mm2s;
    logic start_s2mm;

    assign request_mm2s = valid && we && addr[5:2] == 4'h0 && wdata[0] && !mm2s_busy;
    assign request_s2mm = valid && we && addr[5:2] == 4'h0 && wdata[1] && !s2mm_busy;
    assign ready = valid &&
                   (!request_mm2s || (mm2s_cmd_ready && mm2s_local_ready)) &&
                   (!request_s2mm || (s2mm_cmd_ready && s2mm_local_ready));
    assign write_hit = valid && we && ready;
    assign start_mm2s = write_hit && addr[5:2] == 4'h0 && wdata[0] && !mm2s_busy;
    assign start_s2mm = write_hit && addr[5:2] == 4'h0 && wdata[1] && !s2mm_busy;

    assign mm2s_cmd_valid = start_mm2s;
    assign s2mm_cmd_valid = start_s2mm;
    assign mm2s_sts_ready = 1'b1;
    assign s2mm_sts_ready = 1'b1;
    assign local_addr_o = local_addr;
    assign length_bytes_o = length_bytes;
    assign mm2s_local_start = start_mm2s;
    assign s2mm_local_start = start_s2mm;

    always @* begin
        rdata = 32'd0;
        case (addr[5:2])
            4'h0: rdata = 32'd0;
            4'h1: rdata = ({32{mm2s_busy}} & STATUS_MM2S_BUSY) |
                           ({32{s2mm_busy}} & STATUS_S2MM_BUSY) |
                           ({32{mm2s_done}} & STATUS_MM2S_DONE) |
                           ({32{s2mm_done}} & STATUS_S2MM_DONE) |
                           ({32{mm2s_err}} & STATUS_MM2S_ERR) |
                           ({32{s2mm_err}} & STATUS_S2MM_ERR) |
                           ({32{mm2s_cmd_ready}} & STATUS_MM2S_CREADY) |
                           ({32{s2mm_cmd_ready}} & STATUS_S2MM_CREADY);
            4'h2: rdata = ddr_addr;
            4'h3: rdata = local_addr;
            4'h4: rdata = length_bytes;
            4'h5: rdata = {28'd0, tag};
            4'h6: rdata = {24'd0, mm2s_sts_data};
            4'h7: rdata = {24'd0, s2mm_sts_data};
            default: rdata = 32'd0;
        endcase
    end

    function automatic logic [CMD_WIDTH-1:0] pack_cmd(
        input logic [31:0] base_addr,
        input logic [31:0] bytes,
        input logic [3:0]  cmd_tag,
        input logic        include_drr
    );
        logic [CMD_WIDTH-1:0] cmd;
        begin
            cmd = '0;
            cmd[BTT_WIDTH-1:0] = bytes[BTT_WIDTH-1:0];
            cmd[23] = 1'b1;
            cmd[29:24] = 6'd0;
            cmd[30] = 1'b1;
            cmd[31] = include_drr;
            cmd[32 +: ADDR_WIDTH] = base_addr[ADDR_WIDTH-1:0];
            cmd[32 + ADDR_WIDTH +: TAG_WIDTH] = cmd_tag[TAG_WIDTH-1:0];
            pack_cmd = cmd;
        end
    endfunction

    assign mm2s_cmd_data = pack_cmd(ddr_addr, length_bytes, tag, 1'b0);
    assign s2mm_cmd_data = pack_cmd(ddr_addr, length_bytes, tag, 1'b1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ddr_addr <= 32'd0;
            local_addr <= 32'd0;
            length_bytes <= 32'd0;
            tag <= 4'd0;
            mm2s_busy <= 1'b0;
            s2mm_busy <= 1'b0;
            mm2s_done <= 1'b0;
            s2mm_done <= 1'b0;
            mm2s_err <= 1'b0;
            s2mm_err <= 1'b0;
        end else begin
            if (write_hit) begin
                case (addr[5:2])
                    4'h1: begin
                        mm2s_done <= mm2s_done & ~wdata[2];
                        s2mm_done <= s2mm_done & ~wdata[3];
                        mm2s_err <= mm2s_err & ~wdata[4];
                        s2mm_err <= s2mm_err & ~wdata[5];
                    end
                    4'h2: ddr_addr <= wdata;
                    4'h3: local_addr <= wdata;
                    4'h4: length_bytes <= wdata;
                    4'h5: tag <= wdata[3:0];
                    default: begin
                    end
                endcase
            end

            if (start_mm2s && mm2s_cmd_ready) begin
                mm2s_busy <= 1'b1;
                mm2s_done <= 1'b0;
                mm2s_err <= 1'b0;
            end
            if (start_s2mm && s2mm_cmd_ready) begin
                s2mm_busy <= 1'b1;
                s2mm_done <= 1'b0;
                s2mm_err <= 1'b0;
            end

            if (mm2s_sts_valid) begin
                mm2s_busy <= 1'b0;
                mm2s_done <= 1'b1;
                mm2s_err <= |mm2s_sts_data[6:4];
            end
            if (s2mm_sts_valid) begin
                s2mm_busy <= 1'b0;
                s2mm_done <= 1'b1;
                s2mm_err <= |s2mm_sts_data[6:4];
            end
        end
    end
endmodule
