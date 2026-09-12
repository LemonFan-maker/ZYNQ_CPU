module fregfile64 (
    input  logic        clk,
    input  logic        wen,
    input  logic [4:0]  waddr,
    input  logic [63:0] wdata,
    input  logic [4:0]  raddr1,
    output logic [63:0] rdata1,
    input  logic [4:0]  raddr2,
    output logic [63:0] rdata2,
    input  logic [4:0]  raddr3,
    output logic [63:0] rdata3
);
    logic [63:0] regs [31:0];

    assign rdata1 = regs[raddr1];
    assign rdata2 = regs[raddr2];
    assign rdata3 = regs[raddr3];

    always_ff @(posedge clk) begin
        if (wen) begin
            regs[waddr] <= wdata;
        end
    end
endmodule
