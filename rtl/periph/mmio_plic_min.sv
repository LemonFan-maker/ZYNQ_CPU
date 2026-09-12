module mmio_plic_min #(
    parameter int NUM_SOURCES = 1
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

    input  logic [NUM_SOURCES-1:0] source_irq,
    output logic                   irq_external
);
    localparam logic [31:0] PRIORITY_BASE = 32'h0000_0000;
    localparam logic [31:0] PENDING_BASE  = 32'h0000_1000;
    localparam logic [31:0] ENABLE_BASE   = 32'h0000_2000;
    localparam logic [31:0] CONTEXT_BASE  = 32'h0020_0000;

	logic [NUM_SOURCES-1:0] pending_q;
	logic [NUM_SOURCES-1:0] enable_q;
	logic [NUM_SOURCES-1:0] in_flight_q;
	logic [2:0]             priority_q [0:NUM_SOURCES-1];
	logic [2:0]             threshold_q;
	logic [31:0]            claim_id;
    logic [31:0]            read_word;
    logic [31:0]            merged_word;

    assign ready = valid;

    function automatic logic [31:0] merge32(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  byte_strobe
    );
        begin
            merge32 = old_value;
            for (int i = 0; i < 4; i++) begin
                if (byte_strobe[i]) begin
                    merge32[i * 8 +: 8] = new_value[i * 8 +: 8];
                end
            end
        end
    endfunction

    always_comb begin
        claim_id = 32'd0;
        for (int i = NUM_SOURCES - 1; i >= 0; i--) begin
            if (claim_id == 32'd0 && pending_q[i] && enable_q[i] &&
                priority_q[i] > threshold_q) begin
                claim_id = i + 32'd1;
            end
        end
    end

    assign irq_external = (claim_id != 32'd0);

    always_comb begin
        read_word = 32'd0;
        if (addr >= PRIORITY_BASE && addr < PRIORITY_BASE + ((NUM_SOURCES + 1) * 4)) begin
            for (int i = 0; i < NUM_SOURCES; i++) begin
                if (addr == PRIORITY_BASE + ((i + 1) * 4)) begin
                    read_word = {29'd0, priority_q[i]};
                end
            end
        end else if (addr == PENDING_BASE) begin
            read_word = {{(31 - NUM_SOURCES){1'b0}}, pending_q, 1'b0};
        end else if (addr == ENABLE_BASE) begin
            read_word = {{(31 - NUM_SOURCES){1'b0}}, enable_q, 1'b0};
        end else if (addr == CONTEXT_BASE) begin
            read_word = {29'd0, threshold_q};
        end else if (addr == CONTEXT_BASE + 32'h0000_0004) begin
            read_word = claim_id;
        end
        rdata = read_word;
    end

    always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			pending_q <= '0;
			enable_q <= '0;
			in_flight_q <= '0;
			threshold_q <= 3'd0;
			for (int i = 0; i < NUM_SOURCES; i++) begin
				priority_q[i] <= 3'd0;
			end
		end else begin
			pending_q <= pending_q | (source_irq & ~in_flight_q);

			if (valid && ready) begin
				if (!we && addr == CONTEXT_BASE + 32'h0000_0004 && claim_id != 32'd0 &&
				    claim_id <= NUM_SOURCES) begin
					pending_q[claim_id - 1] <= 1'b0;
					in_flight_q[claim_id - 1] <= 1'b1;
				end

				if (we) begin
                    if (addr >= PRIORITY_BASE && addr < PRIORITY_BASE + ((NUM_SOURCES + 1) * 4)) begin
                        for (int i = 0; i < NUM_SOURCES; i++) begin
                            if (addr == PRIORITY_BASE + ((i + 1) * 4)) begin
                                merged_word = merge32({29'd0, priority_q[i]}, wdata, wstrb);
                                priority_q[i] <= merged_word[2:0];
                            end
                        end
                    end else if (addr == PENDING_BASE) begin
                        merged_word = merge32({{(31 - NUM_SOURCES){1'b0}}, pending_q, 1'b0},
                                              wdata, wstrb);
                        pending_q <= pending_q | merged_word[NUM_SOURCES:1];
                    end else if (addr == ENABLE_BASE) begin
                        merged_word = merge32({{(31 - NUM_SOURCES){1'b0}}, enable_q, 1'b0},
                                              wdata, wstrb);
                        enable_q <= merged_word[NUM_SOURCES:1];
					end else if (addr == CONTEXT_BASE) begin
						merged_word = merge32({29'd0, threshold_q}, wdata, wstrb);
						threshold_q <= merged_word[2:0];
					end else if (addr == CONTEXT_BASE + 32'h0000_0004) begin
						merged_word = merge32(32'd0, wdata, wstrb);
						for (int i = 0; i < NUM_SOURCES; i++) begin
							if (merged_word == i + 32'd1) begin
								in_flight_q[i] <= 1'b0;
							end
						end
					end
				end
			end
        end
    end
endmodule
