module regfile64 (
    input  logic        clk,
    input  logic        wen,
    input  logic [4:0]  waddr,
    input  logic [63:0] wdata,
    input  logic [4:0]  raddr1,
    output logic [63:0] rdata1,
    input  logic [4:0]  raddr2,
    output logic [63:0] rdata2
);
    logic [63:0] regs [31:0];

    assign rdata1 = (raddr1 == 5'd0) ? 64'd0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 64'd0 : regs[raddr2];

    always_ff @(posedge clk) begin
        if (wen && waddr != 5'd0) begin
            regs[waddr] <= wdata;
        end
    end
endmodule
