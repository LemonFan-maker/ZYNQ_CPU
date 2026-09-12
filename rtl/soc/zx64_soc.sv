module zx64_soc #(
    parameter int BRAM_WORDS = 4096,
    parameter int SCRATCH_WORDS = 1024,
    parameter int CLK_HZ = 75_000_000,
    parameter bit USE_CORE5 = 1'b0,
    parameter bit ENABLE_FPU = 1'b1
) (
    input  logic clk,
    input  logic rst_n,
    input  logic soft_reset,
    input  logic [63:0] reset_vector,
    input  logic irq_external_i,
    input  logic [63:0] virtio_blk_capacity_sectors,
    input  logic        virtio_blk_backend_irq,
    input  logic        virtio_blk_notify_ack,
    output logic        virtio_blk_notify_pending,
    output logic [15:0] virtio_blk_notify_queue,
    output logic [31:0] virtio_blk_notify_count,
    output logic [31:0] virtio_blk_queue_num,
    output logic        virtio_blk_queue_ready,
    output logic [63:0] virtio_blk_queue_desc_addr,
    output logic [63:0] virtio_blk_queue_avail_addr,
    output logic [63:0] virtio_blk_queue_used_addr,
    output logic        virtio_blk_irq_pending,
    output logic [7:0]  virtio_blk_device_status,
    input  logic        virtio_input_backend_irq,
    input  logic        virtio_input_notify_ack,
    output logic        virtio_input_notify_pending,
    output logic [15:0] virtio_input_notify_queue,
    output logic [31:0] virtio_input_notify_count,
    output logic        virtio_input_irq_pending,
    output logic [7:0]  virtio_input_device_status,
    output logic [31:0] virtio_input_event_queue_num,
    output logic        virtio_input_event_queue_ready,
    output logic [63:0] virtio_input_event_queue_desc_addr,
    output logic [63:0] virtio_input_event_queue_avail_addr,
    output logic [63:0] virtio_input_event_queue_used_addr,
    output logic [31:0] virtio_input_status_queue_num,
    output logic        virtio_input_status_queue_ready,
    output logic [63:0] virtio_input_status_queue_desc_addr,
    output logic [63:0] virtio_input_status_queue_avail_addr,
    output logic [63:0] virtio_input_status_queue_used_addr,

    output logic uart_tx,
    output logic core_halted,
    output logic core_illegal,
    output logic [31:0] dbg_core_state,
    output logic [63:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_icache_hits,
    output logic [31:0] dbg_icache_misses,
    output logic [31:0] dbg_dcache_hits,
    output logic [31:0] dbg_dcache_misses,
    output logic [31:0] dbg_cache_invalidates,

    input  logic        host_valid,
    input  logic        host_we,
    input  logic [3:0]  host_wstrb,
    input  logic [31:0] host_addr,
    input  logic [31:0] host_wdata,
    output logic        host_ready,
    output logic [31:0] host_rdata,

    output logic [3:0]  M_AXI_DDR_AWID,
    output logic [31:0] M_AXI_DDR_AWADDR,
    output logic [7:0]  M_AXI_DDR_AWLEN,
    output logic [2:0]  M_AXI_DDR_AWSIZE,
    output logic [1:0]  M_AXI_DDR_AWBURST,
    output logic        M_AXI_DDR_AWLOCK,
    output logic [3:0]  M_AXI_DDR_AWCACHE,
    output logic [2:0]  M_AXI_DDR_AWPROT,
    output logic [3:0]  M_AXI_DDR_AWQOS,
    output logic        M_AXI_DDR_AWVALID,
    input  logic        M_AXI_DDR_AWREADY,
    output logic [31:0] M_AXI_DDR_WDATA,
    output logic [3:0]  M_AXI_DDR_WSTRB,
    output logic        M_AXI_DDR_WLAST,
    output logic        M_AXI_DDR_WVALID,
    input  logic        M_AXI_DDR_WREADY,
    input  logic [3:0]  M_AXI_DDR_BID,
    input  logic [1:0]  M_AXI_DDR_BRESP,
    input  logic        M_AXI_DDR_BVALID,
    output logic        M_AXI_DDR_BREADY,
    output logic [3:0]  M_AXI_DDR_ARID,
    output logic [31:0] M_AXI_DDR_ARADDR,
    output logic [7:0]  M_AXI_DDR_ARLEN,
    output logic [2:0]  M_AXI_DDR_ARSIZE,
    output logic [1:0]  M_AXI_DDR_ARBURST,
    output logic        M_AXI_DDR_ARLOCK,
    output logic [3:0]  M_AXI_DDR_ARCACHE,
    output logic [2:0]  M_AXI_DDR_ARPROT,
    output logic [3:0]  M_AXI_DDR_ARQOS,
    output logic        M_AXI_DDR_ARVALID,
    input  logic        M_AXI_DDR_ARREADY,
    input  logic [3:0]  M_AXI_DDR_RID,
    input  logic [31:0] M_AXI_DDR_RDATA,
    input  logic [1:0]  M_AXI_DDR_RRESP,
    input  logic        M_AXI_DDR_RLAST,
    input  logic        M_AXI_DDR_RVALID,
    output logic        M_AXI_DDR_RREADY
);
    localparam logic [31:0] UART_BASE  = 32'h1000_0000;
    localparam logic [31:0] TIMER_BASE = 32'h1001_0000;
    localparam logic [31:0] VIRTIO_BLK_BASE = 32'h1006_0000;
    localparam logic [31:0] VIRTIO_INPUT_BASE = 32'h1009_0000;
    localparam logic [31:0] PLIC_BASE = 32'h0c00_0000;
    localparam logic [31:0] SCRATCH_BASE = 32'h2000_0000;
    localparam logic [31:0] DDR_BASE   = 32'h8000_0000;
    localparam logic [31:0] BRAM_BYTES = BRAM_WORDS * 8;
    localparam int          SCRATCH_ADDR_BITS = $clog2(SCRATCH_WORDS);
    localparam int          SCRATCH_QWORDS = SCRATCH_WORDS / 2;
    localparam int          SCRATCH_QADDR_BITS = SCRATCH_ADDR_BITS - 1;
    localparam int          ICACHE_LINES = 128;
    localparam int          DCACHE_LINES = 128;
    localparam int          ICACHE_LINE_WORDS = 8;
    localparam int          DCACHE_LINE_WORDS = 4;
    localparam int          ICACHE_LINE_WORD_BITS = $clog2(ICACHE_LINE_WORDS);
    localparam int          DCACHE_LINE_WORD_BITS = $clog2(DCACHE_LINE_WORDS);
    localparam int          ICACHE_INDEX_BITS = $clog2(ICACHE_LINES);
    localparam int          DCACHE_INDEX_BITS = $clog2(DCACHE_LINES);
    localparam int          ICACHE_TAG_BITS = 32 - ICACHE_INDEX_BITS - 2;
    localparam int          DCACHE_TAG_BITS = 32 - DCACHE_INDEX_BITS - 3;

    logic        imem_valid;
    logic [31:0] imem_addr;
    logic        imem_ready;
    logic [31:0] imem_rdata;

    logic        dmem_valid;
    logic        dmem_we;
    logic [7:0]  dmem_wstrb;
    logic [31:0] dmem_addr;
    logic [63:0] dmem_wdata;
    logic        dmem_ready;
    logic [63:0] dmem_rdata;
    logic        core_fence_i;

    logic        ram_imem_valid;
    logic [31:0] ram_imem_addr;
    logic        ram_imem_ready;
    logic [31:0] ram_imem_rdata;
    logic        ram_dmem_valid;
    logic        ram_dmem_we;
    logic [7:0]  ram_dmem_wstrb;
    logic [31:0] ram_dmem_addr;
    logic [63:0] ram_dmem_wdata;
    logic        ram_dmem_ready;
    logic [63:0] ram_dmem_rdata;

    logic        uart_valid;
    logic        uart_ready;
    logic [31:0] uart_rdata;
    logic        timer_valid;
    logic        timer_ready;
    logic [31:0] timer_rdata;
    logic        timer_irq;
    logic        virtio_blk_valid;
    logic        virtio_blk_ready;
    logic [31:0] virtio_blk_rdata;
    logic        virtio_blk_notify_pulse;
    logic        virtio_input_valid;
    logic        virtio_input_ready;
    logic [31:0] virtio_input_rdata;
    logic        virtio_input_notify_pulse;
    logic        plic_valid;
    logic        plic_ready;
    logic [31:0] plic_rdata;
    logic        plic_irq_external;
    logic        core_irq_external;
    logic        scratch_valid;
    logic [SCRATCH_QADDR_BITS-1:0] scratch_qword;
    logic [63:0] scratch_rdata;
    logic        host_bram_selected;
    logic        host_scratch_selected;
    logic [SCRATCH_QADDR_BITS-1:0] host_scratch_qword;
    logic        host_scratch_hi;
    logic [31:0] host_scratch_rdata;

    logic [3:0]  mmio_wstrb;
    logic [31:0] mmio_wdata;
    logic [63:0] mmio_rdata64;

    logic        imem_bram_selected;
    logic        imem_ddr_selected;
    logic        imem_cacheable_selected;
    logic        icache_hit;
    logic        icache_miss_start;
    logic        icache_refill_valid;
    logic        icache_refill_wait;
    logic        icache_miss_ddr;
    logic        icache_resp_valid;
    logic        icache_resp_match;
    logic [31:0] icache_resp_rdata;
    logic [31:0] icache_resp_addr;
    logic [ICACHE_LINE_WORD_BITS-1:0] icache_refill_beat;
    logic [ICACHE_LINE_WORD_BITS-1:0] icache_miss_word_offset;
    logic [31:0] icache_miss_addr;
    logic [ICACHE_INDEX_BITS-1:0] icache_index;
    logic [ICACHE_INDEX_BITS-1:0] icache_line_base_index;
    logic [ICACHE_INDEX_BITS-1:0] icache_miss_base_index;
    logic [ICACHE_INDEX_BITS-1:0] icache_refill_index;
    logic [ICACHE_TAG_BITS-1:0]   icache_tag;
    logic [ICACHE_TAG_BITS-1:0]   icache_miss_tag;
    logic [ICACHE_LINES-1:0]      icache_valid;
    (* ram_style = "distributed" *)
    logic [ICACHE_TAG_BITS-1:0]   icache_tags [0:ICACHE_LINES-1];
    (* ram_style = "distributed" *)
    logic [31:0]                  icache_data [0:ICACHE_LINES-1];

    logic        dmem_bram_selected;
    logic        dmem_ddr_selected;
    logic        dmem_bram_read;
    logic        dmem_bram_write;
    logic        dmem_ddr_read;
    logic        dmem_ddr_write;
    logic        dmem_cacheable_read;
    logic        dcache_hit;
    logic        dcache_miss_start;
    logic        dcache_refill_valid;
    logic        dcache_refill_wait;
    logic        dcache_miss_ddr;
    logic        dcache_irq_invalidate_pending;
    logic        dcache_resp_valid;
    logic [63:0] dcache_resp_rdata;
    logic [31:0] dcache_resp_addr;
    logic [DCACHE_LINE_WORD_BITS-1:0] dcache_refill_beat;
    logic [DCACHE_LINE_WORD_BITS-1:0] dcache_miss_word_offset;
    logic [31:0] dcache_miss_addr;
    logic [DCACHE_INDEX_BITS-1:0] dcache_index;
    logic [DCACHE_INDEX_BITS-1:0] dcache_line_base_index;
    logic [DCACHE_INDEX_BITS-1:0] dcache_miss_base_index;
    logic [DCACHE_INDEX_BITS-1:0] dcache_refill_index;
    logic [DCACHE_TAG_BITS-1:0]   dcache_tag;
    logic [DCACHE_TAG_BITS-1:0]   dcache_miss_tag;
    logic [DCACHE_LINES-1:0]      dcache_valid;
    (* ram_style = "distributed" *)
    logic [DCACHE_TAG_BITS-1:0]   dcache_tags [0:DCACHE_LINES-1];
    (* ram_style = "distributed" *)
    logic [63:0]                  dcache_data [0:DCACHE_LINES-1];

    logic [ICACHE_INDEX_BITS-1:0] store_icache_index;
    logic [DCACHE_INDEX_BITS-1:0] store_dcache_index;
    logic                         icache_array_we;
    logic [ICACHE_INDEX_BITS-1:0] icache_array_windex;
    logic [ICACHE_TAG_BITS-1:0]   icache_array_wtag;
    logic [31:0]                  icache_array_wdata;
    logic                         dcache_array_we;
    logic [DCACHE_INDEX_BITS-1:0] dcache_array_windex;
    logic [DCACHE_TAG_BITS-1:0]   dcache_array_wtag;
    logic [63:0]                  dcache_array_wdata;
    logic [31:0] perf_icache_hits;
    logic [31:0] perf_icache_misses;
    logic [31:0] perf_dcache_hits;
    logic [31:0] perf_dcache_misses;
    logic [31:0] perf_cache_invalidates;
    (* ram_style = "distributed" *)
    logic [31:0] scratch_rx_lo_mem [0:SCRATCH_QWORDS-1];
    (* ram_style = "distributed" *)
    logic [31:0] scratch_rx_hi_mem [0:SCRATCH_QWORDS-1];
    (* ram_style = "distributed" *)
    logic [31:0] scratch_tx_lo_mem [0:SCRATCH_QWORDS-1];
    (* ram_style = "distributed" *)
    logic [31:0] scratch_tx_hi_mem [0:SCRATCH_QWORDS-1];
    logic        scratch_rx_lo_we;
    logic        scratch_rx_hi_we;
    logic        scratch_tx_lo_we;
    logic        scratch_tx_hi_we;
    logic [SCRATCH_QADDR_BITS-1:0] scratch_rx_lo_waddr;
    logic [SCRATCH_QADDR_BITS-1:0] scratch_rx_hi_waddr;
    logic [SCRATCH_QADDR_BITS-1:0] scratch_tx_lo_waddr;
    logic [SCRATCH_QADDR_BITS-1:0] scratch_tx_hi_waddr;
    logic [31:0] scratch_rx_lo_wdata;
    logic [31:0] scratch_rx_hi_wdata;
    logic [31:0] scratch_tx_lo_wdata;
    logic [31:0] scratch_tx_hi_wdata;
    logic [3:0]  scratch_rx_lo_wstrb;
    logic [3:0]  scratch_rx_hi_wstrb;
    logic [3:0]  scratch_tx_lo_wstrb;
    logic [3:0]  scratch_tx_hi_wstrb;

`ifndef SYNTHESIS
    initial begin
        for (int i = 0; i < SCRATCH_QWORDS; i++) begin
            scratch_rx_lo_mem[i] = 32'd0;
            scratch_rx_hi_mem[i] = 32'd0;
            scratch_tx_lo_mem[i] = 32'd0;
            scratch_tx_hi_mem[i] = 32'd0;
        end
    end
`endif

    typedef enum logic [1:0] {
        DDR_STORE_IDLE,
        DDR_STORE_LO,
        DDR_STORE_HI,
        DDR_STORE_DONE
    } ddr_store_state_t;

    ddr_store_state_t ddr_store_state;
    logic [31:0] ddr_store_addr_q;
    logic [63:0] ddr_store_wdata_q;
    logic [7:0]  ddr_store_wstrb_q;
    logic        ddr_store_done;

    logic        ddr32_valid;
    logic        ddr32_we;
    logic [3:0]  ddr32_wstrb;
    logic [31:0] ddr32_addr;
    logic [31:0] ddr32_wdata;
    logic [3:0]  ddr32_read_beats;
    logic        ddr32_ready;
    logic [31:0] ddr32_rdata;
    logic        ddr32_read_beat_valid;
    logic [3:0]  ddr32_read_beat_index;
    logic [31:0] ddr32_read_beat_data;
    logic        ddr_req_store;
    logic        ddr_req_dcache;
    logic        ddr_req_icache;
    logic [31:0] dcache_refill_low_q;
    logic [63:0] dcache_refill_word;

    assign imem_bram_selected = imem_valid && (imem_addr < BRAM_BYTES);
    assign imem_ddr_selected = imem_valid && (imem_addr[31:30] == 2'b10);
    assign imem_cacheable_selected = imem_bram_selected || imem_ddr_selected;
    assign icache_index = imem_addr[ICACHE_INDEX_BITS+1:2];
    assign icache_line_base_index = {imem_addr[ICACHE_INDEX_BITS+1:5], {ICACHE_LINE_WORD_BITS{1'b0}}};
    assign icache_refill_index = icache_miss_base_index + icache_refill_beat;
    assign icache_tag = imem_addr[31:ICACHE_INDEX_BITS+2];
    assign icache_resp_match = icache_resp_valid && imem_cacheable_selected &&
                               (imem_addr == icache_resp_addr);
    assign icache_hit = imem_cacheable_selected && !icache_refill_valid &&
                        icache_valid[icache_index] && (icache_tags[icache_index] == icache_tag);
    assign icache_miss_start = imem_cacheable_selected && !icache_hit &&
                               !icache_refill_valid && !icache_resp_match;

    assign dmem_bram_selected = dmem_valid && (dmem_addr < BRAM_BYTES);
    assign dmem_ddr_selected = dmem_valid && (dmem_addr[31:30] == 2'b10);
    assign dmem_bram_read = dmem_bram_selected && !dmem_we;
    assign dmem_bram_write = dmem_bram_selected && dmem_we;
    assign dmem_ddr_read = dmem_ddr_selected && !dmem_we;
    assign dmem_ddr_write = dmem_ddr_selected && dmem_we;
    assign dmem_cacheable_read = dmem_bram_read || dmem_ddr_read;
    assign dcache_index = dmem_addr[DCACHE_INDEX_BITS+2:3];
    assign dcache_line_base_index = {dmem_addr[DCACHE_INDEX_BITS+2:5], {DCACHE_LINE_WORD_BITS{1'b0}}};
    assign dcache_refill_index = dcache_miss_base_index + dcache_refill_beat;
    assign dcache_tag = dmem_addr[31:DCACHE_INDEX_BITS+3];
    assign dcache_hit = dmem_cacheable_read && !dcache_irq_invalidate_pending &&
                        !dcache_refill_valid && !dcache_resp_valid &&
                        dcache_valid[dcache_index] && (dcache_tags[dcache_index] == dcache_tag);
    assign dcache_miss_start = dmem_cacheable_read && !dcache_hit &&
                               !dcache_irq_invalidate_pending &&
                               !dcache_refill_valid && !dcache_resp_valid;
    assign store_icache_index = dmem_addr[ICACHE_INDEX_BITS+1:2];
    assign store_dcache_index = dmem_addr[DCACHE_INDEX_BITS+2:3];

    assign ram_imem_valid = icache_refill_valid && !icache_miss_ddr && !icache_refill_wait;
    assign ram_imem_addr = {icache_miss_addr[31:5], icache_refill_beat, 2'b00};
    assign host_bram_selected = host_valid && (host_addr < BRAM_BYTES);
    assign host_scratch_selected = host_valid && !host_bram_selected &&
                                   (host_addr[31:20] == SCRATCH_BASE[31:20]);
    assign host_scratch_qword = host_addr[SCRATCH_ADDR_BITS+1:3];
    assign host_scratch_hi = host_addr[2];
    assign host_scratch_rdata = host_addr[16] ?
                                (host_scratch_hi ? scratch_tx_hi_mem[host_scratch_qword] :
                                                   scratch_tx_lo_mem[host_scratch_qword]) :
                                (host_scratch_hi ? scratch_rx_hi_mem[host_scratch_qword] :
                                                   scratch_rx_lo_mem[host_scratch_qword]);

    assign ram_dmem_valid = host_bram_selected ||
                            (dcache_refill_valid && !dcache_miss_ddr && !dcache_refill_wait) ||
                            (dmem_bram_write && !dcache_refill_valid);
    assign ram_dmem_we = host_bram_selected ? host_we :
                         dcache_refill_valid ? 1'b0 : dmem_we;
    assign ram_dmem_wstrb = host_bram_selected ? (host_addr[2] ? {host_wstrb, 4'd0} :
                                                                 {4'd0, host_wstrb}) :
                            dcache_refill_valid ? 8'd0 : dmem_wstrb;
    assign ram_dmem_addr = host_bram_selected ? host_addr :
                           dcache_refill_valid ? {dcache_miss_addr[31:5], dcache_refill_beat, 3'b000} :
                                                 dmem_addr;
    assign ram_dmem_wdata = host_bram_selected ? (host_addr[2] ? {host_wdata, 32'd0} :
                                                                 {32'd0, host_wdata}) :
                            dcache_refill_valid ? 64'd0 : dmem_wdata;

    assign ddr_store_done = (ddr_store_state == DDR_STORE_DONE);
    assign ddr_req_store = (ddr_store_state == DDR_STORE_LO) || (ddr_store_state == DDR_STORE_HI);
    assign ddr_req_dcache = !ddr_req_store && dcache_refill_valid && dcache_miss_ddr;
    assign ddr_req_icache = !ddr_req_store && !ddr_req_dcache && icache_refill_valid && icache_miss_ddr;
    assign ddr32_valid = ddr_req_store || ddr_req_dcache || ddr_req_icache;
    assign ddr32_we = ddr_req_store;
    assign ddr32_wstrb = (ddr_store_state == DDR_STORE_HI) ? ddr_store_wstrb_q[7:4] :
                                                            ddr_store_wstrb_q[3:0];
    assign ddr32_addr = (ddr_store_state == DDR_STORE_LO) ? ddr_store_addr_q :
                        (ddr_store_state == DDR_STORE_HI) ? (ddr_store_addr_q + 32'd4) :
                        ddr_req_dcache ? dcache_miss_addr : icache_miss_addr;
    assign ddr32_wdata = (ddr_store_state == DDR_STORE_HI) ? ddr_store_wdata_q[63:32] :
                                                            ddr_store_wdata_q[31:0];
    assign ddr32_read_beats = ddr_req_dcache ? 4'd8 :
                              ddr_req_icache ? 4'd8 : 4'd1;
    assign dcache_refill_word = {ddr32_read_beat_data, dcache_refill_low_q};

    assign uart_valid = dmem_valid && !dmem_bram_selected && !dmem_ddr_selected &&
                        (dmem_addr[31:16] == UART_BASE[31:16]);
    assign timer_valid = dmem_valid && !dmem_bram_selected && !dmem_ddr_selected &&
                         (dmem_addr[31:16] == TIMER_BASE[31:16]);
    assign virtio_blk_valid = dmem_valid && !dmem_bram_selected && !dmem_ddr_selected &&
                              (dmem_addr[31:12] == VIRTIO_BLK_BASE[31:12]);
    assign virtio_input_valid = dmem_valid && !dmem_bram_selected && !dmem_ddr_selected &&
                                (dmem_addr[31:12] == VIRTIO_INPUT_BASE[31:12]);
    assign plic_valid = dmem_valid && !dmem_bram_selected && !dmem_ddr_selected &&
                        (dmem_addr[31:22] == PLIC_BASE[31:22]);
    assign scratch_valid = dmem_valid && !dmem_bram_selected && !dmem_ddr_selected &&
                           (dmem_addr[31:20] == SCRATCH_BASE[31:20]);
    assign scratch_qword = dmem_addr[SCRATCH_ADDR_BITS+1:3];
    assign scratch_rdata = dmem_addr[16] ?
                           {scratch_tx_hi_mem[scratch_qword],
                            scratch_tx_lo_mem[scratch_qword]} :
                           {scratch_rx_hi_mem[scratch_qword],
                            scratch_rx_lo_mem[scratch_qword]};
    assign mmio_wstrb = dmem_addr[2] ? dmem_wstrb[7:4] : dmem_wstrb[3:0];
    assign mmio_wdata = dmem_addr[2] ? dmem_wdata[63:32] : dmem_wdata[31:0];
    assign dbg_icache_hits = perf_icache_hits;
    assign dbg_icache_misses = perf_icache_misses;
    assign dbg_dcache_hits = perf_dcache_hits;
    assign dbg_dcache_misses = perf_dcache_misses;
    assign dbg_cache_invalidates = perf_cache_invalidates;
    assign core_irq_external = irq_external_i | plic_irq_external;

    always_comb begin
        icache_array_we = 1'b0;
        icache_array_windex = icache_refill_index;
        icache_array_wtag = icache_miss_tag;
        icache_array_wdata = ram_imem_rdata;
        if (icache_refill_valid && !icache_miss_ddr && icache_refill_wait && ram_imem_ready) begin
            icache_array_we = 1'b1;
        end else if (ddr32_read_beat_valid && ddr_req_icache) begin
            icache_array_we = 1'b1;
            icache_array_windex = icache_miss_base_index + ddr32_read_beat_index[2:0];
            icache_array_wdata = ddr32_read_beat_data;
        end
    end

    always_comb begin
        dcache_array_we = 1'b0;
        dcache_array_windex = dcache_refill_index;
        dcache_array_wtag = dcache_miss_tag;
        dcache_array_wdata = ram_dmem_rdata;
        if (dcache_refill_valid && !dcache_miss_ddr && dcache_refill_wait && ram_dmem_ready) begin
            dcache_array_we = 1'b1;
        end else if (ddr32_read_beat_valid && ddr_req_dcache && ddr32_read_beat_index[0]) begin
            dcache_array_we = 1'b1;
            dcache_array_windex = dcache_miss_base_index + ddr32_read_beat_index[2:1];
            dcache_array_wdata = dcache_refill_word;
        end
    end

    always_comb begin
        scratch_rx_lo_we = scratch_valid && dmem_we && !dmem_addr[16] && (dmem_wstrb[3:0] != 4'd0);
        scratch_rx_hi_we = scratch_valid && dmem_we && !dmem_addr[16] && (dmem_wstrb[7:4] != 4'd0);
        scratch_tx_lo_we = scratch_valid && dmem_we && dmem_addr[16] && (dmem_wstrb[3:0] != 4'd0);
        scratch_tx_hi_we = scratch_valid && dmem_we && dmem_addr[16] && (dmem_wstrb[7:4] != 4'd0);

        scratch_rx_lo_waddr = scratch_qword;
        scratch_rx_hi_waddr = scratch_qword;
        scratch_tx_lo_waddr = scratch_qword;
        scratch_tx_hi_waddr = scratch_qword;
        scratch_rx_lo_wdata = dmem_wdata[31:0];
        scratch_rx_hi_wdata = dmem_wdata[63:32];
        scratch_tx_lo_wdata = dmem_wdata[31:0];
        scratch_tx_hi_wdata = dmem_wdata[63:32];
        scratch_rx_lo_wstrb = dmem_wstrb[3:0];
        scratch_rx_hi_wstrb = dmem_wstrb[7:4];
        scratch_tx_lo_wstrb = dmem_wstrb[3:0];
        scratch_tx_hi_wstrb = dmem_wstrb[7:4];

        if (host_scratch_selected && host_we) begin
            if (host_addr[16]) begin
                if (host_scratch_hi) begin
                    scratch_tx_hi_we = host_wstrb != 4'd0;
                    scratch_tx_hi_waddr = host_scratch_qword;
                    scratch_tx_hi_wdata = host_wdata;
                    scratch_tx_hi_wstrb = host_wstrb;
                end else begin
                    scratch_tx_lo_we = host_wstrb != 4'd0;
                    scratch_tx_lo_waddr = host_scratch_qword;
                    scratch_tx_lo_wdata = host_wdata;
                    scratch_tx_lo_wstrb = host_wstrb;
                end
            end else begin
                if (host_scratch_hi) begin
                    scratch_rx_hi_we = host_wstrb != 4'd0;
                    scratch_rx_hi_waddr = host_scratch_qword;
                    scratch_rx_hi_wdata = host_wdata;
                    scratch_rx_hi_wstrb = host_wstrb;
                end else begin
                    scratch_rx_lo_we = host_wstrb != 4'd0;
                    scratch_rx_lo_waddr = host_scratch_qword;
                    scratch_rx_lo_wdata = host_wdata;
                    scratch_rx_lo_wstrb = host_wstrb;
                end
            end
        end
    end

    always_comb begin
        host_ready = host_valid;
        host_rdata = 32'd0;
        if (host_bram_selected) begin
            host_ready = ram_dmem_ready;
            host_rdata = host_addr[2] ? ram_dmem_rdata[63:32] : ram_dmem_rdata[31:0];
        end else if (host_scratch_selected) begin
            host_ready = 1'b1;
            host_rdata = host_scratch_rdata;
        end
    end

    always_comb begin
        imem_ready = imem_valid;
        imem_rdata = 32'h0010_0073; // ebreak for unmapped fetches.
        if (imem_cacheable_selected) begin
            if (icache_hit) begin
                imem_ready = 1'b1;
                imem_rdata = icache_data[icache_index];
            end else if (icache_resp_match) begin
                imem_ready = 1'b1;
                imem_rdata = icache_resp_rdata;
            end else begin
                imem_ready = 1'b0;
                imem_rdata = 32'd0;
            end
        end
    end

    always_comb begin
        dmem_ready = dmem_valid;
        dmem_rdata = 64'd0;
        mmio_rdata64 = 64'd0;
        if (dmem_cacheable_read) begin
            if (dcache_hit) begin
                dmem_ready = 1'b1;
                dmem_rdata = dcache_data[dcache_index];
            end else if (dcache_resp_valid && (dmem_addr == dcache_resp_addr)) begin
                dmem_ready = 1'b1;
                dmem_rdata = dcache_resp_rdata;
            end else begin
                dmem_ready = 1'b0;
                dmem_rdata = 64'd0;
            end
        end else if (dmem_bram_write) begin
            dmem_ready = ram_dmem_ready;
            dmem_rdata = ram_dmem_rdata;
        end else if (dmem_ddr_write) begin
            dmem_ready = ddr_store_done;
            dmem_rdata = 64'd0;
        end else if (uart_valid) begin
            dmem_ready = uart_ready;
            mmio_rdata64 = dmem_addr[2] ? {uart_rdata, 32'd0} : {32'd0, uart_rdata};
            dmem_rdata = mmio_rdata64;
        end else if (timer_valid) begin
            dmem_ready = timer_ready;
            mmio_rdata64 = dmem_addr[2] ? {timer_rdata, 32'd0} : {32'd0, timer_rdata};
            dmem_rdata = mmio_rdata64;
        end else if (virtio_blk_valid) begin
            dmem_ready = virtio_blk_ready;
            mmio_rdata64 = dmem_addr[2] ? {virtio_blk_rdata, 32'd0} : {32'd0, virtio_blk_rdata};
            dmem_rdata = mmio_rdata64;
        end else if (virtio_input_valid) begin
            dmem_ready = virtio_input_ready;
            mmio_rdata64 = dmem_addr[2] ? {virtio_input_rdata, 32'd0} : {32'd0, virtio_input_rdata};
            dmem_rdata = mmio_rdata64;
        end else if (plic_valid) begin
            dmem_ready = plic_ready;
            mmio_rdata64 = dmem_addr[2] ? {plic_rdata, 32'd0} : {32'd0, plic_rdata};
            dmem_rdata = mmio_rdata64;
        end else if (scratch_valid) begin
            dmem_ready = 1'b1;
            dmem_rdata = scratch_rdata;
        end else begin
            mmio_rdata64 = 64'd0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            icache_valid <= '0;
            icache_refill_valid <= 1'b0;
            icache_refill_wait <= 1'b0;
            icache_miss_ddr <= 1'b0;
            icache_resp_valid <= 1'b0;
            icache_resp_rdata <= 32'd0;
            icache_resp_addr <= 32'd0;
            icache_refill_beat <= '0;
            icache_miss_word_offset <= '0;
            icache_miss_addr <= 32'd0;
            icache_miss_base_index <= '0;
            icache_miss_tag <= '0;
            dcache_valid <= '0;
            dcache_refill_valid <= 1'b0;
            dcache_refill_wait <= 1'b0;
            dcache_miss_ddr <= 1'b0;
            dcache_irq_invalidate_pending <= 1'b0;
            dcache_resp_valid <= 1'b0;
            dcache_resp_rdata <= 64'd0;
            dcache_resp_addr <= 32'd0;
            dcache_refill_beat <= '0;
            dcache_miss_word_offset <= '0;
            dcache_miss_addr <= 32'd0;
            dcache_miss_base_index <= '0;
            dcache_miss_tag <= '0;
            perf_icache_hits <= 32'd0;
            perf_icache_misses <= 32'd0;
            perf_dcache_hits <= 32'd0;
            perf_dcache_misses <= 32'd0;
            perf_cache_invalidates <= 32'd0;
            ddr_store_state <= DDR_STORE_IDLE;
            ddr_store_addr_q <= 32'd0;
            ddr_store_wdata_q <= 64'd0;
            ddr_store_wstrb_q <= 8'd0;
            dcache_refill_low_q <= 32'd0;
        end else begin
            if (icache_hit) begin
                perf_icache_hits <= perf_icache_hits + 32'd1;
            end
            if (dcache_hit) begin
                perf_dcache_hits <= perf_dcache_hits + 32'd1;
            end

            if (icache_resp_valid && (!imem_cacheable_selected || (imem_addr != icache_resp_addr) ||
                                      icache_hit)) begin
                icache_resp_valid <= 1'b0;
            end else if (icache_resp_match) begin
                icache_resp_valid <= 1'b0;
            end
            if (dcache_resp_valid && dmem_cacheable_read && (dmem_addr == dcache_resp_addr)) begin
                dcache_resp_valid <= 1'b0;
            end

            if (core_fence_i) begin
                icache_valid <= '0;
                icache_refill_valid <= 1'b0;
                icache_refill_wait <= 1'b0;
                icache_miss_ddr <= 1'b0;
                icache_resp_valid <= 1'b0;
                perf_cache_invalidates <= perf_cache_invalidates + 32'd1;
            end else if (icache_miss_start) begin
                perf_icache_misses <= perf_icache_misses + 32'd1;
                icache_refill_valid <= 1'b1;
                icache_refill_wait <= 1'b0;
                icache_miss_ddr <= imem_ddr_selected;
                icache_refill_beat <= '0;
                icache_miss_word_offset <= imem_addr[4:2];
                icache_miss_addr <= {imem_addr[31:5], 5'b00000};
                icache_miss_base_index <= icache_line_base_index;
                icache_miss_tag <= icache_tag;
                icache_resp_rdata <= 32'd0;
            end else if (icache_refill_valid && !icache_miss_ddr) begin
                if (!icache_refill_wait) begin
                    icache_refill_wait <= 1'b1;
                end else if (ram_imem_ready) begin
                    icache_valid[icache_refill_index] <= 1'b1;
                    if (icache_refill_beat == icache_miss_word_offset) begin
                        icache_resp_rdata <= ram_imem_rdata;
                        icache_resp_addr <= {icache_miss_addr[31:5], icache_miss_word_offset, 2'b00};
                        icache_resp_valid <= 1'b1;
                    end
                    if (icache_refill_beat == ICACHE_LINE_WORDS - 1) begin
                        icache_refill_valid <= 1'b0;
                        icache_refill_wait <= 1'b0;
                    end else begin
                        icache_refill_beat <= icache_refill_beat + 1'b1;
                        icache_refill_wait <= 1'b0;
                    end
                end
            end
            if (ddr32_read_beat_valid && ddr_req_icache) begin
                icache_valid[icache_miss_base_index + ddr32_read_beat_index[2:0]] <= 1'b1;
                if (ddr32_read_beat_index[2:0] == icache_miss_word_offset) begin
                    icache_resp_rdata <= ddr32_read_beat_data;
                    icache_resp_addr <= {icache_miss_addr[31:5], icache_miss_word_offset, 2'b00};
                    icache_resp_valid <= 1'b1;
                end
            end
            if (icache_refill_valid && icache_miss_ddr && ddr_req_icache && ddr32_ready) begin
                icache_refill_valid <= 1'b0;
                icache_miss_ddr <= 1'b0;
            end

            if (dcache_miss_start) begin
                perf_dcache_misses <= perf_dcache_misses + 32'd1;
                dcache_refill_valid <= 1'b1;
                dcache_refill_wait <= 1'b0;
                dcache_miss_ddr <= dmem_ddr_read;
                dcache_refill_beat <= '0;
                dcache_miss_word_offset <= dmem_addr[4:3];
                dcache_miss_addr <= {dmem_addr[31:5], 5'b00000};
                dcache_miss_base_index <= dcache_line_base_index;
                dcache_miss_tag <= dcache_tag;
                dcache_resp_rdata <= 64'd0;
            end else if (dcache_refill_valid && !dcache_miss_ddr) begin
                if (!dcache_refill_wait) begin
                    dcache_refill_wait <= 1'b1;
                end else if (ram_dmem_ready) begin
                    dcache_valid[dcache_refill_index] <= 1'b1;
                    if (dcache_refill_beat == dcache_miss_word_offset) begin
                        dcache_resp_rdata <= ram_dmem_rdata;
                        dcache_resp_addr <= {dcache_miss_addr[31:5], dcache_miss_word_offset, 3'b000};
                        dcache_resp_valid <= 1'b1;
                    end
                    if (dcache_refill_beat == DCACHE_LINE_WORDS - 1) begin
                        dcache_refill_valid <= 1'b0;
                        dcache_refill_wait <= 1'b0;
                    end else begin
                        dcache_refill_beat <= dcache_refill_beat + 1'b1;
                        dcache_refill_wait <= 1'b0;
                    end
                end
            end
            if (ddr32_read_beat_valid && ddr_req_dcache && !dcache_irq_invalidate_pending) begin
                if (ddr32_read_beat_index[0] == 1'b0) begin
                    dcache_refill_low_q <= ddr32_read_beat_data;
                end else begin
                    dcache_valid[dcache_miss_base_index + ddr32_read_beat_index[2:1]] <= 1'b1;
                    if (ddr32_read_beat_index[2:1] == dcache_miss_word_offset) begin
                        dcache_resp_rdata <= dcache_refill_word;
                        dcache_resp_addr <= {dcache_miss_addr[31:5], dcache_miss_word_offset, 3'b000};
                        dcache_resp_valid <= 1'b1;
                    end
                end
            end
            if (dcache_refill_valid && dcache_miss_ddr && ddr_req_dcache && ddr32_ready) begin
                dcache_refill_valid <= 1'b0;
                dcache_miss_ddr <= 1'b0;
                dcache_irq_invalidate_pending <= 1'b0;
                if (dcache_irq_invalidate_pending) begin
                    dcache_valid <= '0;
                    dcache_resp_valid <= 1'b0;
                end
            end

            case (ddr_store_state)
                DDR_STORE_IDLE: begin
                    if (dmem_ddr_write && !dcache_refill_valid && !icache_refill_valid) begin
                        ddr_store_addr_q <= dmem_addr;
                        ddr_store_wdata_q <= dmem_wdata;
                        ddr_store_wstrb_q <= dmem_wstrb;
                        if (dmem_wstrb[3:0] != 4'd0) begin
                            ddr_store_state <= DDR_STORE_LO;
                        end else if (dmem_wstrb[7:4] != 4'd0) begin
                            ddr_store_state <= DDR_STORE_HI;
                        end else begin
                            ddr_store_state <= DDR_STORE_DONE;
                        end
                    end
                end
                DDR_STORE_LO: begin
                    if (ddr32_ready) begin
                        if (ddr_store_wstrb_q[7:4] != 4'd0) begin
                            ddr_store_state <= DDR_STORE_HI;
                        end else begin
                            ddr_store_state <= DDR_STORE_DONE;
                        end
                    end
                end
                DDR_STORE_HI: begin
                    if (ddr32_ready) begin
                        ddr_store_state <= DDR_STORE_DONE;
                    end
                end
                DDR_STORE_DONE: begin
                    if (dmem_ddr_write) begin
                        ddr_store_state <= DDR_STORE_IDLE;
                    end
                end
                default: ddr_store_state <= DDR_STORE_IDLE;
            endcase

            if (dmem_bram_write && ram_dmem_ready) begin
                dcache_valid[store_dcache_index] <= 1'b0;
                icache_valid[store_icache_index] <= 1'b0;
                perf_cache_invalidates <= perf_cache_invalidates + 32'd1;
            end
            if (dmem_ddr_write && ddr_store_done) begin
                dcache_valid[store_dcache_index] <= 1'b0;
                icache_valid[store_icache_index] <= 1'b0;
                perf_cache_invalidates <= perf_cache_invalidates + 32'd1;
            end
            if (virtio_blk_backend_irq || virtio_input_backend_irq) begin
                dcache_valid <= '0;
                dcache_resp_valid <= 1'b0;
                if (dcache_refill_valid && dcache_miss_ddr) begin
                    dcache_irq_invalidate_pending <= 1'b1;
                end else begin
                    dcache_refill_valid <= 1'b0;
                    dcache_refill_wait <= 1'b0;
                    dcache_miss_ddr <= 1'b0;
                    dcache_irq_invalidate_pending <= 1'b0;
                end
                perf_cache_invalidates <= perf_cache_invalidates + 32'd1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (scratch_tx_lo_we) begin
            if (scratch_tx_lo_wstrb[0]) scratch_tx_lo_mem[scratch_tx_lo_waddr][7:0]   <= scratch_tx_lo_wdata[7:0];
            if (scratch_tx_lo_wstrb[1]) scratch_tx_lo_mem[scratch_tx_lo_waddr][15:8]  <= scratch_tx_lo_wdata[15:8];
            if (scratch_tx_lo_wstrb[2]) scratch_tx_lo_mem[scratch_tx_lo_waddr][23:16] <= scratch_tx_lo_wdata[23:16];
            if (scratch_tx_lo_wstrb[3]) scratch_tx_lo_mem[scratch_tx_lo_waddr][31:24] <= scratch_tx_lo_wdata[31:24];
        end
        if (scratch_tx_hi_we) begin
            if (scratch_tx_hi_wstrb[0]) scratch_tx_hi_mem[scratch_tx_hi_waddr][7:0]   <= scratch_tx_hi_wdata[7:0];
            if (scratch_tx_hi_wstrb[1]) scratch_tx_hi_mem[scratch_tx_hi_waddr][15:8]  <= scratch_tx_hi_wdata[15:8];
            if (scratch_tx_hi_wstrb[2]) scratch_tx_hi_mem[scratch_tx_hi_waddr][23:16] <= scratch_tx_hi_wdata[23:16];
            if (scratch_tx_hi_wstrb[3]) scratch_tx_hi_mem[scratch_tx_hi_waddr][31:24] <= scratch_tx_hi_wdata[31:24];
        end
        if (scratch_rx_lo_we) begin
            if (scratch_rx_lo_wstrb[0]) scratch_rx_lo_mem[scratch_rx_lo_waddr][7:0]   <= scratch_rx_lo_wdata[7:0];
            if (scratch_rx_lo_wstrb[1]) scratch_rx_lo_mem[scratch_rx_lo_waddr][15:8]  <= scratch_rx_lo_wdata[15:8];
            if (scratch_rx_lo_wstrb[2]) scratch_rx_lo_mem[scratch_rx_lo_waddr][23:16] <= scratch_rx_lo_wdata[23:16];
            if (scratch_rx_lo_wstrb[3]) scratch_rx_lo_mem[scratch_rx_lo_waddr][31:24] <= scratch_rx_lo_wdata[31:24];
        end
        if (scratch_rx_hi_we) begin
            if (scratch_rx_hi_wstrb[0]) scratch_rx_hi_mem[scratch_rx_hi_waddr][7:0]   <= scratch_rx_hi_wdata[7:0];
            if (scratch_rx_hi_wstrb[1]) scratch_rx_hi_mem[scratch_rx_hi_waddr][15:8]  <= scratch_rx_hi_wdata[15:8];
            if (scratch_rx_hi_wstrb[2]) scratch_rx_hi_mem[scratch_rx_hi_waddr][23:16] <= scratch_rx_hi_wdata[23:16];
            if (scratch_rx_hi_wstrb[3]) scratch_rx_hi_mem[scratch_rx_hi_waddr][31:24] <= scratch_rx_hi_wdata[31:24];
        end

        if (icache_array_we) begin
            icache_tags[icache_array_windex] <= icache_array_wtag;
            icache_data[icache_array_windex] <= icache_array_wdata;
        end
        if (dcache_array_we) begin
            dcache_tags[dcache_array_windex] <= dcache_array_wtag;
            dcache_data[dcache_array_windex] <= dcache_array_wdata;
        end
    end

    generate
        if (USE_CORE5) begin : gen_core5
            zx64_core5 #(
                .ENABLE_FPU(ENABLE_FPU)
            ) u_core (
                .clk(clk),
                .rst_n(rst_n),
                .soft_reset(soft_reset),
                .reset_vector(reset_vector),
                .irq_timer(timer_irq),
                .irq_external(core_irq_external),
                .imem_valid(imem_valid),
                .imem_addr(imem_addr),
                .imem_ready(imem_ready),
                .imem_rdata(imem_rdata),
                .dmem_valid(dmem_valid),
                .dmem_we(dmem_we),
                .dmem_wstrb(dmem_wstrb),
                .dmem_addr(dmem_addr),
                .dmem_wdata(dmem_wdata),
                .dmem_ready(dmem_ready),
                .dmem_rdata(dmem_rdata),
                .fence_i(core_fence_i),
                .halted(core_halted),
                .illegal_instr(core_illegal),
                .dbg_state(dbg_core_state),
                .dbg_pc(dbg_pc),
                .dbg_instr(dbg_instr)
            );
        end else begin : gen_core
            assign core_fence_i = 1'b0;

            zx64_core u_core (
                .clk(clk),
                .rst_n(rst_n),
                .soft_reset(soft_reset),
                .reset_vector(reset_vector),
                .irq_timer(timer_irq),
                .irq_external(core_irq_external),
                .imem_valid(imem_valid),
                .imem_addr(imem_addr),
                .imem_ready(imem_ready),
                .imem_rdata(imem_rdata),
                .dmem_valid(dmem_valid),
                .dmem_we(dmem_we),
                .dmem_wstrb(dmem_wstrb),
                .dmem_addr(dmem_addr),
                .dmem_wdata(dmem_wdata),
                .dmem_ready(dmem_ready),
                .dmem_rdata(dmem_rdata),
                .halted(core_halted),
                .illegal_instr(core_illegal),
                .dbg_state(dbg_core_state),
                .dbg_pc(dbg_pc),
                .dbg_instr(dbg_instr)
            );
        end
    endgenerate

    simple_ram64 #(.WORDS(BRAM_WORDS)) u_ram (
        .clk(clk),
        .imem_valid(ram_imem_valid),
        .imem_addr(ram_imem_addr),
        .imem_ready(ram_imem_ready),
        .imem_rdata(ram_imem_rdata),
        .dmem_valid(ram_dmem_valid),
        .dmem_we(ram_dmem_we),
        .dmem_wstrb(ram_dmem_wstrb),
        .dmem_addr(ram_dmem_addr),
        .dmem_wdata(ram_dmem_wdata),
        .dmem_ready(ram_dmem_ready),
        .dmem_rdata(ram_dmem_rdata)
    );

    mmio_uart_tx #(.CLK_HZ(CLK_HZ)) u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .valid(uart_valid),
        .we(dmem_we),
        .wstrb(mmio_wstrb),
        .addr(dmem_addr),
        .wdata(mmio_wdata),
        .ready(uart_ready),
        .rdata(uart_rdata),
        .tx(uart_tx)
    );

    mmio_timer u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .valid(timer_valid),
        .we(dmem_we),
        .wstrb(mmio_wstrb),
        .addr(dmem_addr),
        .wdata(mmio_wdata),
        .ready(timer_ready),
        .rdata(timer_rdata),
        .irq_timer(timer_irq)
    );

    mmio_virtio_blk_regs #(
        .DEFAULT_CAPACITY_SECTORS(64'd0),
        .QUEUE_NUM_MAX(128)
    ) u_virtio_blk (
        .clk(clk),
        .rst_n(rst_n),
        .valid(virtio_blk_valid),
        .we(dmem_we),
        .wstrb(mmio_wstrb),
        .addr(dmem_addr - VIRTIO_BLK_BASE),
        .wdata(mmio_wdata),
        .ready(virtio_blk_ready),
        .rdata(virtio_blk_rdata),
        .capacity_sectors(virtio_blk_capacity_sectors),
        .backend_vring_irq(virtio_blk_backend_irq),
        .backend_notify_ack(virtio_blk_notify_ack),
        .notify_pulse(virtio_blk_notify_pulse),
        .notify_queue(virtio_blk_notify_queue),
        .notify_pending(virtio_blk_notify_pending),
        .irq_pending(virtio_blk_irq_pending),
        .notify_count(virtio_blk_notify_count),
        .queue_num(virtio_blk_queue_num),
        .queue_ready(virtio_blk_queue_ready),
        .queue_desc_addr(virtio_blk_queue_desc_addr),
        .queue_avail_addr(virtio_blk_queue_avail_addr),
        .queue_used_addr(virtio_blk_queue_used_addr),
        .device_status(virtio_blk_device_status)
    );

    mmio_virtio_input_regs #(
        .QUEUE_NUM_MAX(64)
    ) u_virtio_input (
        .clk(clk),
        .rst_n(rst_n),
        .valid(virtio_input_valid),
        .we(dmem_we),
        .wstrb(mmio_wstrb),
        .addr(dmem_addr - VIRTIO_INPUT_BASE),
        .wdata(mmio_wdata),
        .ready(virtio_input_ready),
        .rdata(virtio_input_rdata),
        .backend_vring_irq(virtio_input_backend_irq),
        .backend_notify_ack(virtio_input_notify_ack),
        .notify_pulse(virtio_input_notify_pulse),
        .notify_queue(virtio_input_notify_queue),
        .notify_pending(virtio_input_notify_pending),
        .irq_pending(virtio_input_irq_pending),
        .notify_count(virtio_input_notify_count),
        .device_status(virtio_input_device_status),
        .event_queue_num(virtio_input_event_queue_num),
        .event_queue_ready(virtio_input_event_queue_ready),
        .event_queue_desc_addr(virtio_input_event_queue_desc_addr),
        .event_queue_avail_addr(virtio_input_event_queue_avail_addr),
        .event_queue_used_addr(virtio_input_event_queue_used_addr),
        .status_queue_num(virtio_input_status_queue_num),
        .status_queue_ready(virtio_input_status_queue_ready),
        .status_queue_desc_addr(virtio_input_status_queue_desc_addr),
        .status_queue_avail_addr(virtio_input_status_queue_avail_addr),
        .status_queue_used_addr(virtio_input_status_queue_used_addr)
    );

    mmio_plic_min #(
        .NUM_SOURCES(2)
    ) u_plic (
        .clk(clk),
        .rst_n(rst_n),
        .valid(plic_valid),
        .we(dmem_we),
        .wstrb(mmio_wstrb),
        .addr(dmem_addr - PLIC_BASE),
        .wdata(mmio_wdata),
        .ready(plic_ready),
        .rdata(plic_rdata),
        .source_irq({virtio_input_irq_pending, virtio_blk_irq_pending}),
        .irq_external(plic_irq_external)
    );

    axi4_master_bridge #(
        .CPU_BASE_ADDR(DDR_BASE),
        .PHYS_BASE_ADDR(32'h0000_0000)
    ) u_ddr_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .valid(ddr32_valid),
        .we(ddr32_we),
        .wstrb(ddr32_wstrb),
        .addr(ddr32_addr),
        .wdata(ddr32_wdata),
        .read_beats(ddr32_read_beats),
        .ready(ddr32_ready),
        .rdata(ddr32_rdata),
        .read_beat_valid(ddr32_read_beat_valid),
        .read_beat_index(ddr32_read_beat_index),
        .read_beat_data(ddr32_read_beat_data),
        .M_AXI_AWID(M_AXI_DDR_AWID),
        .M_AXI_AWADDR(M_AXI_DDR_AWADDR),
        .M_AXI_AWLEN(M_AXI_DDR_AWLEN),
        .M_AXI_AWSIZE(M_AXI_DDR_AWSIZE),
        .M_AXI_AWBURST(M_AXI_DDR_AWBURST),
        .M_AXI_AWLOCK(M_AXI_DDR_AWLOCK),
        .M_AXI_AWCACHE(M_AXI_DDR_AWCACHE),
        .M_AXI_AWPROT(M_AXI_DDR_AWPROT),
        .M_AXI_AWQOS(M_AXI_DDR_AWQOS),
        .M_AXI_AWVALID(M_AXI_DDR_AWVALID),
        .M_AXI_AWREADY(M_AXI_DDR_AWREADY),
        .M_AXI_WDATA(M_AXI_DDR_WDATA),
        .M_AXI_WSTRB(M_AXI_DDR_WSTRB),
        .M_AXI_WLAST(M_AXI_DDR_WLAST),
        .M_AXI_WVALID(M_AXI_DDR_WVALID),
        .M_AXI_WREADY(M_AXI_DDR_WREADY),
        .M_AXI_BID(M_AXI_DDR_BID),
        .M_AXI_BRESP(M_AXI_DDR_BRESP),
        .M_AXI_BVALID(M_AXI_DDR_BVALID),
        .M_AXI_BREADY(M_AXI_DDR_BREADY),
        .M_AXI_ARID(M_AXI_DDR_ARID),
        .M_AXI_ARADDR(M_AXI_DDR_ARADDR),
        .M_AXI_ARLEN(M_AXI_DDR_ARLEN),
        .M_AXI_ARSIZE(M_AXI_DDR_ARSIZE),
        .M_AXI_ARBURST(M_AXI_DDR_ARBURST),
        .M_AXI_ARLOCK(M_AXI_DDR_ARLOCK),
        .M_AXI_ARCACHE(M_AXI_DDR_ARCACHE),
        .M_AXI_ARPROT(M_AXI_DDR_ARPROT),
        .M_AXI_ARQOS(M_AXI_DDR_ARQOS),
        .M_AXI_ARVALID(M_AXI_DDR_ARVALID),
        .M_AXI_ARREADY(M_AXI_DDR_ARREADY),
        .M_AXI_RID(M_AXI_DDR_RID),
        .M_AXI_RDATA(M_AXI_DDR_RDATA),
        .M_AXI_RRESP(M_AXI_DDR_RRESP),
        .M_AXI_RLAST(M_AXI_DDR_RLAST),
        .M_AXI_RVALID(M_AXI_DDR_RVALID),
        .M_AXI_RREADY(M_AXI_DDR_RREADY)
    );
endmodule
