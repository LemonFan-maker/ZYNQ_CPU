module mmio_irqctrl #(
    parameter int NUM_SOURCES = 8
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  valid,
    input  logic                  we,
    input  logic [3:0]            wstrb,
    input  logic [31:0]           addr,
    input  logic [31:0]           wdata,
    output logic                  ready,
    output logic [31:0]           rdata,

    input  logic [NUM_SOURCES-1:0] source_irq,
    output logic                  irq_external
);
    logic [NUM_SOURCES-1:0] pending;
    logic [NUM_SOURCES-1:0] pending_next;
    logic [NUM_SOURCES-1:0] enable;
    logic [2:0]             threshold;
    logic [3:0]             claim_id;

    function automatic logic [3:0] select_claim(
        input logic [NUM_SOURCES-1:0] pending_mask,
        input logic [NUM_SOURCES-1:0] enable_mask,
        input logic [2:0] threshold_value
    );
        begin
            select_claim = 4'd0;
            for (int i = NUM_SOURCES - 1; i >= 0; i--) begin
                if (select_claim == 4'd0 && pending_mask[i] && enable_mask[i] &&
                    ((i + 1) > threshold_value)) begin
                    select_claim = i + 4'd1;
                end
            end
        end
    endfunction

    assign ready = valid;
    assign claim_id = select_claim(pending, enable, threshold);
    assign irq_external = (claim_id != 4'd0);

    always_comb begin
        rdata = 32'd0;
        case (addr[5:2])
            4'h0: rdata = {24'd0, pending};
            4'h1: rdata = {24'd0, enable};
            4'h2: rdata = {29'd0, threshold};
            4'h3: rdata = {28'd0, claim_id};
            4'h4: rdata = {24'd0, source_irq};
            default: rdata = 32'd0;
        endcase
    end

    always_comb begin
        pending_next = pending | source_irq;
        if (valid && we && ready) begin
            case (addr[5:2])
                4'h0: pending_next = pending_next | wdata[NUM_SOURCES-1:0];
                4'h3: begin
                    if (wdata[3:0] != 4'd0 && wdata[3:0] <= NUM_SOURCES) begin
                        pending_next[wdata[3:0]-1] = 1'b0;
                    end
                end
                default: begin
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= '0;
            enable <= '0;
            threshold <= 3'd0;
        end else begin
            pending <= pending_next;

            if (valid && we && ready) begin
                case (addr[5:2])
                    4'h1: enable <= wdata[NUM_SOURCES-1:0];
                    4'h2: threshold <= wdata[2:0];
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
