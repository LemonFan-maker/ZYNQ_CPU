module zx32_soc #(
    parameter int BRAM_WORDS = 4096,
    parameter int SCRATCH_WORDS = 256,
    parameter int CLK_HZ = 75_000_000
) (
    input  logic clk,
    input  logic rst_n,

    output logic uart_tx,

    input  logic        host_valid,
    input  logic        host_we,
    input  logic [3:0]  host_wstrb,
    input  logic [31:0] host_addr,
    input  logic [31:0] host_wdata,
    output logic        host_ready,
    output logic [31:0] host_rdata,

    output logic        dm_mm2s_cmd_valid,
    input  logic        dm_mm2s_cmd_ready,
    output logic [71:0] dm_mm2s_cmd_data,
    input  logic        dm_mm2s_sts_valid,
    output logic        dm_mm2s_sts_ready,
    input  logic [7:0]  dm_mm2s_sts_data,

    output logic        dm_s2mm_cmd_valid,
    input  logic        dm_s2mm_cmd_ready,
    output logic [71:0] dm_s2mm_cmd_data,
    input  logic        dm_s2mm_sts_valid,
    output logic        dm_s2mm_sts_ready,
    input  logic [7:0]  dm_s2mm_sts_data,

    input  logic [31:0] dm_m_axis_mm2s_tdata,
    input  logic [3:0]  dm_m_axis_mm2s_tkeep,
    input  logic        dm_m_axis_mm2s_tlast,
    input  logic        dm_m_axis_mm2s_tvalid,
    output logic        dm_m_axis_mm2s_tready,

    output logic [31:0] dm_s_axis_s2mm_tdata,
    output logic [3:0]  dm_s_axis_s2mm_tkeep,
    output logic        dm_s_axis_s2mm_tlast,
    output logic        dm_s_axis_s2mm_tvalid,
    input  logic        dm_s_axis_s2mm_tready,

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
    localparam logic [31:0] UART_BASE = 32'h1000_0000;
    localparam logic [31:0] TIMER_BASE = 32'h1001_0000;
    localparam logic [31:0] DM_BASE   = 32'h1002_0000;
    localparam logic [31:0] CTRL_BASE = 32'h1003_0000;
    localparam logic [31:0] IRQ_BASE  = 32'h1004_0000;
    localparam logic [31:0] GPU_BASE  = 32'h1007_0000;
    localparam logic [31:0] SCRATCH_BASE = 32'h2000_0000;
    localparam logic [31:0] DDR_BASE     = 32'h8000_0000;
    localparam int          ICACHE_LINES = 128;
    localparam int          DCACHE_LINES = 128;
    localparam int          ICACHE_INDEX_BITS = $clog2(ICACHE_LINES);
    localparam int          DCACHE_INDEX_BITS = $clog2(DCACHE_LINES);
    localparam int          ICACHE_TAG_BITS = 32 - ICACHE_INDEX_BITS - 2;
    localparam int          DCACHE_TAG_BITS = 32 - DCACHE_INDEX_BITS - 2;
    localparam int          CACHE_LINE_WORDS = 8;
    localparam logic [3:0]  CACHE_LINE_BEATS = 4'd8;

    logic        imem_valid;
    logic [31:0] imem_addr;
    logic        imem_ready;
    logic [31:0] imem_rdata;
    logic        bram_imem_valid;
    logic        bram_imem_ready;
    logic [31:0] bram_imem_rdata;
    logic        ddr_req_valid;
    logic        ddr_req_we;
    logic [3:0]  ddr_req_wstrb;
    logic [31:0] ddr_req_addr;
    logic [31:0] ddr_req_wdata;
    logic [3:0]  ddr_req_read_beats;
    logic        ddr_read_beat_valid;
    logic [3:0]  ddr_read_beat_index;
    logic [31:0] ddr_read_beat_data;
    logic        imem_ddr_selected;
    logic        imem_ddr_raw_selected;
    logic        icache_miss_start;
    logic        icache_miss_valid;
    logic [ICACHE_INDEX_BITS-1:0] icache_line_base_index;
    logic [ICACHE_INDEX_BITS-1:0] icache_miss_base_index;
    logic [ICACHE_TAG_BITS-1:0]   icache_miss_tag;
    logic [31:0] icache_miss_addr;
    logic [2:0]  icache_miss_word_offset;
    logic [31:0] icache_refill_rdata_q;
    logic [ICACHE_INDEX_BITS-1:0] icache_refill_index;
    logic [ICACHE_INDEX_BITS-1:0] icache_write_index;
    logic        icache_hit;
    logic [ICACHE_INDEX_BITS-1:0] icache_index;
    logic [ICACHE_TAG_BITS-1:0]   icache_tag;
    logic [ICACHE_LINES-1:0] icache_valid;
    (* ram_style = "distributed" *)
    logic [ICACHE_TAG_BITS-1:0] icache_tags [0:ICACHE_LINES-1];
    (* ram_style = "distributed" *)
    logic [31:0] icache_data [0:ICACHE_LINES-1];
    logic        bus_ddr_raw_selected;
    logic        dmem_ddr_raw_selected;
    logic        dmem_ddr_read_selected;
    logic        dcache_check_active;
    logic        dcache_lookup_hit;
    logic        dcache_miss_valid;
    logic [DCACHE_INDEX_BITS-1:0] dcache_miss_base_index;
    logic [DCACHE_INDEX_BITS-1:0] dcache_miss_index;
    logic [DCACHE_TAG_BITS-1:0]   dcache_miss_tag;
    logic [31:0] dcache_miss_addr;
    logic [2:0]  dcache_miss_word_offset;
    logic [31:0] dcache_refill_rdata_q;
    logic        dcache_resp_valid;
    logic [31:0] dcache_resp_rdata;
    logic [DCACHE_INDEX_BITS-1:0] dcache_index;
    logic [DCACHE_INDEX_BITS-1:0] dcache_line_base_index;
    logic [DCACHE_INDEX_BITS-1:0] dcache_refill_index;
    logic [DCACHE_INDEX_BITS-1:0] dcache_write_index;
    logic [DCACHE_TAG_BITS-1:0]   dcache_tag;
    logic [DCACHE_LINES-1:0] dcache_valid;
    (* ram_style = "distributed" *)
    logic [DCACHE_TAG_BITS-1:0] dcache_tags [0:DCACHE_LINES-1];
    (* ram_style = "distributed" *)
    logic [31:0] dcache_data [0:DCACHE_LINES-1];

    logic        dmem_valid;
    logic        dmem_we;
    logic [3:0]  dmem_wstrb;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic        dmem_ready;
    logic [31:0] dmem_rdata;

    logic        ram_dmem_valid;
    logic        ram_dmem_ready;
    logic [31:0] ram_dmem_rdata;
    logic        uart_valid;
    logic        uart_ready;
    logic [31:0] uart_rdata;
    logic        timer_valid;
    logic        timer_ready;
    logic [31:0] timer_rdata;
    logic        timer_irq;
    logic        irq_valid;
    logic        irq_ready;
    logic [31:0] irq_rdata;
    logic        irq_external;
    logic        gpu_valid;
    logic        gpu_ready;
    logic [31:0] gpu_rdata;
    logic        gpu_ddr_valid;
    logic [31:0] gpu_ddr_addr;
    logic [31:0] gpu_ddr_wdata;
    logic        gpu_ddr_ready;
    logic        gpu_ddr_start;
    logic        gpu_ddr_active;
    logic        gpu_ddr_inflight;
    logic [31:0] gpu_ddr_addr_q;
    logic [31:0] gpu_ddr_wdata_q;
    logic        dm_valid;
    logic        dm_ready;
    logic [31:0] dm_rdata;
    logic        ctrl_valid;
    logic        ctrl_ready;
    logic [31:0] ctrl_rdata;
    logic        scratch_valid;
    logic        scratch_ready;
    logic [31:0] scratch_rdata;
    logic        ddr_valid;
    logic        ddr_ready;
    logic [31:0] ddr_rdata;
    logic        bus_valid;
    logic        bus_we;
    logic [3:0]  bus_wstrb;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic        bus_ready;
    logic [31:0] bus_rdata;
    logic [31:0] dm_local_addr;
    logic [31:0] dm_length_bytes;
    logic        dm_mm2s_local_start;
    logic        dm_s2mm_local_start;
    logic        scratch_mm2s_ready;
    logic        scratch_mm2s_done;
    logic        scratch_mm2s_error;
    logic        scratch_s2mm_ready;
    logic        scratch_s2mm_done;
    logic        scratch_s2mm_error;
    logic        cpu_reset_req;
    logic [31:0] cpu_reset_vector;
    logic [31:0] dbg_core_state;
    logic [31:0] dbg_pc;
    logic [31:0] dbg_satp;
    logic [31:0] dbg_stvec;
    logic [31:0] dbg_sepc;
    logic [31:0] dbg_scause;
    logic [31:0] dbg_stval;
    logic [31:0] dbg_req_vaddr;
    logic [31:0] dbg_req_paddr;
    logic [31:0] dbg_ptw_pte_addr;
    logic [31:0] dbg_ptw_l1_pte;
    logic [31:0] dbg_ptw_l0_pte;
    logic [31:0] dbg_mcycle_lo;
    logic [31:0] dbg_mcycle_hi;
    logic [31:0] dbg_minstret_lo;
    logic [31:0] dbg_minstret_hi;
    logic [31:0] dbg_wfi_cycles_lo;
    logic [31:0] dbg_wfi_cycles_hi;
    logic [31:0] dbg_fetch_wait_cycles;
    logic [31:0] dbg_dmem_wait_cycles;
    logic [31:0] dbg_bus_state;
    logic [31:0] dbg_last_ddr_addr;
    logic [31:0] dbg_last_ddr_state;
    logic [31:0] dbg_last_imem_addr;
    logic [31:0] dbg_last_dmem_addr;
    logic [31:0] dbg_last_axi_araddr;
    logic [31:0] perf_imem_ddr_reqs;
    logic [31:0] perf_dmem_ddr_reqs;
    logic [31:0] perf_ddr_wait_cycles;
    logic [31:0] perf_icache_hits;
    logic [31:0] perf_icache_misses;
    logic [31:0] perf_dcache_hits;
    logic [31:0] perf_dcache_misses;
    logic [31:0] perf_icache_wait_cycles;
    logic [31:0] perf_dcache_wait_cycles;
    logic [31:0] perf_dmem_raw_wait_cycles;
    logic [31:0] perf_host_ddr_wait_cycles;
    logic [31:0] perf_icache_refill_beats;
    logic [31:0] perf_dcache_refill_beats;
    logic [31:0] perf_dmem_raw_reads;
    logic [31:0] perf_dmem_raw_writes;
    logic [31:0] perf_host_ddr_reqs;
    logic [31:0] perf_cache_invalidates;
    logic [31:0] perf_ddr_busy_cycles;
    logic [31:0] perf_icache_blocked_by_dbus_cycles;
    logic        ddr_req_from_dcache_refill;
    logic        ddr_req_from_dmem_raw;
    logic        ddr_req_from_host;
    logic        ddr_req_from_icache_refill;
    logic        ddr_req_from_gpu;
    logic        icache_live_critical;
    logic        dcache_live_critical;
    logic [31:0] icache_live_rdata;
    logic [31:0] dcache_live_rdata;
    logic        dcache_prefetch_valid;
    logic [31:0] dcache_prefetch_addr;
    logic [DCACHE_INDEX_BITS-1:0] dcache_prefetch_base_index;
    logic [DCACHE_TAG_BITS-1:0]   dcache_prefetch_tag;
    logic        dcache_prefetch_active;
    logic        dcache_prefetch_inflight;
    logic        dcache_prefetch_hit;
    logic        ddr_req_from_dcache_prefetch;
    logic        ddr_ready_for_demand;
    logic        dcache_last_read_line_valid;
    logic [31:0] dcache_last_read_line_addr;
    logic        dcache_stream_miss;
    logic        dcache_miss_stream;
    logic [31:0] dcache_current_line_addr;
    logic [31:0] dcache_next_line_addr;
    assign dcache_next_line_addr = {dcache_miss_addr[31:5] + 27'd1, 5'b00000};

    assign bus_valid = host_valid || dmem_valid;
    assign bus_we = host_valid ? host_we : dmem_we;
    assign bus_wstrb = host_valid ? host_wstrb : dmem_wstrb;
    assign bus_addr = host_valid ? host_addr : dmem_addr;
    assign bus_wdata = host_valid ? host_wdata : dmem_wdata;

    assign ram_dmem_valid = bus_valid && bus_addr[31:16] == 16'h0000;
    assign uart_valid = bus_valid && bus_addr[31:12] == UART_BASE[31:12];
    assign timer_valid = bus_valid && bus_addr[31:12] == TIMER_BASE[31:12];
    assign dm_valid = bus_valid && bus_addr[31:12] == DM_BASE[31:12];
    assign ctrl_valid = bus_valid && bus_addr[31:12] == CTRL_BASE[31:12];
    assign irq_valid = bus_valid && bus_addr[31:12] == IRQ_BASE[31:12];
    assign gpu_valid = bus_valid && bus_addr[31:12] == GPU_BASE[31:12];
    assign scratch_valid = bus_valid && bus_addr[31:20] == SCRATCH_BASE[31:20];
    assign bus_ddr_raw_selected = bus_valid && bus_addr[31:30] == 2'b10;
    assign dmem_ddr_raw_selected = !host_valid && bus_ddr_raw_selected;
    assign dmem_ddr_read_selected = dmem_ddr_raw_selected && !bus_we;
    assign dcache_index = bus_addr[DCACHE_INDEX_BITS+1:2];
    assign dcache_current_line_addr = {bus_addr[31:5], 5'b00000};
    assign dcache_line_base_index = {bus_addr[DCACHE_INDEX_BITS+1:5], 3'b000};
    assign dcache_tag = bus_addr[31:DCACHE_INDEX_BITS+2];
    assign dcache_write_index = bus_addr[DCACHE_INDEX_BITS+1:2];
    assign dcache_check_active = dmem_ddr_read_selected &&
                               !dcache_resp_valid &&
                               !dcache_miss_valid;
    assign dcache_lookup_hit = dcache_check_active &&
                               dcache_valid[dcache_index] &&
                               (dcache_tags[dcache_index] == dcache_tag);
    assign ddr_valid = dcache_miss_valid ||
                       (bus_ddr_raw_selected && !dcache_check_active && !(dmem_ddr_read_selected && dcache_resp_valid));
    assign bram_imem_valid = imem_valid && imem_addr[31:16] == 16'h0000;
    assign imem_ddr_raw_selected = !bus_ddr_raw_selected && !icache_miss_valid && imem_valid && imem_addr[31:30] == 2'b10;
    assign icache_index = imem_addr[ICACHE_INDEX_BITS+1:2];
    assign icache_line_base_index = {imem_addr[ICACHE_INDEX_BITS+1:5], 3'b000};
    assign icache_tag = imem_addr[31:ICACHE_INDEX_BITS+2];
    assign icache_write_index = bus_addr[ICACHE_INDEX_BITS+1:2];
    assign icache_hit = imem_ddr_raw_selected &&
                        icache_valid[icache_index] &&
                        (icache_tags[icache_index] == icache_tag);
    assign icache_miss_start = imem_ddr_raw_selected && !icache_hit;
    assign imem_ddr_selected = icache_miss_valid || icache_miss_start;
    assign gpu_ddr_start = gpu_ddr_valid && !gpu_ddr_inflight &&
                           !dcache_miss_valid && !ddr_valid && !imem_ddr_selected &&
                           !dcache_prefetch_active && !dcache_prefetch_inflight;
    assign gpu_ddr_active = gpu_ddr_inflight || gpu_ddr_start;
    assign ddr_req_valid = gpu_ddr_active || ddr_valid || imem_ddr_selected ||
                           dcache_prefetch_active || dcache_prefetch_inflight;
    assign ddr_req_we = gpu_ddr_active ? 1'b1 :
                        dcache_miss_valid ? 1'b0 : (ddr_valid && bus_we);
    assign ddr_req_wstrb = gpu_ddr_active ? 4'hf :
                           dcache_miss_valid ? 4'd0 : (ddr_valid ? bus_wstrb : 4'd0);
    assign ddr_req_addr = gpu_ddr_inflight ? gpu_ddr_addr_q :
                          gpu_ddr_start ? gpu_ddr_addr :
                          dcache_miss_valid ? dcache_miss_addr :
                          ddr_valid ? bus_addr :
                          icache_miss_valid ? icache_miss_addr :
                          imem_ddr_selected ? {imem_addr[31:5], 5'b00000} :
                          dcache_prefetch_addr;
    assign ddr_req_wdata = gpu_ddr_inflight ? gpu_ddr_wdata_q :
                           gpu_ddr_start ? gpu_ddr_wdata :
                           dcache_miss_valid ? 32'd0 : (ddr_valid ? bus_wdata : 32'd0);
    assign ddr_req_read_beats = (dcache_miss_valid || icache_miss_valid || icache_miss_start || dcache_prefetch_active) ?
                                CACHE_LINE_BEATS : 4'd1;
    assign dcache_prefetch_hit = dcache_prefetch_valid &&
                                 dcache_valid[dcache_prefetch_addr[DCACHE_INDEX_BITS+1:2]] &&
                                 (dcache_tags[dcache_prefetch_addr[DCACHE_INDEX_BITS+1:2]] ==
                                  dcache_prefetch_addr[31:DCACHE_INDEX_BITS+2]);
    assign dcache_prefetch_active = dcache_prefetch_valid && !dcache_prefetch_hit &&
                                    !dcache_prefetch_inflight &&
                                    !dcache_miss_valid && !ddr_valid && !imem_ddr_selected;
    assign ddr_ready_for_demand = ddr_ready && !dcache_prefetch_inflight && !gpu_ddr_inflight;
    assign dcache_stream_miss = dcache_last_read_line_valid &&
                                (dcache_current_line_addr == (dcache_last_read_line_addr + 32'd32));
    assign ddr_req_from_dcache_refill = dcache_miss_valid;
    assign ddr_req_from_dmem_raw = !dcache_miss_valid && ddr_valid && !host_valid;
    assign ddr_req_from_host = !dcache_miss_valid && ddr_valid && host_valid;
    assign ddr_req_from_icache_refill = !dcache_miss_valid && !ddr_valid && imem_ddr_selected;
    assign ddr_req_from_dcache_prefetch = !dcache_miss_valid && !ddr_valid && !imem_ddr_selected && dcache_prefetch_active;
    assign ddr_req_from_gpu = gpu_ddr_active;
    assign gpu_ddr_ready = ddr_ready && gpu_ddr_inflight;
    assign icache_refill_index = icache_miss_base_index + ddr_read_beat_index[2:0];
    assign dcache_refill_index = dcache_miss_base_index + ddr_read_beat_index[2:0];
    assign icache_live_critical = ddr_read_beat_valid && icache_miss_valid && !dcache_miss_valid &&
                                  (ddr_read_beat_index[2:0] == icache_miss_word_offset);
    assign dcache_live_critical = ddr_read_beat_valid && dcache_miss_valid &&
                                  (ddr_read_beat_index[2:0] == dcache_miss_word_offset);
    assign icache_live_rdata = icache_live_critical ? ddr_read_beat_data : icache_refill_rdata_q;
    assign dcache_live_rdata = dcache_live_critical ? ddr_read_beat_data : dcache_refill_rdata_q;
    assign imem_ready = bram_imem_valid ? bram_imem_ready :
                        icache_hit ? 1'b1 :
                        imem_ddr_selected ? ddr_ready_for_demand :
                        imem_valid;
    assign imem_rdata = bram_imem_valid ? bram_imem_rdata :
                        icache_hit ? icache_data[icache_index] :
                        imem_ddr_selected ? icache_live_rdata :
                        32'd0;
    assign dmem_ready = !host_valid && bus_ready;
    assign dmem_rdata = bus_rdata;
    assign host_ready = host_valid && bus_ready;
    assign host_rdata = bus_rdata;
    assign ctrl_ready = ctrl_valid;
    assign dbg_bus_state = {20'd0,
                            ddr_req_valid,
                            ddr_req_we,
                            ddr_ready,
                            ddr_valid,
                            imem_ddr_selected,
                            bus_valid,
                            bus_ready,
                            host_valid,
                            dmem_valid,
                            dmem_ready,
                            imem_valid,
                            imem_ready};

    always_comb begin
        ctrl_rdata = 32'd0;
        case (bus_addr[7:2])
            6'h00: ctrl_rdata = {31'd0, cpu_reset_req};
            6'h01: ctrl_rdata = {31'd0, cpu_reset_req};
            6'h02: ctrl_rdata = BRAM_WORDS;
            6'h03: ctrl_rdata = SCRATCH_WORDS;
            6'h04: ctrl_rdata = cpu_reset_vector;
            6'h08: ctrl_rdata = dbg_core_state;
            6'h09: ctrl_rdata = dbg_pc;
            6'h0a: ctrl_rdata = dbg_satp;
            6'h0b: ctrl_rdata = dbg_stvec;
            6'h0c: ctrl_rdata = dbg_sepc;
            6'h0d: ctrl_rdata = dbg_scause;
            6'h0e: ctrl_rdata = dbg_stval;
            6'h0f: ctrl_rdata = dbg_req_vaddr;
            6'h10: ctrl_rdata = dbg_req_paddr;
            6'h11: ctrl_rdata = dbg_ptw_pte_addr;
            6'h12: ctrl_rdata = dbg_ptw_l1_pte;
            6'h13: ctrl_rdata = dbg_ptw_l0_pte;
            6'h14: ctrl_rdata = dbg_bus_state;
            6'h15: ctrl_rdata = ddr_req_addr;
            6'h16: ctrl_rdata = imem_addr;
            6'h17: ctrl_rdata = dmem_addr;
            6'h18: ctrl_rdata = dbg_last_ddr_addr;
            6'h19: ctrl_rdata = dbg_last_ddr_state;
            6'h1a: ctrl_rdata = dbg_last_axi_araddr;
            6'h1b: ctrl_rdata = dbg_last_imem_addr;
            6'h1c: ctrl_rdata = dbg_last_dmem_addr;
            6'h20: ctrl_rdata = dbg_mcycle_lo;
            6'h21: ctrl_rdata = dbg_mcycle_hi;
            6'h22: ctrl_rdata = dbg_minstret_lo;
            6'h23: ctrl_rdata = dbg_minstret_hi;
            6'h24: ctrl_rdata = dbg_wfi_cycles_lo;
            6'h25: ctrl_rdata = dbg_wfi_cycles_hi;
            6'h26: ctrl_rdata = dbg_fetch_wait_cycles;
            6'h27: ctrl_rdata = dbg_dmem_wait_cycles;
            6'h28: ctrl_rdata = perf_imem_ddr_reqs;
            6'h29: ctrl_rdata = perf_dmem_ddr_reqs;
            6'h2a: ctrl_rdata = perf_ddr_wait_cycles;
            6'h2b: ctrl_rdata = perf_icache_hits;
            6'h2c: ctrl_rdata = perf_icache_misses;
            6'h2d: ctrl_rdata = perf_dcache_hits;
            6'h2e: ctrl_rdata = perf_dcache_misses;
            6'h2f: ctrl_rdata = perf_icache_wait_cycles;
            6'h30: ctrl_rdata = perf_dcache_wait_cycles;
            6'h31: ctrl_rdata = perf_dmem_raw_wait_cycles;
            6'h32: ctrl_rdata = perf_host_ddr_wait_cycles;
            6'h33: ctrl_rdata = perf_icache_refill_beats;
            6'h34: ctrl_rdata = perf_dcache_refill_beats;
            6'h35: ctrl_rdata = perf_dmem_raw_reads;
            6'h36: ctrl_rdata = perf_dmem_raw_writes;
            6'h37: ctrl_rdata = perf_host_ddr_reqs;
            6'h38: ctrl_rdata = perf_cache_invalidates;
            6'h39: ctrl_rdata = perf_ddr_busy_cycles;
            6'h3a: ctrl_rdata = perf_icache_blocked_by_dbus_cycles;
            default: ctrl_rdata = 32'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_reset_req <= 1'b0;
            cpu_reset_vector <= 32'd0;
        end else if (ctrl_valid && bus_we) begin
            if (bus_wstrb[0] && bus_addr[5:2] == 4'h0) begin
                cpu_reset_req <= bus_wdata[0];
            end
            if (bus_addr[5:2] == 4'h4) begin
                for (int i = 0; i < 4; i++) begin
                    if (bus_wstrb[i]) begin
                        cpu_reset_vector[i * 8 +: 8] <= bus_wdata[i * 8 +: 8];
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || cpu_reset_req) begin
            dbg_last_ddr_addr <= 32'd0;
            dbg_last_ddr_state <= 32'd0;
            dbg_last_imem_addr <= 32'd0;
            dbg_last_dmem_addr <= 32'd0;
            dbg_last_axi_araddr <= 32'd0;
            perf_imem_ddr_reqs <= 32'd0;
            perf_dmem_ddr_reqs <= 32'd0;
            perf_ddr_wait_cycles <= 32'd0;
            perf_icache_hits <= 32'd0;
            perf_icache_misses <= 32'd0;
            perf_dcache_hits <= 32'd0;
            perf_dcache_misses <= 32'd0;
            perf_icache_wait_cycles <= 32'd0;
            perf_dcache_wait_cycles <= 32'd0;
            perf_dmem_raw_wait_cycles <= 32'd0;
            perf_host_ddr_wait_cycles <= 32'd0;
            perf_icache_refill_beats <= 32'd0;
            perf_dcache_refill_beats <= 32'd0;
            perf_dmem_raw_reads <= 32'd0;
            perf_dmem_raw_writes <= 32'd0;
            perf_host_ddr_reqs <= 32'd0;
            perf_cache_invalidates <= 32'd0;
            perf_ddr_busy_cycles <= 32'd0;
            perf_icache_blocked_by_dbus_cycles <= 32'd0;
            icache_valid <= '0;
            icache_miss_valid <= 1'b0;
            icache_miss_base_index <= '0;
            icache_miss_tag <= '0;
            icache_miss_addr <= 32'd0;
            icache_miss_word_offset <= 3'd0;
            icache_refill_rdata_q <= 32'd0;
            dcache_valid <= '0;
            dcache_miss_valid <= 1'b0;
            dcache_miss_base_index <= '0;
            dcache_miss_index <= '0;
            dcache_miss_tag <= '0;
            dcache_miss_addr <= 32'd0;
            dcache_miss_word_offset <= 3'd0;
            dcache_refill_rdata_q <= 32'd0;
            dcache_resp_valid <= 1'b0;
            dcache_resp_rdata <= 32'd0;
            dcache_prefetch_valid <= 1'b0;
            dcache_prefetch_inflight <= 1'b0;
            dcache_prefetch_addr <= 32'd0;
            dcache_prefetch_base_index <= '0;
            dcache_prefetch_tag <= '0;
            dcache_last_read_line_valid <= 1'b0;
            dcache_last_read_line_addr <= 32'd0;
            dcache_miss_stream <= 1'b0;
            gpu_ddr_inflight <= 1'b0;
            gpu_ddr_addr_q <= 32'd0;
            gpu_ddr_wdata_q <= 32'd0;
        end else begin
            if (gpu_ddr_inflight && ddr_ready) begin
                gpu_ddr_inflight <= 1'b0;
            end else if (gpu_ddr_start) begin
                gpu_ddr_inflight <= 1'b1;
                gpu_ddr_addr_q <= gpu_ddr_addr;
                gpu_ddr_wdata_q <= gpu_ddr_wdata;
            end

            if (imem_ddr_raw_selected && icache_hit) begin
                perf_icache_hits <= perf_icache_hits + 32'd1;
            end
            if (icache_miss_start) begin
                icache_miss_valid <= 1'b1;
                icache_miss_base_index <= icache_line_base_index;
                icache_miss_tag <= icache_tag;
                icache_miss_addr <= {imem_addr[31:5], 5'b00000};
                icache_miss_word_offset <= imem_addr[4:2];
                icache_refill_rdata_q <= 32'd0;
            end
            if (dcache_lookup_hit) begin
                perf_dcache_hits <= perf_dcache_hits + 32'd1;
                dcache_resp_valid <= 1'b1;
                dcache_resp_rdata <= dcache_data[dcache_index];
                dcache_last_read_line_valid <= 1'b1;
                dcache_last_read_line_addr <= {bus_addr[31:5], 5'b00000};
            end else if (dcache_check_active) begin
                perf_dcache_misses <= perf_dcache_misses + 32'd1;
                dcache_miss_valid <= 1'b1;
                dcache_miss_base_index <= dcache_line_base_index;
                dcache_miss_index <= dcache_index;
                dcache_miss_tag <= dcache_tag;
                dcache_miss_addr <= {bus_addr[31:5], 5'b00000};
                dcache_miss_word_offset <= bus_addr[4:2];
                dcache_miss_stream <= dcache_stream_miss;
                dcache_refill_rdata_q <= 32'd0;
                dcache_prefetch_valid <= 1'b0;
                dcache_last_read_line_valid <= 1'b1;
                dcache_last_read_line_addr <= {bus_addr[31:5], 5'b00000};
            end else if (dcache_resp_valid && !host_valid && dmem_valid) begin
                dcache_resp_valid <= 1'b0;
            end
            if (dcache_prefetch_valid && dcache_prefetch_hit) begin
                dcache_prefetch_valid <= 1'b0;
            end
            if (ddr_req_valid && !ddr_ready) begin
                perf_ddr_wait_cycles <= perf_ddr_wait_cycles + 32'd1;
                if (ddr_req_from_dcache_refill) begin
                    perf_dcache_wait_cycles <= perf_dcache_wait_cycles + 32'd1;
                end else if (ddr_req_from_dmem_raw) begin
                    perf_dmem_raw_wait_cycles <= perf_dmem_raw_wait_cycles + 32'd1;
                end else if (ddr_req_from_host) begin
                    perf_host_ddr_wait_cycles <= perf_host_ddr_wait_cycles + 32'd1;
                end else if (ddr_req_from_icache_refill) begin
                    perf_icache_wait_cycles <= perf_icache_wait_cycles + 32'd1;
                end
            end
            if (ddr_req_valid) begin
                perf_ddr_busy_cycles <= perf_ddr_busy_cycles + 32'd1;
            end
            if (imem_ddr_selected && !ddr_req_from_icache_refill) begin
                perf_icache_blocked_by_dbus_cycles <= perf_icache_blocked_by_dbus_cycles + 32'd1;
            end
            if (ddr_read_beat_valid && icache_miss_valid && !dcache_miss_valid && !dcache_prefetch_inflight) begin
                perf_icache_refill_beats <= perf_icache_refill_beats + 32'd1;
                icache_valid[icache_refill_index] <= 1'b1;
                icache_tags[icache_refill_index] <= icache_miss_tag;
                icache_data[icache_refill_index] <= ddr_read_beat_data;
                if (ddr_read_beat_index[2:0] == icache_miss_word_offset) begin
                    icache_refill_rdata_q <= ddr_read_beat_data;
                end
            end
            if (ddr_read_beat_valid && dcache_miss_valid && !dcache_prefetch_inflight) begin
                perf_dcache_refill_beats <= perf_dcache_refill_beats + 32'd1;
                dcache_valid[dcache_refill_index] <= 1'b1;
                dcache_tags[dcache_refill_index] <= dcache_miss_tag;
                dcache_data[dcache_refill_index] <= ddr_read_beat_data;
                if (ddr_read_beat_index[2:0] == dcache_miss_word_offset) begin
                    dcache_refill_rdata_q <= ddr_read_beat_data;
                end
            end
            if (ddr_read_beat_valid && dcache_prefetch_inflight && !dcache_miss_valid && !icache_miss_valid) begin
                perf_dcache_refill_beats <= perf_dcache_refill_beats + 32'd1;
                dcache_valid[dcache_prefetch_base_index + ddr_read_beat_index[2:0]] <= 1'b1;
                dcache_tags[dcache_prefetch_base_index + ddr_read_beat_index[2:0]] <= dcache_prefetch_tag;
                dcache_data[dcache_prefetch_base_index + ddr_read_beat_index[2:0]] <= ddr_read_beat_data;
            end
            if (ddr_req_valid && ddr_ready) begin
                if (dcache_prefetch_inflight) begin
                    dcache_prefetch_valid <= 1'b0;
                    dcache_prefetch_inflight <= 1'b0;
                end else if (dcache_miss_valid) begin
                    perf_dmem_ddr_reqs <= perf_dmem_ddr_reqs + 32'd1;
                    dcache_miss_valid <= 1'b0;
                    dcache_resp_valid <= 1'b1;
                    dcache_resp_rdata <= dcache_live_rdata;
                    if (dcache_miss_stream && dcache_miss_addr[31:30] == 2'b10) begin
                        dcache_prefetch_valid <= 1'b1;
                        dcache_prefetch_inflight <= 1'b0;
                        dcache_prefetch_addr <= dcache_next_line_addr;
                        dcache_prefetch_base_index <= {dcache_next_line_addr[DCACHE_INDEX_BITS+1:5], 3'b000};
                        dcache_prefetch_tag <= dcache_next_line_addr[31:DCACHE_INDEX_BITS+2];
                    end
                end else if (imem_ddr_selected) begin
                    perf_imem_ddr_reqs <= perf_imem_ddr_reqs + 32'd1;
                    perf_icache_misses <= perf_icache_misses + 32'd1;
                    icache_miss_valid <= 1'b0;
                end else if (!host_valid && ddr_valid) begin
                    perf_dmem_ddr_reqs <= perf_dmem_ddr_reqs + 32'd1;
                    if (bus_we) begin
                        perf_dmem_raw_writes <= perf_dmem_raw_writes + 32'd1;
                    end else begin
                        perf_dmem_raw_reads <= perf_dmem_raw_reads + 32'd1;
                    end
                end else if (host_valid && ddr_valid) begin
                    perf_host_ddr_reqs <= perf_host_ddr_reqs + 32'd1;
                end
                if ((ddr_valid && bus_we) || ddr_req_from_gpu) begin
                    perf_cache_invalidates <= perf_cache_invalidates + 32'd1;
                    icache_miss_valid <= 1'b0;
                    dcache_miss_valid <= 1'b0;
                    dcache_resp_valid <= 1'b0;
                    dcache_prefetch_valid <= 1'b0;
                    dcache_prefetch_inflight <= 1'b0;
                    icache_valid[ddr_req_addr[ICACHE_INDEX_BITS+1:2]] <= 1'b0;
                    dcache_valid[ddr_req_addr[DCACHE_INDEX_BITS+1:2]] <= 1'b0;
                end
            end else if (dcache_prefetch_active) begin
                dcache_prefetch_inflight <= 1'b1;
            end
            if (ddr_req_valid && !host_valid) begin
                dbg_last_ddr_addr <= ddr_req_addr;
                dbg_last_ddr_state <= dbg_bus_state;
                dbg_last_imem_addr <= imem_addr;
                dbg_last_dmem_addr <= dmem_addr;
                dbg_last_axi_araddr <= M_AXI_DDR_ARADDR;
            end
        end
    end

    always_comb begin
        bus_ready = bus_valid;
        bus_rdata = 32'd0;

        if (ram_dmem_valid) begin
            bus_ready = ram_dmem_ready;
            bus_rdata = ram_dmem_rdata;
        end else if (dcache_resp_valid && !host_valid && dmem_valid) begin
            bus_ready = 1'b1;
            bus_rdata = dcache_resp_rdata;
        end else if (dcache_check_active || dcache_miss_valid) begin
            bus_ready = 1'b0;
            bus_rdata = 32'd0;
        end else if (uart_valid) begin
            bus_ready = uart_ready;
            bus_rdata = uart_rdata;
        end else if (timer_valid) begin
            bus_ready = timer_ready;
            bus_rdata = timer_rdata;
        end else if (irq_valid) begin
            bus_ready = irq_ready;
            bus_rdata = irq_rdata;
        end else if (gpu_valid) begin
            bus_ready = gpu_ready;
            bus_rdata = gpu_rdata;
        end else if (dm_valid) begin
            bus_ready = dm_ready;
            bus_rdata = dm_rdata;
        end else if (ctrl_valid) begin
            bus_ready = ctrl_ready;
            bus_rdata = ctrl_rdata;
        end else if (scratch_valid) begin
            bus_ready = scratch_ready;
            bus_rdata = scratch_rdata;
        end else if (ddr_valid) begin
            bus_ready = ddr_ready_for_demand;
            bus_rdata = ddr_rdata;
        end
    end

    zx32_core u_core (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(cpu_reset_req),
        .reset_vector(cpu_reset_vector),
        .irq_timer(timer_irq),
        .irq_external(irq_external),
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
        .dbg_core_state(dbg_core_state),
        .dbg_pc(dbg_pc),
        .dbg_satp(dbg_satp),
        .dbg_stvec(dbg_stvec),
        .dbg_sepc(dbg_sepc),
        .dbg_scause(dbg_scause),
        .dbg_stval(dbg_stval),
        .dbg_req_vaddr(dbg_req_vaddr),
        .dbg_req_paddr(dbg_req_paddr),
        .dbg_ptw_pte_addr(dbg_ptw_pte_addr),
        .dbg_ptw_l1_pte(dbg_ptw_l1_pte),
        .dbg_ptw_l0_pte(dbg_ptw_l0_pte),
        .dbg_mcycle_lo(dbg_mcycle_lo),
        .dbg_mcycle_hi(dbg_mcycle_hi),
        .dbg_minstret_lo(dbg_minstret_lo),
        .dbg_minstret_hi(dbg_minstret_hi),
        .dbg_wfi_cycles_lo(dbg_wfi_cycles_lo),
        .dbg_wfi_cycles_hi(dbg_wfi_cycles_hi),
        .dbg_fetch_wait_cycles(dbg_fetch_wait_cycles),
        .dbg_dmem_wait_cycles(dbg_dmem_wait_cycles)
    );

    simple_ram #(.WORDS(BRAM_WORDS)) u_bram (
        .clk(clk),
        .imem_valid(bram_imem_valid),
        .imem_addr(imem_addr),
        .imem_ready(bram_imem_ready),
        .imem_rdata(bram_imem_rdata),
        .dmem_valid(ram_dmem_valid),
        .dmem_we(bus_we),
        .dmem_wstrb(bus_wstrb),
        .dmem_addr(bus_addr),
        .dmem_wdata(bus_wdata),
        .dmem_ready(ram_dmem_ready),
        .dmem_rdata(ram_dmem_rdata)
    );

    mmio_uart_tx #(.CLK_HZ(CLK_HZ)) u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .valid(uart_valid),
        .we(bus_we),
        .wstrb(bus_wstrb),
        .addr(bus_addr),
        .wdata(bus_wdata),
        .ready(uart_ready),
        .rdata(uart_rdata),
        .tx(uart_tx)
    );

    mmio_timer u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .valid(timer_valid),
        .we(bus_we),
        .wstrb(bus_wstrb),
        .addr(bus_addr),
        .wdata(bus_wdata),
        .ready(timer_ready),
        .rdata(timer_rdata),
        .irq_timer(timer_irq)
    );

    mmio_irqctrl u_irqctrl (
        .clk(clk),
        .rst_n(rst_n),
        .valid(irq_valid),
        .we(bus_we),
        .wstrb(bus_wstrb),
        .addr(bus_addr),
        .wdata(bus_wdata),
        .ready(irq_ready),
        .rdata(irq_rdata),
        .source_irq(8'd0),
        .irq_external(irq_external)
    );

    mmio_gpu_fill u_gpu (
        .clk(clk),
        .rst_n(rst_n),
        .valid(gpu_valid),
        .we(bus_we),
        .wstrb(bus_wstrb),
        .addr(bus_addr),
        .wdata(bus_wdata),
        .ready(gpu_ready),
        .rdata(gpu_rdata),
        .ddr_valid(gpu_ddr_valid),
        .ddr_addr(gpu_ddr_addr),
        .ddr_wdata(gpu_ddr_wdata),
        .ddr_ready(gpu_ddr_ready)
    );

    datamover_ctrl u_datamover_ctrl (
        .clk(clk),
        .rst_n(rst_n),
        .valid(dm_valid),
        .we(bus_we),
        .wstrb(bus_wstrb),
        .addr(bus_addr),
        .wdata(bus_wdata),
        .ready(dm_ready),
        .rdata(dm_rdata),
        .mm2s_cmd_valid(dm_mm2s_cmd_valid),
        .mm2s_cmd_ready(dm_mm2s_cmd_ready),
        .mm2s_cmd_data(dm_mm2s_cmd_data),
        .mm2s_sts_valid(dm_mm2s_sts_valid),
        .mm2s_sts_ready(dm_mm2s_sts_ready),
        .mm2s_sts_data(dm_mm2s_sts_data),
        .s2mm_cmd_valid(dm_s2mm_cmd_valid),
        .s2mm_cmd_ready(dm_s2mm_cmd_ready),
        .s2mm_cmd_data(dm_s2mm_cmd_data),
        .s2mm_sts_valid(dm_s2mm_sts_valid),
        .s2mm_sts_ready(dm_s2mm_sts_ready),
        .s2mm_sts_data(dm_s2mm_sts_data),
        .local_addr_o(dm_local_addr),
        .length_bytes_o(dm_length_bytes),
        .mm2s_local_start(dm_mm2s_local_start),
        .mm2s_local_ready(scratch_mm2s_ready),
        .s2mm_local_start(dm_s2mm_local_start),
        .s2mm_local_ready(scratch_s2mm_ready)
    );

    axis_scratchpad #(.WORDS(SCRATCH_WORDS)) u_scratchpad (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_valid(scratch_valid),
        .cpu_we(bus_we),
        .cpu_wstrb(bus_wstrb),
        .cpu_addr(bus_addr),
        .cpu_wdata(bus_wdata),
        .cpu_ready(scratch_ready),
        .cpu_rdata(scratch_rdata),
        .mm2s_start(dm_mm2s_local_start),
        .mm2s_local_addr(dm_local_addr),
        .mm2s_length_bytes(dm_length_bytes),
        .mm2s_ready(scratch_mm2s_ready),
        .mm2s_done(scratch_mm2s_done),
        .mm2s_error(scratch_mm2s_error),
        .s_axis_mm2s_tdata(dm_m_axis_mm2s_tdata),
        .s_axis_mm2s_tkeep(dm_m_axis_mm2s_tkeep),
        .s_axis_mm2s_tlast(dm_m_axis_mm2s_tlast),
        .s_axis_mm2s_tvalid(dm_m_axis_mm2s_tvalid),
        .s_axis_mm2s_tready(dm_m_axis_mm2s_tready),
        .s2mm_start(dm_s2mm_local_start),
        .s2mm_local_addr(dm_local_addr),
        .s2mm_length_bytes(dm_length_bytes),
        .s2mm_ready(scratch_s2mm_ready),
        .s2mm_done(scratch_s2mm_done),
        .s2mm_error(scratch_s2mm_error),
        .m_axis_s2mm_tdata(dm_s_axis_s2mm_tdata),
        .m_axis_s2mm_tkeep(dm_s_axis_s2mm_tkeep),
        .m_axis_s2mm_tlast(dm_s_axis_s2mm_tlast),
        .m_axis_s2mm_tvalid(dm_s_axis_s2mm_tvalid),
        .m_axis_s2mm_tready(dm_s_axis_s2mm_tready)
    );

    axi4_master_bridge #(
        .CPU_BASE_ADDR(DDR_BASE),
        .PHYS_BASE_ADDR(32'h0000_0000)
    ) u_ddr_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .valid(ddr_req_valid),
        .we(ddr_req_we),
        .wstrb(ddr_req_wstrb),
        .addr(ddr_req_addr),
        .wdata(ddr_req_wdata),
        .read_beats(ddr_req_read_beats),
        .ready(ddr_ready),
        .rdata(ddr_rdata),
        .read_beat_valid(ddr_read_beat_valid),
        .read_beat_index(ddr_read_beat_index),
        .read_beat_data(ddr_read_beat_data),
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
