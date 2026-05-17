module mmio_timer (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        valid,
    input  logic        we,
    input  logic [3:0]  wstrb,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic        ready,
    output logic [31:0] rdata,
    output logic        irq_timer
);
    logic [63:0] mtime;
    logic [63:0] mtimecmp;
    logic        write_hit;

    assign ready = valid;
    assign write_hit = valid && we && ready;
    assign irq_timer = (mtimecmp != 64'd0) && (mtime >= mtimecmp);

    always_comb begin
        rdata = 32'd0;
        case (addr[5:2])
            4'h0: rdata = mtime[31:0];
            4'h1: rdata = mtime[63:32];
            4'h2: rdata = mtimecmp[31:0];
            4'h3: rdata = mtimecmp[63:32];
            4'h4: rdata = {31'd0, irq_timer};
            default: rdata = 32'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= 64'd0;
            mtimecmp <= 64'd0;
        end else begin
            mtime <= mtime + 64'd1;

            if (write_hit) begin
                case (addr[5:2])
                    4'h0: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) begin
                                mtime[i * 8 +: 8] <= wdata[i * 8 +: 8];
                            end
                        end
                    end
                    4'h1: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) begin
                                mtime[32 + i * 8 +: 8] <= wdata[i * 8 +: 8];
                            end
                        end
                    end
                    4'h2: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) begin
                                mtimecmp[i * 8 +: 8] <= wdata[i * 8 +: 8];
                            end
                        end
                    end
                    4'h3: begin
                        for (int i = 0; i < 4; i++) begin
                            if (wstrb[i]) begin
                                mtimecmp[32 + i * 8 +: 8] <= wdata[i * 8 +: 8];
                            end
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
