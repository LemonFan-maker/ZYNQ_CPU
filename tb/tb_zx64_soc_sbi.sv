module tb_zx64_soc_sbi;
    localparam int BRAM_WORDS = 1024;
    localparam int FW_ENTRY = 32'h0000_0000;
    localparam int M_TRAP = 32'h0000_0100;
    localparam int S_PAYLOAD = 32'h0000_0400;
    localparam int S_TRAP = 32'h0000_0600;
    localparam int RESULT_BASE = 32'h0000_0800;
    localparam logic [63:0] DTB_ADDR = 64'h0000_0000_8000_1000;
    parameter bit USE_CORE5 = 1'b0;

    logic clk;
    logic rst_n;
    logic irq_external_i;
    logic uart_tx;
    logic core_halted;
    logic core_illegal;
    logic [31:0] dbg_core_state;
    logic [63:0] dbg_pc;
    logic [31:0] dbg_instr;
    logic [31:0] dbg_icache_hits;
    logic [31:0] dbg_icache_misses;
    logic [31:0] dbg_dcache_hits;
    logic [31:0] dbg_dcache_misses;
    logic [31:0] dbg_cache_invalidates;
    logic [3:0]  M_AXI_DDR_AWID;
    logic [31:0] M_AXI_DDR_AWADDR;
    logic [7:0]  M_AXI_DDR_AWLEN;
    logic [2:0]  M_AXI_DDR_AWSIZE;
    logic [1:0]  M_AXI_DDR_AWBURST;
    logic        M_AXI_DDR_AWLOCK;
    logic [3:0]  M_AXI_DDR_AWCACHE;
    logic [2:0]  M_AXI_DDR_AWPROT;
    logic [3:0]  M_AXI_DDR_AWQOS;
    logic        M_AXI_DDR_AWVALID;
    logic        M_AXI_DDR_AWREADY;
    logic [31:0] M_AXI_DDR_WDATA;
    logic [3:0]  M_AXI_DDR_WSTRB;
    logic        M_AXI_DDR_WLAST;
    logic        M_AXI_DDR_WVALID;
    logic        M_AXI_DDR_WREADY;
    logic [3:0]  M_AXI_DDR_BID;
    logic [1:0]  M_AXI_DDR_BRESP;
    logic        M_AXI_DDR_BVALID;
    logic        M_AXI_DDR_BREADY;
    logic [3:0]  M_AXI_DDR_ARID;
    logic [31:0] M_AXI_DDR_ARADDR;
    logic [7:0]  M_AXI_DDR_ARLEN;
    logic [2:0]  M_AXI_DDR_ARSIZE;
    logic [1:0]  M_AXI_DDR_ARBURST;
    logic        M_AXI_DDR_ARLOCK;
    logic [3:0]  M_AXI_DDR_ARCACHE;
    logic [2:0]  M_AXI_DDR_ARPROT;
    logic [3:0]  M_AXI_DDR_ARQOS;
    logic        M_AXI_DDR_ARVALID;
    logic        M_AXI_DDR_ARREADY;
    logic [3:0]  M_AXI_DDR_RID;
    logic [31:0] M_AXI_DDR_RDATA;
    logic [1:0]  M_AXI_DDR_RRESP;
    logic        M_AXI_DDR_RLAST;
    logic        M_AXI_DDR_RVALID;
    logic        M_AXI_DDR_RREADY;

    integer pcw;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    zx64_soc #(
        .BRAM_WORDS(BRAM_WORDS),
        .CLK_HZ(1_000_000),
        .USE_CORE5(USE_CORE5)
    ) u_soc (
        .clk(clk),
        .rst_n(rst_n),
        .soft_reset(1'b0),
        .reset_vector({32'd0, FW_ENTRY}),
        .irq_external_i(irq_external_i),
        .virtio_blk_capacity_sectors(64'd0),
        .virtio_blk_backend_irq(1'b0),
        .virtio_blk_notify_ack(1'b0),
        .virtio_blk_notify_pending(),
        .virtio_blk_notify_queue(),
        .virtio_blk_notify_count(),
        .virtio_blk_queue_num(),
        .virtio_blk_queue_ready(),
        .virtio_blk_queue_desc_addr(),
        .virtio_blk_queue_avail_addr(),
        .virtio_blk_queue_used_addr(),
        .virtio_blk_irq_pending(),
        .virtio_blk_device_status(),
        .virtio_input_backend_irq(1'b0),
        .virtio_input_notify_ack(1'b0),
        .virtio_input_notify_pending(),
        .virtio_input_notify_queue(),
        .virtio_input_notify_count(),
        .virtio_input_irq_pending(),
        .virtio_input_device_status(),
        .virtio_input_event_queue_num(),
        .virtio_input_event_queue_ready(),
        .virtio_input_event_queue_desc_addr(),
        .virtio_input_event_queue_avail_addr(),
        .virtio_input_event_queue_used_addr(),
        .virtio_input_status_queue_num(),
        .virtio_input_status_queue_ready(),
        .virtio_input_status_queue_desc_addr(),
        .virtio_input_status_queue_avail_addr(),
        .virtio_input_status_queue_used_addr(),
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
        .host_valid(1'b0),
        .host_we(1'b0),
        .host_wstrb(4'd0),
        .host_addr(32'd0),
        .host_wdata(32'd0),
        .host_ready(),
        .host_rdata(),
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

    assign M_AXI_DDR_AWREADY = 1'b0;
    assign M_AXI_DDR_WREADY = 1'b0;
    assign M_AXI_DDR_BID = 4'd0;
    assign M_AXI_DDR_BRESP = 2'd0;
    assign M_AXI_DDR_BVALID = 1'b0;
    assign M_AXI_DDR_ARREADY = 1'b0;
    assign M_AXI_DDR_RID = 4'd0;
    assign M_AXI_DDR_RDATA = 32'd0;
    assign M_AXI_DDR_RRESP = 2'd0;
    assign M_AXI_DDR_RLAST = 1'b0;
    assign M_AXI_DDR_RVALID = 1'b0;

    function automatic logic [31:0] enc_r(input logic [6:0] funct7,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_i(input logic signed [11:0] imm,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_i = {imm[11:0], rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_s(input logic signed [11:0] imm,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [6:0] opcode);
        enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] enc_b(input logic signed [12:0] imm,
                                          input logic [4:0] rs2,
                                          input logic [4:0] rs1,
                                          input logic [2:0] funct3,
                                          input logic [6:0] opcode);
        enc_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] enc_u(input logic [19:0] imm20,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_u = {imm20, rd, opcode};
    endfunction

    function automatic logic [31:0] enc_j(input logic signed [20:0] imm,
                                          input logic [4:0] rd,
                                          input logic [6:0] opcode);
        enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    function automatic logic [31:0] enc_csr(input logic [11:0] csr,
                                            input logic [4:0] rs1,
                                            input logic [2:0] funct3,
                                            input logic [4:0] rd);
        enc_csr = {csr, rs1, funct3, rd, 7'b1110011};
    endfunction

    task automatic emit(input logic [31:0] inst);
        begin
            if (pcw[0]) begin
                u_soc.u_ram.mem[pcw >> 1][63:32] = inst;
            end else begin
                u_soc.u_ram.mem[pcw >> 1][31:0] = inst;
            end
            pcw = pcw + 1;
        end
    endtask

    task automatic seek(input int byte_addr);
        begin
            pcw = byte_addr >> 2;
        end
    endtask

    task automatic emit_j(input int target_byte);
        logic signed [20:0] delta;
        begin
            delta = target_byte - (pcw << 2);
            emit(enc_j(delta, 5'd0, 7'b1101111));
        end
    endtask

    task automatic emit_beq(input logic [4:0] rs1,
                            input logic [4:0] rs2,
                            input int target_byte);
        logic signed [12:0] delta;
        begin
            delta = target_byte - (pcw << 2);
            emit(enc_b(delta, rs2, rs1, 3'b000, 7'b1100011));
        end
    endtask

    task automatic emit_bne(input logic [4:0] rs1,
                            input logic [4:0] rs2,
                            input int target_byte);
        logic signed [12:0] delta;
        begin
            delta = target_byte - (pcw << 2);
            emit(enc_b(delta, rs2, rs1, 3'b001, 7'b1100011));
        end
    endtask

    task automatic li_small(input logic [4:0] rd, input logic signed [11:0] imm);
        begin
            emit(enc_i(imm, 5'd0, 3'b000, rd, 7'b0010011));
        end
    endtask

    task automatic li_const32(input logic [4:0] rd, input logic [31:0] value);
        logic [31:0] upper;
        logic signed [11:0] lower;
        begin
            upper = (value + 32'h0000_0800) >> 12;
            lower = value[11:0];
            emit(enc_u(upper[19:0], rd, 7'b0110111));
            if (lower != 12'sd0) begin
                emit(enc_i(lower, rd, 3'b000, rd, 7'b0010011));
            end
        end
    endtask

    task automatic li_result_base(input logic [4:0] rd);
        begin
            li_small(rd, 12'sd1);
            emit(enc_i(12'sd11, rd, 3'b001, rd, 7'b0010011)); // rd = 0x800.
        end
    endtask

    task automatic li_dtb_addr(input logic [4:0] rd, input logic [4:0] tmp);
        begin
            li_small(rd, 12'sd1);
            emit(enc_i(12'sd31, rd, 3'b001, rd, 7'b0010011)); // rd = 0x80000000.
            li_small(tmp, 12'sd1);
            emit(enc_i(12'sd12, tmp, 3'b001, tmp, 7'b0010011)); // tmp = 0x1000.
            emit(enc_r(7'b0000000, tmp, rd, 3'b000, rd, 7'b0110011));
        end
    endtask

    task automatic emit_return_sbi;
        begin
            emit(32'h3020_0073); // mret
        end
    endtask

    task automatic expect64(input int byte_addr, input logic [63:0] expected, input string label);
        int idx;
        begin
            idx = byte_addr >> 3;
            if (u_soc.u_ram.mem[idx] !== expected) begin
                $fatal(1, "%s expected mem[%0d]=%016x got %016x pc=%016x instr=%08x state=%08x illegal=%0d",
                       label, idx, expected, u_soc.u_ram.mem[idx],
                       dbg_pc, dbg_instr, dbg_core_state, core_illegal);
            end
        end
    endtask

    task automatic expect_mask64(input int byte_addr,
                                 input logic [63:0] mask,
                                 input logic [63:0] expected,
                                 input string label);
        int idx;
        begin
            idx = byte_addr >> 3;
            if ((u_soc.u_ram.mem[idx] & mask) !== expected) begin
                $fatal(1, "%s expected mem[%0d]&%016x=%016x got %016x pc=%016x instr=%08x state=%08x illegal=%0d",
                       label, idx, mask, expected, u_soc.u_ram.mem[idx] & mask,
                       dbg_pc, dbg_instr, dbg_core_state, core_illegal);
            end
        end
    endtask

    initial begin
        irq_external_i = 1'b0;
        rst_n = 1'b0;

        for (int i = 0; i < BRAM_WORDS; i++) begin
            u_soc.u_ram.mem[i] = 64'd0;
        end

        seek(FW_ENTRY);
        emit(enc_u(20'h10010, 5'd29, 7'b0110111));                 // lui   t4, 0x10010
        emit(enc_s(12'sd0, 5'd0, 5'd29, 3'b010, 7'b0100011));      // sw    x0, 0(t4)
        emit(enc_s(12'sd4, 5'd0, 5'd29, 3'b010, 7'b0100011));      // sw    x0, 4(t4)
        li_small(5'd5, M_TRAP[11:0]);                               // addi  t0, x0, m_trap
        emit(enc_csr(12'h305, 5'd5, 3'b001, 5'd0));                // csrw  mtvec, t0
        li_small(5'd5, 12'sd32);
        emit(enc_csr(12'h303, 5'd5, 3'b001, 5'd0));                // csrw  mideleg, t0
        li_small(5'd5, 12'sd7);
        emit(enc_csr(12'h306, 5'd5, 3'b001, 5'd0));                // csrw  mcounteren, t0
        li_small(5'd10, 12'sd0);                                    // li    a0, 0
        li_dtb_addr(5'd11, 5'd12);                                  // li    a1, DTB_ADDR
        li_small(5'd5, S_PAYLOAD[11:0]);
        emit(enc_csr(12'h341, 5'd5, 3'b001, 5'd0));                // csrw  mepc, t0
        emit(enc_u(20'h00001, 5'd5, 7'b0110111));                  // lui   t0, 0x1
        emit(enc_i(-12'sd2048, 5'd5, 3'b000, 5'd5, 7'b0010011));   // addi  t0, t0, -2048
        emit(enc_csr(12'h300, 5'd5, 3'b001, 5'd0));                // csrw  mstatus, t0 (MPP=S)
        emit(32'h3020_0073);                                        // mret

        seek(M_TRAP);
        emit(enc_csr(12'h342, 5'd0, 3'b010, 5'd6));                // csrr  t1, mcause
        li_small(5'd7, 12'sd9);
        emit_bne(5'd6, 5'd7, 32'h0000_0250);
        emit(enc_csr(12'h341, 5'd0, 3'b010, 5'd5));                // csrr  t0, mepc
        emit(enc_i(12'sd4, 5'd5, 3'b000, 5'd5, 7'b0010011));       // addi  t0, t0, 4
        emit(enc_csr(12'h341, 5'd5, 3'b001, 5'd0));                // csrw  mepc, t0
        li_small(5'd7, 12'sd16);
        emit_beq(5'd17, 5'd7, 32'h0000_0300);                      // beq   a7, 0x10, sbi_base
        li_small(5'd7, 12'sd1);
        emit_beq(5'd17, 5'd7, 32'h0000_01e0);                      // beq   a7, 1, putchar
        emit_beq(5'd17, 5'd0, 32'h0000_0200);                      // beq   a7, 0, set_timer
        li_small(5'd7, 12'sd2);
        emit_beq(5'd17, 5'd7, 32'h0000_0230);                      // beq   a7, 2, getchar
        li_const32(5'd7, 32'h5449_4d45);
        emit_beq(5'd17, 5'd7, 32'h0000_0200);                      // beq   a7, TIME, set_timer
        li_const32(5'd7, 32'h0073_5049);
        emit_beq(5'd17, 5'd7, 32'h0000_0260);                      // beq   a7, IPI
        li_const32(5'd7, 32'h5246_4e43);
        emit_beq(5'd17, 5'd7, 32'h0000_0270);                      // beq   a7, RFENCE
        li_const32(5'd7, 32'h0048_534d);
        emit_beq(5'd17, 5'd7, 32'h0000_0280);                      // beq   a7, HSM
        li_const32(5'd7, 32'h4442_434e);
        emit_beq(5'd17, 5'd7, 32'h0000_0290);                      // beq   a7, DBCN
        emit_j(32'h0000_0240);

        seek(32'h0000_0300);
        emit_beq(5'd16, 5'd0, 32'h0000_0180);                      // fid 0: spec version
        li_small(5'd7, 12'sd1);
        emit_beq(5'd16, 5'd7, 32'h0000_0190);                      // fid 1: impl id
        li_small(5'd7, 12'sd2);
        emit_beq(5'd16, 5'd7, 32'h0000_01a0);                      // fid 2: impl version
        li_small(5'd7, 12'sd3);
        emit_beq(5'd16, 5'd7, 32'h0000_0340);                      // fid 3: probe extension
        li_small(5'd7, 12'sd4);
        emit_beq(5'd16, 5'd7, 32'h0000_02d0);                      // fid 4: mvendorid
        li_small(5'd7, 12'sd5);
        emit_beq(5'd16, 5'd7, 32'h0000_02e0);                      // fid 5: marchid
        li_small(5'd7, 12'sd6);
        emit_beq(5'd16, 5'd7, 32'h0000_02f0);                      // fid 6: mimpid
        emit_j(32'h0000_0240);

        seek(32'h0000_0180);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd2);
        emit_return_sbi();

        seek(32'h0000_0190);
        li_small(5'd10, 12'sd0);
        li_const32(5'd11, 32'h0000_5a32);
        emit_return_sbi();

        seek(32'h0000_01a0);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd1);
        emit_return_sbi();

        seek(32'h0000_0340);
        li_small(5'd11, 12'sd0);
        emit_beq(5'd10, 5'd0, 32'h0000_01d0);
        li_small(5'd7, 12'sd1);
        emit_beq(5'd10, 5'd7, 32'h0000_01d0);
        li_small(5'd7, 12'sd2);
        emit_beq(5'd10, 5'd7, 32'h0000_01d0);
        li_small(5'd7, 12'sd16);
        emit_beq(5'd10, 5'd7, 32'h0000_01d0);
        li_const32(5'd7, 32'h5449_4d45);
        emit_beq(5'd10, 5'd7, 32'h0000_01d0);
        li_const32(5'd7, 32'h0073_5049);
        emit_beq(5'd10, 5'd7, 32'h0000_01d0);
        li_const32(5'd7, 32'h5246_4e43);
        emit_beq(5'd10, 5'd7, 32'h0000_01d0);
        li_const32(5'd7, 32'h0048_534d);
        emit_beq(5'd10, 5'd7, 32'h0000_01d0);
        li_small(5'd10, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_01d0);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd1);
        emit_return_sbi();

        seek(32'h0000_01e0);
        emit(enc_u(20'h10000, 5'd29, 7'b0110111));                 // lui   t4, 0x10000
        emit(enc_s(12'sd0, 5'd10, 5'd29, 3'b010, 7'b0100011));     // sw    a0, 0(t4)
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_0200);
        emit(enc_u(20'h10010, 5'd29, 7'b0110111));                 // lui   t4, 0x10010
        li_small(5'd7, -12'sd1);
        emit(enc_s(12'sd12, 5'd7, 5'd29, 3'b010, 7'b0100011));     // sw    -1, mtimecmp_hi
        emit(enc_s(12'sd8, 5'd10, 5'd29, 3'b010, 7'b0100011));     // sw    a0, mtimecmp_lo
        emit(enc_s(12'sd12, 5'd11, 5'd29, 3'b010, 7'b0100011));    // sw    a1, mtimecmp_hi
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_0230);
        li_small(5'd10, -12'sd1);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_0240);
        li_small(5'd10, -12'sd2);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_0250);
        li_result_base(5'd31);
        emit(enc_s(12'sd120, 5'd6, 5'd31, 3'b011, 7'b0100011));    // sd    mcause, fail slot
        emit_j(32'h0000_0250);

        seek(32'h0000_0260);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_0270);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_0280);
        li_small(5'd7, 12'sd2);
        emit_beq(5'd16, 5'd7, 32'h0000_02a0);                      // fid 2: hart_get_status
        emit_j(32'h0000_0240);

        seek(32'h0000_0290);
        li_small(5'd10, -12'sd2);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_02a0);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_02d0);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_02e0);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        emit_return_sbi();

        seek(32'h0000_02f0);
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd1);
        emit_return_sbi();

        seek(S_PAYLOAD);
        li_result_base(5'd1);
        emit(enc_s(12'sd0, 5'd10, 5'd1, 3'b011, 7'b0100011));      // sd    a0, 0(scratch)
        emit(enc_s(12'sd8, 5'd11, 5'd1, 3'b011, 7'b0100011));      // sd    a1, 8(scratch)
        li_small(5'd5, S_TRAP[11:0]);
        emit(enc_csr(12'h105, 5'd5, 3'b001, 5'd0));                // csrw  stvec, t0
        li_small(5'd5, 12'sd32);
        emit(enc_csr(12'h104, 5'd5, 3'b001, 5'd0));                // csrw  sie, t0
        li_small(5'd5, 12'sd2);
        emit(enc_csr(12'h100, 5'd5, 3'b001, 5'd0));                // csrw  sstatus, t0 (SIE)
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd0);
        emit(32'h0000_0073);                                        // ecall SBI base spec
        emit(enc_s(12'sd16, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd24, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd1);
        emit(32'h0000_0073);                                        // ecall SBI base impl id
        emit(enc_s(12'sd104, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd112, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd17, 12'sd16);
        li_small(5'd16, 12'sd4);
        emit(32'h0000_0073);                                        // ecall SBI base mvendorid
        emit(enc_s(12'sd128, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd136, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_const32(5'd10, 32'h5449_4d45);
        li_small(5'd16, 12'sd3);
        li_small(5'd17, 12'sd16);
        emit(32'h0000_0073);                                        // ecall SBI probe TIME
        emit(enc_s(12'sd144, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd152, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_const32(5'd10, 32'h0073_5049);
        li_small(5'd16, 12'sd3);
        li_small(5'd17, 12'sd16);
        emit(32'h0000_0073);                                        // ecall SBI probe IPI
        emit(enc_s(12'sd160, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd168, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_const32(5'd10, 32'h5246_4e43);
        li_small(5'd16, 12'sd3);
        li_small(5'd17, 12'sd16);
        emit(32'h0000_0073);                                        // ecall SBI probe RFENCE
        emit(enc_s(12'sd176, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd184, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_const32(5'd10, 32'h0048_534d);
        li_small(5'd16, 12'sd3);
        li_small(5'd17, 12'sd16);
        emit(32'h0000_0073);                                        // ecall SBI probe HSM
        emit(enc_s(12'sd192, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd200, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_const32(5'd10, 32'h4442_434e);
        li_small(5'd16, 12'sd3);
        li_small(5'd17, 12'sd16);
        emit(32'h0000_0073);                                        // ecall SBI probe DBCN
        emit(enc_s(12'sd208, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd216, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd10, 12'sd1);
        li_small(5'd16, 12'sd3);
        li_small(5'd17, 12'sd16);
        emit(32'h0000_0073);                                        // ecall SBI probe console
        emit(enc_s(12'sd32, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd40, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd10, 12'sd90);
        li_small(5'd17, 12'sd1);
        emit(32'h0000_0073);                                        // ecall legacy console_putchar
        emit(enc_s(12'sd48, 5'd10, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd10, 12'sd1);
        li_small(5'd11, 12'sd0);
        li_small(5'd17, 12'sd0);
        emit(32'h0000_0073);                                        // ecall legacy set_timer
        emit(enc_s(12'sd56, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd64, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        li_const32(5'd17, 32'h0073_5049);
        emit(32'h0000_0073);                                        // ecall SBI IPI no-op
        emit(enc_s(12'sd224, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd232, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd10, 12'sd0);
        li_small(5'd11, 12'sd0);
        li_const32(5'd17, 32'h5246_4e43);
        emit(32'h0000_0073);                                        // ecall SBI RFENCE no-op
        emit(enc_s(12'sd240, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd248, 5'd11, 5'd1, 3'b011, 7'b0100011));
        li_small(5'd10, 12'sd0);
        li_small(5'd16, 12'sd2);
        li_const32(5'd17, 32'h0048_534d);
        emit(32'h0000_0073);                                        // ecall SBI HSM hart_get_status
        emit(enc_s(12'sd256, 5'd10, 5'd1, 3'b011, 7'b0100011));
        emit(enc_s(12'sd264, 5'd11, 5'd1, 3'b011, 7'b0100011));
        emit(32'h1050_0073);                                        // wfi
        li_small(5'd5, 12'sd123);
        emit(enc_s(12'sd72, 5'd5, 5'd1, 3'b011, 7'b0100011));
        emit(32'h0010_0073);                                        // ebreak if timer did not arrive

        seek(S_TRAP);
        li_result_base(5'd1);
        emit(enc_csr(12'h142, 5'd0, 3'b010, 5'd5));                // csrr  t0, scause
        emit(enc_s(12'sd80, 5'd5, 5'd1, 3'b011, 7'b0100011));
        emit(enc_csr(12'h141, 5'd0, 3'b010, 5'd5));                // csrr  t0, sepc
        emit(enc_s(12'sd88, 5'd5, 5'd1, 3'b011, 7'b0100011));
        emit(enc_csr(12'h144, 5'd0, 3'b010, 5'd5));                // csrr  t0, sip
        emit(enc_s(12'sd96, 5'd5, 5'd1, 3'b011, 7'b0100011));
        emit(32'h0010_0073);                                        // ebreak

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (int cycle = 0; cycle < 8000 && !core_halted; cycle++) begin
            @(posedge clk);
        end

        if (!core_halted || core_illegal) begin
            $fatal(1, "ZX64 SBI handoff did not halt cleanly halted=%0d illegal=%0d pc=%016x instr=%08x state=%08x",
                   core_halted, core_illegal, dbg_pc, dbg_instr, dbg_core_state);
        end

        expect64(RESULT_BASE + 0, 64'd0, "SBI handoff hartid");
        expect64(RESULT_BASE + 8, DTB_ADDR, "SBI handoff dtb");
        expect64(RESULT_BASE + 16, 64'd0, "SBI base spec error");
        expect64(RESULT_BASE + 24, 64'd2, "SBI base spec value");
        expect64(RESULT_BASE + 32, 64'd0, "SBI probe error");
        expect64(RESULT_BASE + 40, 64'd1, "SBI probe console value");
        expect64(RESULT_BASE + 48, 64'd0, "SBI console return");
        expect64(RESULT_BASE + 56, 64'd0, "SBI timer return error");
        expect64(RESULT_BASE + 64, 64'd0, "SBI timer return value");
        expect64(RESULT_BASE + 72, 64'd0, "SBI WFI fallthrough marker");
        expect64(RESULT_BASE + 80, 64'h8000_0000_0000_0005, "SBI delegated S timer scause");
        expect_mask64(RESULT_BASE + 96, 64'h20, 64'h20, "SBI delegated S timer sip");
        expect64(RESULT_BASE + 104, 64'd0, "SBI base impl id error");
        expect64(RESULT_BASE + 112, 64'h0000_0000_0000_5a32, "SBI base impl id value");
        expect64(RESULT_BASE + 120, 64'd0, "SBI unexpected M trap marker");
        expect64(RESULT_BASE + 128, 64'd0, "SBI base mvendorid error");
        expect64(RESULT_BASE + 136, 64'd0, "SBI base mvendorid value");
        expect64(RESULT_BASE + 144, 64'd0, "SBI probe TIME error");
        expect64(RESULT_BASE + 152, 64'd1, "SBI probe TIME value");
        expect64(RESULT_BASE + 160, 64'd0, "SBI probe IPI error");
        expect64(RESULT_BASE + 168, 64'd1, "SBI probe IPI value");
        expect64(RESULT_BASE + 176, 64'd0, "SBI probe RFENCE error");
        expect64(RESULT_BASE + 184, 64'd1, "SBI probe RFENCE value");
        expect64(RESULT_BASE + 192, 64'd0, "SBI probe HSM error");
        expect64(RESULT_BASE + 200, 64'd1, "SBI probe HSM value");
        expect64(RESULT_BASE + 208, 64'd0, "SBI probe DBCN error");
        expect64(RESULT_BASE + 216, 64'd0, "SBI probe DBCN value");
        expect64(RESULT_BASE + 224, 64'd0, "SBI IPI no-op error");
        expect64(RESULT_BASE + 232, 64'd0, "SBI IPI no-op value");
        expect64(RESULT_BASE + 240, 64'd0, "SBI RFENCE no-op error");
        expect64(RESULT_BASE + 248, 64'd0, "SBI RFENCE no-op value");
        expect64(RESULT_BASE + 256, 64'd0, "SBI HSM status error");
        expect64(RESULT_BASE + 264, 64'd0, "SBI HSM status started value");

        $display("tb_zx64_soc_sbi: PASS ih=%0d im=%0d dh=%0d dm=%0d",
                 dbg_icache_hits, dbg_icache_misses,
                 dbg_dcache_hits, dbg_dcache_misses);
        $finish;
    end
endmodule
