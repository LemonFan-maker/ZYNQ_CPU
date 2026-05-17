module axi4_master_bridge #(
    parameter int  AXI_ID_WIDTH   = 4,
    parameter int  AXI_ADDR_WIDTH = 32,
    parameter int  AXI_DATA_WIDTH = 32,
    parameter logic [31:0] CPU_BASE_ADDR  = 32'h8000_0000,
    parameter logic [31:0] PHYS_BASE_ADDR = 32'h0010_0000
) (
    input  logic clk,
    input  logic rst_n,

    input  logic        valid,
    input  logic        we,
    input  logic [3:0]  wstrb,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic        ready,
    output logic [31:0] rdata,

    output logic [AXI_ID_WIDTH-1:0]    M_AXI_AWID,
    output logic [AXI_ADDR_WIDTH-1:0]  M_AXI_AWADDR,
    output logic [7:0]                 M_AXI_AWLEN,
    output logic [2:0]                 M_AXI_AWSIZE,
    output logic [1:0]                 M_AXI_AWBURST,
    output logic                       M_AXI_AWLOCK,
    output logic [3:0]                 M_AXI_AWCACHE,
    output logic [2:0]                 M_AXI_AWPROT,
    output logic [3:0]                 M_AXI_AWQOS,
    output logic                       M_AXI_AWVALID,
    input  logic                       M_AXI_AWREADY,

    output logic [AXI_DATA_WIDTH-1:0]  M_AXI_WDATA,
    output logic [AXI_DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output logic                       M_AXI_WLAST,
    output logic                       M_AXI_WVALID,
    input  logic                       M_AXI_WREADY,

    input  logic [AXI_ID_WIDTH-1:0]    M_AXI_BID,
    input  logic [1:0]                 M_AXI_BRESP,
    input  logic                       M_AXI_BVALID,
    output logic                       M_AXI_BREADY,

    output logic [AXI_ID_WIDTH-1:0]    M_AXI_ARID,
    output logic [AXI_ADDR_WIDTH-1:0]  M_AXI_ARADDR,
    output logic [7:0]                 M_AXI_ARLEN,
    output logic [2:0]                 M_AXI_ARSIZE,
    output logic [1:0]                 M_AXI_ARBURST,
    output logic                       M_AXI_ARLOCK,
    output logic [3:0]                 M_AXI_ARCACHE,
    output logic [2:0]                 M_AXI_ARPROT,
    output logic [3:0]                 M_AXI_ARQOS,
    output logic                       M_AXI_ARVALID,
    input  logic                       M_AXI_ARREADY,

    input  logic [AXI_ID_WIDTH-1:0]    M_AXI_RID,
    input  logic [AXI_DATA_WIDTH-1:0]  M_AXI_RDATA,
    input  logic [1:0]                 M_AXI_RRESP,
    input  logic                       M_AXI_RLAST,
    input  logic                       M_AXI_RVALID,
    output logic                       M_AXI_RREADY
);
    typedef enum logic [2:0] {
        S_IDLE,
        S_WAIT_AW_W,
        S_WAIT_B,
        S_WAIT_AR,
        S_WAIT_R,
        S_DONE
    } state_t;

    state_t state, next_state;

    logic [31:0] axi_addr_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic [31:0] rdata_q;
    logic        aw_done_q, w_done_q;

    assign M_AXI_AWID    = {AXI_ID_WIDTH{1'b0}};
    assign M_AXI_ARID    = {AXI_ID_WIDTH{1'b0}};
    assign M_AXI_AWLEN   = 8'd0;
    assign M_AXI_ARLEN   = 8'd0;
    assign M_AXI_AWSIZE  = 3'd2;
    assign M_AXI_ARSIZE  = 3'd2;
    assign M_AXI_AWBURST = 2'd1;
    assign M_AXI_ARBURST = 2'd1;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0011;
    assign M_AXI_ARCACHE = 4'b0011;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'd0;
    assign M_AXI_ARQOS   = 4'd0;

    assign M_AXI_AWADDR = axi_addr_q;
    assign M_AXI_ARADDR = axi_addr_q;
    assign M_AXI_WDATA  = wdata_q;
    assign M_AXI_WSTRB  = wstrb_q;
    assign M_AXI_WLAST  = 1'b1;

    always_comb begin
        next_state = state;
        M_AXI_AWVALID = 1'b0;
        M_AXI_WVALID  = 1'b0;
        M_AXI_BREADY  = 1'b0;
        M_AXI_ARVALID = 1'b0;
        M_AXI_RREADY  = 1'b0;
        ready = 1'b0;
        rdata = rdata_q;

        case (state)
            S_IDLE: begin
                if (valid && we) begin
                    next_state = S_WAIT_AW_W;
                end else if (valid && !we) begin
                    next_state = S_WAIT_AR;
                end
            end
            S_WAIT_AW_W: begin
                M_AXI_AWVALID = ~aw_done_q;
                M_AXI_WVALID  = ~w_done_q;
                if (aw_done_q && w_done_q) begin
                    next_state = S_WAIT_B;
                end
            end
            S_WAIT_B: begin
                M_AXI_BREADY = 1'b1;
                if (M_AXI_BVALID) begin
                    next_state = S_DONE;
                end
            end
            S_WAIT_AR: begin
                M_AXI_ARVALID = 1'b1;
                if (M_AXI_ARREADY) begin
                    next_state = S_WAIT_R;
                end
            end
            S_WAIT_R: begin
                M_AXI_RREADY = 1'b1;
                if (M_AXI_RVALID) begin
                    next_state = S_DONE;
                end
            end
            S_DONE: begin
                ready = 1'b1;
                if (valid) begin
                    next_state = S_IDLE;
                end
            end
            default: next_state = S_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            axi_addr_q <= 32'd0;
            wdata_q <= 32'd0;
            wstrb_q <= 4'd0;
            rdata_q <= 32'd0;
            aw_done_q <= 1'b0;
            w_done_q <= 1'b0;
        end else begin
            state <= next_state;
            if (state == S_IDLE && valid) begin
                axi_addr_q <= addr - CPU_BASE_ADDR + PHYS_BASE_ADDR;
                wdata_q <= wdata;
                wstrb_q <= wstrb;
            end
            if (state == S_IDLE && valid && we) begin
                aw_done_q <= 1'b0;
                w_done_q <= 1'b0;
            end else if (state == S_WAIT_AW_W) begin
                if (~aw_done_q && M_AXI_AWREADY) aw_done_q <= 1'b1;
                if (~w_done_q && M_AXI_WREADY)  w_done_q <= 1'b1;
            end
            if (state == S_WAIT_R && M_AXI_RVALID && M_AXI_RREADY) begin
                rdata_q <= M_AXI_RDATA;
            end
        end
    end
endmodule
