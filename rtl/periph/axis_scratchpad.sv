module axis_scratchpad #(
    parameter int WORDS = 4096
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        cpu_valid,
    input  logic        cpu_we,
    input  logic [3:0]  cpu_wstrb,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    output logic        cpu_ready,
    output logic [31:0] cpu_rdata,

    input  logic        mm2s_start,
    input  logic [31:0] mm2s_local_addr,
    input  logic [31:0] mm2s_length_bytes,
    output logic        mm2s_ready,
    output logic        mm2s_done,
    output logic        mm2s_error,
    input  logic [31:0] s_axis_mm2s_tdata,
    input  logic [3:0]  s_axis_mm2s_tkeep,
    input  logic        s_axis_mm2s_tlast,
    input  logic        s_axis_mm2s_tvalid,
    output logic        s_axis_mm2s_tready,

    input  logic        s2mm_start,
    input  logic [31:0] s2mm_local_addr,
    input  logic [31:0] s2mm_length_bytes,
    output logic        s2mm_ready,
    output logic        s2mm_done,
    output logic        s2mm_error,
    output logic [31:0] m_axis_s2mm_tdata,
    output logic [3:0]  m_axis_s2mm_tkeep,
    output logic        m_axis_s2mm_tlast,
    output logic        m_axis_s2mm_tvalid,
    input  logic        m_axis_s2mm_tready
);
    localparam int ADDR_BITS = $clog2(WORDS);

    typedef enum logic [1:0] {
        RD_IDLE,
        RD_PRIME,
        RD_STREAM
    } rd_state_t;

    logic [31:0] rx_mem [0:WORDS-1];
    logic [31:0] tx_mem [0:WORDS-1];
    integer      init_i;

    logic        mm2s_active = 1'b0;
    logic [31:0] mm2s_bytes_left = 32'd0;
    logic [ADDR_BITS-1:0] mm2s_word_addr = '0;

    rd_state_t   rd_state = RD_IDLE;
    logic [31:0] s2mm_bytes_left = 32'd0;
    logic [ADDR_BITS-1:0] s2mm_word_addr = '0;

    wire cpu_tx_select = cpu_addr[16];

    initial begin
        for (init_i = 0; init_i < WORDS; init_i = init_i + 1) begin
            rx_mem[init_i] = 32'd0;
            tx_mem[init_i] = 32'd0;
        end
    end

    assign cpu_ready = cpu_valid;
    assign cpu_rdata = cpu_tx_select ? tx_mem[cpu_addr[ADDR_BITS+1:2]] :
                                       rx_mem[cpu_addr[ADDR_BITS+1:2]];
    assign mm2s_ready = !mm2s_active && rd_state == RD_IDLE;
    assign s2mm_ready = rd_state == RD_IDLE && !mm2s_active;
    assign s_axis_mm2s_tready = mm2s_active;
    assign m_axis_s2mm_tvalid = (rd_state == RD_STREAM);
    assign m_axis_s2mm_tkeep = (s2mm_bytes_left >= 32'd4) ? 4'b1111 :
                               (s2mm_bytes_left == 32'd3) ? 4'b0111 :
                               (s2mm_bytes_left == 32'd2) ? 4'b0011 :
                               (s2mm_bytes_left == 32'd1) ? 4'b0001 : 4'b0000;
    assign m_axis_s2mm_tlast = (rd_state == RD_STREAM) && s2mm_bytes_left <= 32'd4;

    function automatic logic [2:0] keep_count(input logic [3:0] keep);
        begin
            keep_count = {2'd0, keep[0]} + {2'd0, keep[1]} +
                         {2'd0, keep[2]} + {2'd0, keep[3]};
        end
    endfunction

    always_ff @(posedge clk) begin
        if (cpu_valid && cpu_we && cpu_tx_select) begin
            if (cpu_wstrb[0]) tx_mem[cpu_addr[ADDR_BITS+1:2]][7:0]   <= cpu_wdata[7:0];
            if (cpu_wstrb[1]) tx_mem[cpu_addr[ADDR_BITS+1:2]][15:8]  <= cpu_wdata[15:8];
            if (cpu_wstrb[2]) tx_mem[cpu_addr[ADDR_BITS+1:2]][23:16] <= cpu_wdata[23:16];
            if (cpu_wstrb[3]) tx_mem[cpu_addr[ADDR_BITS+1:2]][31:24] <= cpu_wdata[31:24];
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mm2s_active <= 1'b0;
            mm2s_bytes_left <= 32'd0;
            mm2s_word_addr <= '0;
            mm2s_done <= 1'b0;
            mm2s_error <= 1'b0;
            rd_state <= RD_IDLE;
            s2mm_bytes_left <= 32'd0;
            s2mm_word_addr <= '0;
            s2mm_done <= 1'b0;
            s2mm_error <= 1'b0;
            m_axis_s2mm_tdata <= 32'd0;
        end else begin
            if (mm2s_start && !mm2s_active && rd_state == RD_IDLE) begin
                mm2s_active <= 1'b1;
                mm2s_bytes_left <= mm2s_length_bytes;
                mm2s_word_addr <= mm2s_local_addr[ADDR_BITS+1:2];
                mm2s_done <= 1'b0;
                mm2s_error <= (mm2s_length_bytes == 32'd0);
            end else if (mm2s_active && s_axis_mm2s_tvalid && s_axis_mm2s_tready) begin
                if (s_axis_mm2s_tkeep[0]) rx_mem[mm2s_word_addr][7:0]   <= s_axis_mm2s_tdata[7:0];
                if (s_axis_mm2s_tkeep[1]) rx_mem[mm2s_word_addr][15:8]  <= s_axis_mm2s_tdata[15:8];
                if (s_axis_mm2s_tkeep[2]) rx_mem[mm2s_word_addr][23:16] <= s_axis_mm2s_tdata[23:16];
                if (s_axis_mm2s_tkeep[3]) rx_mem[mm2s_word_addr][31:24] <= s_axis_mm2s_tdata[31:24];

                if ({29'd0, keep_count(s_axis_mm2s_tkeep)} >= mm2s_bytes_left || s_axis_mm2s_tlast) begin
                    mm2s_active <= 1'b0;
                    mm2s_done <= 1'b1;
                    if ({29'd0, keep_count(s_axis_mm2s_tkeep)} != mm2s_bytes_left && s_axis_mm2s_tlast) begin
                        mm2s_error <= 1'b1;
                    end
                end else begin
                    mm2s_bytes_left <= mm2s_bytes_left - {29'd0, keep_count(s_axis_mm2s_tkeep)};
                    mm2s_word_addr <= mm2s_word_addr + {{(ADDR_BITS-1){1'b0}}, 1'b1};
                end
            end

            case (rd_state)
                RD_IDLE: begin
                    if (s2mm_start && !mm2s_active) begin
                        s2mm_word_addr <= s2mm_local_addr[ADDR_BITS+1:2];
                        s2mm_bytes_left <= s2mm_length_bytes;
                        s2mm_done <= 1'b0;
                        s2mm_error <= (s2mm_length_bytes == 32'd0);
                        if (s2mm_length_bytes == 32'd0) begin
                            rd_state <= RD_IDLE;
                        end else begin
                            rd_state <= RD_PRIME;
                        end
                    end
                end
                RD_PRIME: begin
                    m_axis_s2mm_tdata <= tx_mem[s2mm_word_addr];
                    rd_state <= RD_STREAM;
                end
                RD_STREAM: begin
                    if (m_axis_s2mm_tready) begin
                        if (s2mm_bytes_left <= 32'd4) begin
                            s2mm_done <= 1'b1;
                            rd_state <= RD_IDLE;
                        end else begin
                            s2mm_bytes_left <= s2mm_bytes_left - 32'd4;
                            s2mm_word_addr <= s2mm_word_addr + {{(ADDR_BITS-1){1'b0}}, 1'b1};
                            m_axis_s2mm_tdata <= tx_mem[s2mm_word_addr + {{(ADDR_BITS-1){1'b0}}, 1'b1}];
                        end
                    end
                end
                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end
endmodule
