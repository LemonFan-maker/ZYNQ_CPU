module zx64_soc_bd #(
    parameter ENABLE_FPU = 1'b1
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire        uart_tx,
    output wire        display_enable,
    output wire        display_test_pattern_enable,
    output wire        display_text_enable,
    output wire        display_text_clear,
    output wire [1:0]  display_mode,
    output wire [31:0] display_bg_color,
    output wire        display_text_we,
    output wire [11:0] display_text_word_addr,
    output wire [31:0] display_text_wdata,
    output wire [3:0]  display_text_wstrb,
    output wire        display_attr_we,
    output wire [10:0] display_attr_word_addr,
    output wire [31:0] display_attr_wdata,
    output wire [3:0]  display_attr_wstrb,
    output wire        display_font_we,
    output wire [8:0]  display_font_word_addr,
    output wire [31:0] display_font_wdata,
    output wire [3:0]  display_font_wstrb,

    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [15:0] S_AXI_AWADDR,
    input  wire [2:0]  S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [15:0] S_AXI_ARADDR,
    input  wire [2:0]  S_AXI_ARPROT,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output reg  [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    output wire        dm_mm2s_cmd_valid,
    input  wire        dm_mm2s_cmd_ready,
    output wire [71:0] dm_mm2s_cmd_data,
    input  wire        dm_mm2s_sts_valid,
    output wire        dm_mm2s_sts_ready,
    input  wire [7:0]  dm_mm2s_sts_data,

    output wire        dm_s2mm_cmd_valid,
    input  wire        dm_s2mm_cmd_ready,
    output wire [71:0] dm_s2mm_cmd_data,
    input  wire        dm_s2mm_sts_valid,
    output wire        dm_s2mm_sts_ready,
    input  wire [7:0]  dm_s2mm_sts_data,

    input  wire [31:0] dm_m_axis_mm2s_tdata,
    input  wire [3:0]  dm_m_axis_mm2s_tkeep,
    input  wire        dm_m_axis_mm2s_tlast,
    input  wire        dm_m_axis_mm2s_tvalid,
    output wire        dm_m_axis_mm2s_tready,

    output wire [31:0] dm_s_axis_s2mm_tdata,
    output wire [3:0]  dm_s_axis_s2mm_tkeep,
    output wire        dm_s_axis_s2mm_tlast,
    output wire        dm_s_axis_s2mm_tvalid,
    input  wire        dm_s_axis_s2mm_tready,

    output wire [3:0]  M_AXI_DDR_AWID,
    output wire [31:0] M_AXI_DDR_AWADDR,
    output wire [7:0]  M_AXI_DDR_AWLEN,
    output wire [2:0]  M_AXI_DDR_AWSIZE,
    output wire [1:0]  M_AXI_DDR_AWBURST,
    output wire        M_AXI_DDR_AWLOCK,
    output wire [3:0]  M_AXI_DDR_AWCACHE,
    output wire [2:0]  M_AXI_DDR_AWPROT,
    output wire [3:0]  M_AXI_DDR_AWQOS,
    output wire        M_AXI_DDR_AWVALID,
    input  wire        M_AXI_DDR_AWREADY,
    output wire [31:0] M_AXI_DDR_WDATA,
    output wire [3:0]  M_AXI_DDR_WSTRB,
    output wire        M_AXI_DDR_WLAST,
    output wire        M_AXI_DDR_WVALID,
    input  wire        M_AXI_DDR_WREADY,
    input  wire [3:0]  M_AXI_DDR_BID,
    input  wire [1:0]  M_AXI_DDR_BRESP,
    input  wire        M_AXI_DDR_BVALID,
    output wire        M_AXI_DDR_BREADY,
    output wire [3:0]  M_AXI_DDR_ARID,
    output wire [31:0] M_AXI_DDR_ARADDR,
    output wire [7:0]  M_AXI_DDR_ARLEN,
    output wire [2:0]  M_AXI_DDR_ARSIZE,
    output wire [1:0]  M_AXI_DDR_ARBURST,
    output wire        M_AXI_DDR_ARLOCK,
    output wire [3:0]  M_AXI_DDR_ARCACHE,
    output wire [2:0]  M_AXI_DDR_ARPROT,
    output wire [3:0]  M_AXI_DDR_ARQOS,
    output wire        M_AXI_DDR_ARVALID,
    input  wire        M_AXI_DDR_ARREADY,
    input  wire [3:0]  M_AXI_DDR_RID,
    input  wire [31:0] M_AXI_DDR_RDATA,
    input  wire [1:0]  M_AXI_DDR_RRESP,
    input  wire        M_AXI_DDR_RLAST,
    input  wire        M_AXI_DDR_RVALID,
    output wire        M_AXI_DDR_RREADY
);
    localparam integer BRAM_WORDS = 4096;
    localparam integer SCRATCH_WORDS = 256;

    localparam AXI_IDLE  = 2'd0;
    localparam AXI_WRITE = 2'd1;
    localparam AXI_READ  = 2'd2;

    reg [1:0]  axi_state;
    reg [15:0] awaddr_q;
    reg [15:0] araddr_q;
    reg [31:0] wdata_q;
    reg [3:0]  wstrb_q;
    reg        aw_seen;
    reg        w_seen;

    reg        soft_reset_q;
    reg [31:0] reset_vector_q;
    reg [63:0] virtio_capacity_sectors_q;
    reg        virtio_backend_irq_pulse_q;
    reg        virtio_notify_ack_pulse_q;
    reg        virtio_input_backend_irq_pulse_q;
    reg        virtio_input_notify_ack_pulse_q;

    wire        core_halted;
    wire        core_illegal;
    wire [31:0] dbg_core_state;
    wire [63:0] dbg_pc;
    wire [31:0] dbg_instr;
    wire [31:0] dbg_icache_hits;
    wire [31:0] dbg_icache_misses;
    wire [31:0] dbg_dcache_hits;
    wire [31:0] dbg_dcache_misses;
    wire [31:0] dbg_cache_invalidates;
    wire        virtio_notify_pending;
    wire [15:0] virtio_notify_queue;
    wire [31:0] virtio_notify_count;
    wire [31:0] virtio_queue_num;
    wire        virtio_queue_ready;
    wire [63:0] virtio_queue_desc_addr;
    wire [63:0] virtio_queue_avail_addr;
    wire [63:0] virtio_queue_used_addr;
    wire        virtio_irq_pending;
    wire [7:0]  virtio_device_status;
    wire        virtio_input_notify_pending;
    wire [15:0] virtio_input_notify_queue;
    wire [31:0] virtio_input_notify_count;
    wire        virtio_input_irq_pending;
    wire [7:0]  virtio_input_device_status;
    wire [31:0] virtio_input_event_queue_num;
    wire        virtio_input_event_queue_ready;
    wire [63:0] virtio_input_event_queue_desc_addr;
    wire [63:0] virtio_input_event_queue_avail_addr;
    wire [63:0] virtio_input_event_queue_used_addr;
    wire [31:0] virtio_input_status_queue_num;
    wire        virtio_input_status_queue_ready;
    wire [63:0] virtio_input_status_queue_desc_addr;
    wire [63:0] virtio_input_status_queue_avail_addr;
    wire [63:0] virtio_input_status_queue_used_addr;

    wire        host_valid;
    wire        host_we;
    wire [31:0] host_addr;
    wire [31:0] host_wdata;
    wire [3:0]  host_wstrb;
    wire        host_ready;
    wire [31:0] host_rdata;

    wire [15:0] active_axi_addr;
    wire        active_ctrl;
    wire        host_xfer_ready;

    assign S_AXI_AWREADY = (axi_state == AXI_IDLE) && !aw_seen && !S_AXI_BVALID && !S_AXI_RVALID;
    assign S_AXI_WREADY  = (axi_state == AXI_IDLE) && !w_seen && !S_AXI_BVALID && !S_AXI_RVALID;
    assign S_AXI_ARREADY = (axi_state == AXI_IDLE) && !aw_seen && !w_seen && !S_AXI_BVALID && !S_AXI_RVALID;
    assign S_AXI_BRESP = 2'b00;
    assign S_AXI_RRESP = 2'b00;

    assign active_axi_addr = (axi_state == AXI_READ) ? araddr_q : awaddr_q;
    assign active_ctrl = (active_axi_addr[15:12] == 4'h7);
    assign host_valid = ((axi_state == AXI_WRITE) || (axi_state == AXI_READ)) && !active_ctrl;
    assign host_we = (axi_state == AXI_WRITE);
    assign host_wdata = wdata_q;
    assign host_wstrb = wstrb_q;
    assign host_addr = translate_addr(active_axi_addr);
    assign host_xfer_ready = active_ctrl ? 1'b1 : host_ready;

    assign display_enable = 1'b0;
    assign display_test_pattern_enable = 1'b0;
    assign display_text_enable = 1'b0;
    assign display_text_clear = 1'b0;
    assign display_mode = 2'd0;
    assign display_bg_color = 32'd0;
    assign display_text_we = 1'b0;
    assign display_text_word_addr = 12'd0;
    assign display_text_wdata = 32'd0;
    assign display_text_wstrb = 4'd0;
    assign display_attr_we = 1'b0;
    assign display_attr_word_addr = 11'd0;
    assign display_attr_wdata = 32'd0;
    assign display_attr_wstrb = 4'd0;
    assign display_font_we = 1'b0;
    assign display_font_word_addr = 9'd0;
    assign display_font_wdata = 32'd0;
    assign display_font_wstrb = 4'd0;

    assign dm_mm2s_cmd_valid = 1'b0;
    assign dm_mm2s_cmd_data = 72'd0;
    assign dm_mm2s_sts_ready = 1'b1;
    assign dm_s2mm_cmd_valid = 1'b0;
    assign dm_s2mm_cmd_data = 72'd0;
    assign dm_s2mm_sts_ready = 1'b1;
    assign dm_m_axis_mm2s_tready = 1'b1;
    assign dm_s_axis_s2mm_tdata = 32'd0;
    assign dm_s_axis_s2mm_tkeep = 4'd0;
    assign dm_s_axis_s2mm_tlast = 1'b0;
    assign dm_s_axis_s2mm_tvalid = 1'b0;

    function [31:0] translate_addr;
        input [15:0] axi_addr;
        begin
            case (axi_addr[15:12])
                4'h1: translate_addr = 32'h2000_0000 + {20'd0, axi_addr[11:0]};
                4'h2: translate_addr = 32'h2001_0000 + {20'd0, axi_addr[11:0]};
                4'h3,
                4'h4,
                4'h5,
                4'h6: translate_addr = {16'd0, axi_addr - 16'h3000};
                default: translate_addr = 32'hffff_0000 + {16'd0, axi_addr};
            endcase
        end
    endfunction

    function [31:0] ctrl_read_data;
        input [15:0] axi_addr;
        begin
            case (axi_addr[11:0])
                12'h000: ctrl_read_data = {31'd0, soft_reset_q};
                12'h004: ctrl_read_data = {30'd0, core_illegal, core_halted};
                12'h008: ctrl_read_data = BRAM_WORDS[31:0];
                12'h00c: ctrl_read_data = SCRATCH_WORDS[31:0];
                12'h010: ctrl_read_data = reset_vector_q;
                12'h020: ctrl_read_data = dbg_core_state;
                12'h024: ctrl_read_data = dbg_pc[31:0];
                12'h028: ctrl_read_data = dbg_pc[63:32];
                12'h02c: ctrl_read_data = dbg_instr;
                12'h0ac: ctrl_read_data = dbg_icache_hits;
                12'h0b0: ctrl_read_data = dbg_icache_misses;
                12'h0b4: ctrl_read_data = dbg_dcache_hits;
                12'h0b8: ctrl_read_data = dbg_dcache_misses;
                12'h0e0: ctrl_read_data = dbg_cache_invalidates;
                12'h100: ctrl_read_data = {22'd0, virtio_device_status,
                                            virtio_irq_pending, virtio_notify_pending};
                12'h104: ctrl_read_data = virtio_notify_count;
                12'h108: ctrl_read_data = {16'd0, virtio_notify_queue};
                12'h10c: ctrl_read_data = virtio_queue_num;
                12'h110: ctrl_read_data = {31'd0, virtio_queue_ready};
                12'h114: ctrl_read_data = virtio_queue_desc_addr[31:0];
                12'h118: ctrl_read_data = virtio_queue_desc_addr[63:32];
                12'h11c: ctrl_read_data = virtio_queue_avail_addr[31:0];
                12'h120: ctrl_read_data = virtio_queue_avail_addr[63:32];
                12'h124: ctrl_read_data = virtio_queue_used_addr[31:0];
                12'h128: ctrl_read_data = virtio_queue_used_addr[63:32];
                12'h12c: ctrl_read_data = virtio_capacity_sectors_q[31:0];
                12'h130: ctrl_read_data = virtio_capacity_sectors_q[63:32];
                12'h140: ctrl_read_data = {22'd0, virtio_input_device_status,
                                            virtio_input_irq_pending,
                                            virtio_input_notify_pending};
                12'h144: ctrl_read_data = virtio_input_notify_count;
                12'h148: ctrl_read_data = {16'd0, virtio_input_notify_queue};
                12'h150: ctrl_read_data = virtio_input_event_queue_num;
                12'h154: ctrl_read_data = {31'd0, virtio_input_event_queue_ready};
                12'h158: ctrl_read_data = virtio_input_event_queue_desc_addr[31:0];
                12'h15c: ctrl_read_data = virtio_input_event_queue_desc_addr[63:32];
                12'h160: ctrl_read_data = virtio_input_event_queue_avail_addr[31:0];
                12'h164: ctrl_read_data = virtio_input_event_queue_avail_addr[63:32];
                12'h168: ctrl_read_data = virtio_input_event_queue_used_addr[31:0];
                12'h16c: ctrl_read_data = virtio_input_event_queue_used_addr[63:32];
                12'h170: ctrl_read_data = virtio_input_status_queue_num;
                12'h174: ctrl_read_data = {31'd0, virtio_input_status_queue_ready};
                12'h178: ctrl_read_data = virtio_input_status_queue_desc_addr[31:0];
                12'h17c: ctrl_read_data = virtio_input_status_queue_desc_addr[63:32];
                12'h180: ctrl_read_data = virtio_input_status_queue_avail_addr[31:0];
                12'h184: ctrl_read_data = virtio_input_status_queue_avail_addr[63:32];
                12'h188: ctrl_read_data = virtio_input_status_queue_used_addr[31:0];
                12'h18c: ctrl_read_data = virtio_input_status_queue_used_addr[63:32];
                default: ctrl_read_data = 32'd0;
            endcase
        end
    endfunction

    task write_ctrl_reg;
        input [15:0] axi_addr;
        input [31:0] data;
        input [3:0]  strb;
        reg [31:0] merged;
        begin
            case (axi_addr[11:0])
                12'h000: begin
                    merged = {31'd0, soft_reset_q};
                    if (strb[0]) merged[7:0] = data[7:0];
                    soft_reset_q <= merged[0];
                end
                12'h010: begin
                    merged = reset_vector_q;
                    if (strb[0]) merged[7:0] = data[7:0];
                    if (strb[1]) merged[15:8] = data[15:8];
                    if (strb[2]) merged[23:16] = data[23:16];
                    if (strb[3]) merged[31:24] = data[31:24];
                    reset_vector_q <= merged;
                end
                12'h12c: begin
                    merged = virtio_capacity_sectors_q[31:0];
                    if (strb[0]) merged[7:0] = data[7:0];
                    if (strb[1]) merged[15:8] = data[15:8];
                    if (strb[2]) merged[23:16] = data[23:16];
                    if (strb[3]) merged[31:24] = data[31:24];
                    virtio_capacity_sectors_q[31:0] <= merged;
                end
                12'h130: begin
                    merged = virtio_capacity_sectors_q[63:32];
                    if (strb[0]) merged[7:0] = data[7:0];
                    if (strb[1]) merged[15:8] = data[15:8];
                    if (strb[2]) merged[23:16] = data[23:16];
                    if (strb[3]) merged[31:24] = data[31:24];
                    virtio_capacity_sectors_q[63:32] <= merged;
                end
                12'h134: begin
                    if (strb[0]) begin
                        virtio_notify_ack_pulse_q <= data[0];
                        virtio_backend_irq_pulse_q <= data[1];
                    end
                end
                12'h14c: begin
                    if (strb[0]) begin
                        virtio_input_notify_ack_pulse_q <= data[0];
                        virtio_input_backend_irq_pulse_q <= data[1];
                    end
                end
                default: begin
                end
            endcase
        end
    endtask

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            axi_state <= AXI_IDLE;
            awaddr_q <= 16'd0;
            araddr_q <= 16'd0;
            wdata_q <= 32'd0;
            wstrb_q <= 4'd0;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
            S_AXI_BVALID <= 1'b0;
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA <= 32'd0;
            soft_reset_q <= 1'b1;
            reset_vector_q <= 32'd0;
            virtio_capacity_sectors_q <= 64'd0;
            virtio_backend_irq_pulse_q <= 1'b0;
            virtio_notify_ack_pulse_q <= 1'b0;
            virtio_input_backend_irq_pulse_q <= 1'b0;
            virtio_input_notify_ack_pulse_q <= 1'b0;
        end else begin
            virtio_backend_irq_pulse_q <= 1'b0;
            virtio_notify_ack_pulse_q <= 1'b0;
            virtio_input_backend_irq_pulse_q <= 1'b0;
            virtio_input_notify_ack_pulse_q <= 1'b0;

            if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
            if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end

            if (S_AXI_AWREADY && S_AXI_AWVALID) begin
                awaddr_q <= S_AXI_AWADDR;
                aw_seen <= 1'b1;
            end
            if (S_AXI_WREADY && S_AXI_WVALID) begin
                wdata_q <= S_AXI_WDATA;
                wstrb_q <= S_AXI_WSTRB;
                w_seen <= 1'b1;
            end
            if (S_AXI_ARREADY && S_AXI_ARVALID) begin
                araddr_q <= S_AXI_ARADDR;
                axi_state <= AXI_READ;
            end else if (axi_state == AXI_IDLE && (aw_seen || S_AXI_AWVALID) && (w_seen || S_AXI_WVALID)) begin
                if (!aw_seen && S_AXI_AWVALID) begin
                    awaddr_q <= S_AXI_AWADDR;
                end
                if (!w_seen && S_AXI_WVALID) begin
                    wdata_q <= S_AXI_WDATA;
                    wstrb_q <= S_AXI_WSTRB;
                end
                axi_state <= AXI_WRITE;
            end else if (axi_state == AXI_WRITE && host_xfer_ready) begin
                if (active_ctrl) begin
                    write_ctrl_reg(awaddr_q, wdata_q, wstrb_q);
                end
                axi_state <= AXI_IDLE;
                aw_seen <= 1'b0;
                w_seen <= 1'b0;
                S_AXI_BVALID <= 1'b1;
            end else if (axi_state == AXI_READ && host_xfer_ready) begin
                axi_state <= AXI_IDLE;
                S_AXI_RDATA <= active_ctrl ? ctrl_read_data(araddr_q) : host_rdata;
                S_AXI_RVALID <= 1'b1;
            end
        end
    end

    zx64_soc #(
        .BRAM_WORDS(BRAM_WORDS),
        .SCRATCH_WORDS(SCRATCH_WORDS),
        .CLK_HZ(75_000_000),
        .USE_CORE5(1'b1),
        .ENABLE_FPU(ENABLE_FPU)
    ) u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(soft_reset_q),
        .reset_vector({32'd0, reset_vector_q}),
        .irq_external_i(1'b0),
        .virtio_blk_capacity_sectors(virtio_capacity_sectors_q),
        .virtio_blk_backend_irq(virtio_backend_irq_pulse_q),
        .virtio_blk_notify_ack(virtio_notify_ack_pulse_q),
        .virtio_blk_notify_pending(virtio_notify_pending),
        .virtio_blk_notify_queue(virtio_notify_queue),
        .virtio_blk_notify_count(virtio_notify_count),
        .virtio_blk_queue_num(virtio_queue_num),
        .virtio_blk_queue_ready(virtio_queue_ready),
        .virtio_blk_queue_desc_addr(virtio_queue_desc_addr),
        .virtio_blk_queue_avail_addr(virtio_queue_avail_addr),
        .virtio_blk_queue_used_addr(virtio_queue_used_addr),
        .virtio_blk_irq_pending(virtio_irq_pending),
        .virtio_blk_device_status(virtio_device_status),
        .virtio_input_backend_irq(virtio_input_backend_irq_pulse_q),
        .virtio_input_notify_ack(virtio_input_notify_ack_pulse_q),
        .virtio_input_notify_pending(virtio_input_notify_pending),
        .virtio_input_notify_queue(virtio_input_notify_queue),
        .virtio_input_notify_count(virtio_input_notify_count),
        .virtio_input_irq_pending(virtio_input_irq_pending),
        .virtio_input_device_status(virtio_input_device_status),
        .virtio_input_event_queue_num(virtio_input_event_queue_num),
        .virtio_input_event_queue_ready(virtio_input_event_queue_ready),
        .virtio_input_event_queue_desc_addr(virtio_input_event_queue_desc_addr),
        .virtio_input_event_queue_avail_addr(virtio_input_event_queue_avail_addr),
        .virtio_input_event_queue_used_addr(virtio_input_event_queue_used_addr),
        .virtio_input_status_queue_num(virtio_input_status_queue_num),
        .virtio_input_status_queue_ready(virtio_input_status_queue_ready),
        .virtio_input_status_queue_desc_addr(virtio_input_status_queue_desc_addr),
        .virtio_input_status_queue_avail_addr(virtio_input_status_queue_avail_addr),
        .virtio_input_status_queue_used_addr(virtio_input_status_queue_used_addr),
        .uart_tx(uart_tx),
        .core_halted(core_halted),
        .core_illegal(core_illegal),
        .dbg_core_state(dbg_core_state),
        .dbg_pc(dbg_pc),
        .dbg_instr(dbg_instr),
        .dbg_icache_hits(dbg_icache_hits),
        .dbg_icache_misses(dbg_icache_misses),
        .dbg_dcache_hits(dbg_dcache_hits),
        .dbg_dcache_misses(dbg_dcache_misses),
        .dbg_cache_invalidates(dbg_cache_invalidates),
        .host_valid(host_valid),
        .host_we(host_we),
        .host_wstrb(host_wstrb),
        .host_addr(host_addr),
        .host_wdata(host_wdata),
        .host_ready(host_ready),
        .host_rdata(host_rdata),
        .M_AXI_DDR_AWID(M_AXI_DDR_AWID),
        .M_AXI_DDR_AWADDR(M_AXI_DDR_AWADDR),
        .M_AXI_DDR_AWLEN(M_AXI_DDR_AWLEN),
        .M_AXI_DDR_AWSIZE(M_AXI_DDR_AWSIZE),
        .M_AXI_DDR_AWBURST(M_AXI_DDR_AWBURST),
        .M_AXI_DDR_AWLOCK(M_AXI_DDR_AWLOCK),
        .M_AXI_DDR_AWCACHE(M_AXI_DDR_AWCACHE),
        .M_AXI_DDR_AWPROT(M_AXI_DDR_AWPROT),
        .M_AXI_DDR_AWQOS(M_AXI_DDR_AWQOS),
        .M_AXI_DDR_AWVALID(M_AXI_DDR_AWVALID),
        .M_AXI_DDR_AWREADY(M_AXI_DDR_AWREADY),
        .M_AXI_DDR_WDATA(M_AXI_DDR_WDATA),
        .M_AXI_DDR_WSTRB(M_AXI_DDR_WSTRB),
        .M_AXI_DDR_WLAST(M_AXI_DDR_WLAST),
        .M_AXI_DDR_WVALID(M_AXI_DDR_WVALID),
        .M_AXI_DDR_WREADY(M_AXI_DDR_WREADY),
        .M_AXI_DDR_BID(M_AXI_DDR_BID),
        .M_AXI_DDR_BRESP(M_AXI_DDR_BRESP),
        .M_AXI_DDR_BVALID(M_AXI_DDR_BVALID),
        .M_AXI_DDR_BREADY(M_AXI_DDR_BREADY),
        .M_AXI_DDR_ARID(M_AXI_DDR_ARID),
        .M_AXI_DDR_ARADDR(M_AXI_DDR_ARADDR),
        .M_AXI_DDR_ARLEN(M_AXI_DDR_ARLEN),
        .M_AXI_DDR_ARSIZE(M_AXI_DDR_ARSIZE),
        .M_AXI_DDR_ARBURST(M_AXI_DDR_ARBURST),
        .M_AXI_DDR_ARLOCK(M_AXI_DDR_ARLOCK),
        .M_AXI_DDR_ARCACHE(M_AXI_DDR_ARCACHE),
        .M_AXI_DDR_ARPROT(M_AXI_DDR_ARPROT),
        .M_AXI_DDR_ARQOS(M_AXI_DDR_ARQOS),
        .M_AXI_DDR_ARVALID(M_AXI_DDR_ARVALID),
        .M_AXI_DDR_ARREADY(M_AXI_DDR_ARREADY),
        .M_AXI_DDR_RID(M_AXI_DDR_RID),
        .M_AXI_DDR_RDATA(M_AXI_DDR_RDATA),
        .M_AXI_DDR_RRESP(M_AXI_DDR_RRESP),
        .M_AXI_DDR_RLAST(M_AXI_DDR_RLAST),
        .M_AXI_DDR_RVALID(M_AXI_DDR_RVALID),
        .M_AXI_DDR_RREADY(M_AXI_DDR_RREADY)
    );
endmodule
