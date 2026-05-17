module axi_lite_bringup_regs #(
    parameter logic [31:0] BUILD_ID = 32'h2605_1001
) (
    input  logic        S_AXI_ACLK,
    input  logic        S_AXI_ARESETN,

    input  logic [5:0]  S_AXI_AWADDR,
    input  logic [2:0]  S_AXI_AWPROT,
    input  logic        S_AXI_AWVALID,
    output logic        S_AXI_AWREADY,
    input  logic [31:0] S_AXI_WDATA,
    input  logic [3:0]  S_AXI_WSTRB,
    input  logic        S_AXI_WVALID,
    output logic        S_AXI_WREADY,
    output logic [1:0]  S_AXI_BRESP,
    output logic        S_AXI_BVALID,
    input  logic        S_AXI_BREADY,

    input  logic [5:0]  S_AXI_ARADDR,
    input  logic [2:0]  S_AXI_ARPROT,
    input  logic        S_AXI_ARVALID,
    output logic        S_AXI_ARREADY,
    output logic [31:0] S_AXI_RDATA,
    output logic [1:0]  S_AXI_RRESP,
    output logic        S_AXI_RVALID,
    input  logic        S_AXI_RREADY
);
    logic [31:0] scratch;
    logic [31:0] write_count;
    logic [31:0] read_count;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;
    logic [5:0]  awaddr_q;
    logic [5:0]  araddr_q;
    logic        aw_seen;
    logic        w_seen;

    wire resetn = S_AXI_ARESETN;
    wire write_fire = (!S_AXI_BVALID) &&
                      ((aw_seen || S_AXI_AWVALID) && (w_seen || S_AXI_WVALID));
    wire read_fire = S_AXI_ARVALID && S_AXI_ARREADY;

    assign S_AXI_AWREADY = !S_AXI_BVALID && !aw_seen;
    assign S_AXI_WREADY  = !S_AXI_BVALID && !w_seen;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_ARREADY = !S_AXI_RVALID;
    assign S_AXI_RRESP   = 2'b00;

    always_comb begin
        unique case (araddr_q[5:2])
            4'h0: S_AXI_RDATA = BUILD_ID;
            4'h1: S_AXI_RDATA = 32'h0000_0001;
            4'h2: S_AXI_RDATA = scratch;
            4'h3: S_AXI_RDATA = write_count;
            4'h4: S_AXI_RDATA = read_count;
            default: S_AXI_RDATA = 32'd0;
        endcase
    end

    always_ff @(posedge S_AXI_ACLK or negedge resetn) begin
        if (!resetn) begin
            scratch <= 32'd0;
            write_count <= 32'd0;
            read_count <= 32'd0;
            wdata_q <= 32'd0;
            wstrb_q <= 4'd0;
            awaddr_q <= 6'd0;
            araddr_q <= 6'd0;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
            S_AXI_BVALID <= 1'b0;
            S_AXI_RVALID <= 1'b0;
        end else begin
            if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                awaddr_q <= S_AXI_AWADDR;
                aw_seen <= 1'b1;
            end

            if (S_AXI_WREADY && S_AXI_WVALID) begin
                wdata_q <= S_AXI_WDATA;
                wstrb_q <= S_AXI_WSTRB;
                w_seen <= 1'b1;
            end

            if (write_fire) begin
                if (((aw_seen) ? awaddr_q[5:2] : S_AXI_AWADDR[5:2]) == 4'h2) begin
                    for (int i = 0; i < 4; i++) begin
                        if (((w_seen) ? wstrb_q[i] : S_AXI_WSTRB[i])) begin
                            scratch[i * 8 +: 8] <= ((w_seen) ? wdata_q[i * 8 +: 8] : S_AXI_WDATA[i * 8 +: 8]);
                        end
                    end
                end
                write_count <= write_count + 32'd1;
                S_AXI_BVALID <= 1'b1;
                aw_seen <= 1'b0;
                w_seen <= 1'b0;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end

            if (read_fire) begin
                araddr_q <= S_AXI_ARADDR;
                read_count <= read_count + 32'd1;
                S_AXI_RVALID <= 1'b1;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end
endmodule
