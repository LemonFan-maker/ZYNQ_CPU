module simple_ram64 #(
    parameter int WORDS = 1024
) (
    input  logic        clk,

    input  logic        imem_valid,
    input  logic [31:0] imem_addr,
    output logic        imem_ready,
    output logic [31:0] imem_rdata,

    input  logic        dmem_valid,
    input  logic        dmem_we,
    input  logic [7:0]  dmem_wstrb,
    input  logic [31:0] dmem_addr,
    input  logic [63:0] dmem_wdata,
    output logic        dmem_ready,
    output logic [63:0] dmem_rdata
);
    localparam int ADDR_BITS = $clog2(WORDS);

    (* ram_style = "block" *) logic [63:0] mem [0:WORDS-1];
    logic [63:0] imem_rword;
    logic [63:0] dmem_rword;
    logic        imem_upper;
    logic        imem_pending = 1'b0;
    logic        dmem_pending = 1'b0;
    wire [ADDR_BITS-1:0] imem_word_addr = imem_addr[ADDR_BITS+2:3];
    wire [ADDR_BITS-1:0] dmem_word_addr = dmem_addr[ADDR_BITS+2:3];
    integer      init_i;

    initial begin
        for (init_i = 0; init_i < WORDS; init_i = init_i + 1) begin
            mem[init_i] = 64'd0;
        end
    end

    assign imem_ready = imem_pending;
    assign dmem_ready = dmem_pending;
    assign imem_rdata = imem_upper ? imem_rword[63:32] : imem_rword[31:0];
    assign dmem_rdata = dmem_rword;

    always_ff @(posedge clk) begin
        if (imem_pending) begin
            imem_pending <= 1'b0;
        end else if (imem_valid) begin
            imem_rword <= mem[imem_word_addr];
            imem_upper <= imem_addr[2];
            imem_pending <= 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (dmem_pending) begin
            dmem_pending <= 1'b0;
        end else if (dmem_valid) begin
            dmem_rword <= mem[dmem_word_addr];
            if (dmem_we) begin
                if (dmem_wstrb[0]) mem[dmem_word_addr][7:0]   <= dmem_wdata[7:0];
                if (dmem_wstrb[1]) mem[dmem_word_addr][15:8]  <= dmem_wdata[15:8];
                if (dmem_wstrb[2]) mem[dmem_word_addr][23:16] <= dmem_wdata[23:16];
                if (dmem_wstrb[3]) mem[dmem_word_addr][31:24] <= dmem_wdata[31:24];
                if (dmem_wstrb[4]) mem[dmem_word_addr][39:32] <= dmem_wdata[39:32];
                if (dmem_wstrb[5]) mem[dmem_word_addr][47:40] <= dmem_wdata[47:40];
                if (dmem_wstrb[6]) mem[dmem_word_addr][55:48] <= dmem_wdata[55:48];
                if (dmem_wstrb[7]) mem[dmem_word_addr][63:56] <= dmem_wdata[63:56];
            end
            dmem_pending <= 1'b1;
        end
    end
endmodule
