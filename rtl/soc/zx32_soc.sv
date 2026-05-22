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
    localparam logic [31:0] SCRATCH_BASE = 32'h2000_0000;
    localparam logic [31:0] DDR_BASE     = 32'h8000_0000;

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
    logic        imem_ddr_selected;

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
    logic        core_rst_n;
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
    logic [31:0] dbg_bus_state;
    logic [31:0] dbg_last_ddr_addr;
    logic [31:0] dbg_last_ddr_state;
    logic [31:0] dbg_last_imem_addr;
    logic [31:0] dbg_last_dmem_addr;
    logic [31:0] dbg_last_axi_araddr;

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
    assign scratch_valid = bus_valid && bus_addr[31:20] == SCRATCH_BASE[31:20];
    assign ddr_valid     = bus_valid && bus_addr[31:28] == 4'h8;
    assign bram_imem_valid = imem_valid && imem_addr[31:16] == 16'h0000;
    assign imem_ddr_selected = !ddr_valid && imem_valid && imem_addr[31:28] == 4'h8;
    assign ddr_req_valid = ddr_valid || imem_ddr_selected;
    assign ddr_req_we = ddr_valid && bus_we;
    assign ddr_req_wstrb = ddr_valid ? bus_wstrb : 4'd0;
    assign ddr_req_addr = ddr_valid ? bus_addr : imem_addr;
    assign ddr_req_wdata = ddr_valid ? bus_wdata : 32'd0;
    assign imem_ready = bram_imem_valid ? bram_imem_ready :
                        imem_ddr_selected ? ddr_ready :
                        imem_valid;
    assign imem_rdata = bram_imem_valid ? bram_imem_rdata :
                        imem_ddr_selected ? ddr_rdata :
                        32'd0;
    assign dmem_ready = !host_valid && bus_ready;
    assign dmem_rdata = bus_rdata;
    assign host_ready = host_valid && bus_ready;
    assign host_rdata = bus_rdata;
    assign ctrl_ready = ctrl_valid;
    assign core_rst_n = rst_n && !cpu_reset_req;
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
            default: ctrl_rdata = 32'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_reset_req <= 1'b0;
            cpu_reset_vector <= 32'd0;
            dbg_last_ddr_addr <= 32'd0;
            dbg_last_ddr_state <= 32'd0;
            dbg_last_imem_addr <= 32'd0;
            dbg_last_dmem_addr <= 32'd0;
            dbg_last_axi_araddr <= 32'd0;
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
        end else begin
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
        end else if (uart_valid) begin
            bus_ready = uart_ready;
            bus_rdata = uart_rdata;
        end else if (timer_valid) begin
            bus_ready = timer_ready;
            bus_rdata = timer_rdata;
        end else if (irq_valid) begin
            bus_ready = irq_ready;
            bus_rdata = irq_rdata;
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
            bus_ready = ddr_ready;
            bus_rdata = ddr_rdata;
        end
    end

    zx32_core u_core (
        .clk(clk),
        .rst_n(core_rst_n),
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
        .dbg_ptw_l0_pte(dbg_ptw_l0_pte)
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
        .PHYS_BASE_ADDR(32'h0010_0000)
    ) u_ddr_bridge (
        .clk(clk),
        .rst_n(rst_n),
        .valid(ddr_req_valid),
        .we(ddr_req_we),
        .wstrb(ddr_req_wstrb),
        .addr(ddr_req_addr),
        .wdata(ddr_req_wdata),
        .ready(ddr_ready),
        .rdata(ddr_rdata),
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
