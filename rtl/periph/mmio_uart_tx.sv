module mmio_uart_tx #(
    parameter int CLK_HZ = 75_000_000,
    parameter int BAUD   = 115_200
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

    output logic        tx
);
    localparam int CLKS_PER_BIT = CLK_HZ / BAUD;
    localparam int CNT_WIDTH = $clog2(CLKS_PER_BIT);

    logic [CNT_WIDTH-1:0] baud_cnt;
    logic [3:0] bit_idx;
    logic [9:0] shifter;
    logic busy;
    logic fire_write;

    assign ready = valid;
    assign fire_write = valid && we && wstrb[0] && addr[3:2] == 2'd0 && !busy;
    assign rdata = (addr[3:2] == 2'd1) ? {30'd0, busy, !busy} : 32'd0;
    assign tx = busy ? shifter[0] : 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= '0;
            bit_idx <= 4'd0;
            shifter <= 10'h3ff;
            busy <= 1'b0;
        end else begin
            if (fire_write) begin
                shifter <= {1'b1, wdata[7:0], 1'b0};
                baud_cnt <= '0;
                bit_idx <= 4'd0;
                busy <= 1'b1;
`ifndef SYNTHESIS
                $write("%c", wdata[7:0]);
`endif
            end else if (busy) begin
                if (baud_cnt == CLKS_PER_BIT[CNT_WIDTH-1:0] - 1'b1) begin
                    baud_cnt <= '0;
                    shifter <= {1'b1, shifter[9:1]};
                    if (bit_idx == 4'd9) begin
                        busy <= 1'b0;
                    end else begin
                        bit_idx <= bit_idx + 4'd1;
                    end
                end else begin
                    baud_cnt <= baud_cnt + {{(CNT_WIDTH-1){1'b0}}, 1'b1};
                end
            end
        end
    end
endmodule
