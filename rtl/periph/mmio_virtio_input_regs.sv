module mmio_virtio_input_regs #(
    parameter int QUEUE_NUM_MAX = 64
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

    input  logic        backend_vring_irq,
    input  logic        backend_notify_ack,
    output logic        notify_pulse,
    output logic [15:0] notify_queue,
    output logic        notify_pending,
    output logic        irq_pending,
    output logic [31:0] notify_count,
    output logic [7:0]  device_status,
    output logic [31:0] event_queue_num,
    output logic        event_queue_ready,
    output logic [63:0] event_queue_desc_addr,
    output logic [63:0] event_queue_avail_addr,
    output logic [63:0] event_queue_used_addr,
    output logic [31:0] status_queue_num,
    output logic        status_queue_ready,
    output logic [63:0] status_queue_desc_addr,
    output logic [63:0] status_queue_avail_addr,
    output logic [63:0] status_queue_used_addr
);
    localparam logic [31:0] VIRTIO_MAGIC       = 32'h7472_6976;
    localparam logic [31:0] VIRTIO_VERSION     = 32'd2;
    localparam logic [31:0] VIRTIO_DEVICE_INPUT = 32'd18;
    localparam logic [31:0] VIRTIO_VENDOR      = 32'h5a32_3032;
    localparam logic [63:0] VIRTIO_FEATURES    = 64'h0000_0001_0000_0000; // VIRTIO_F_VERSION_1
    localparam logic [31:0] INT_VRING          = 32'h0000_0001;

    localparam logic [7:0] CFG_ID_NAME    = 8'h01;
    localparam logic [7:0] CFG_ID_SERIAL  = 8'h02;
    localparam logic [7:0] CFG_ID_DEVIDS  = 8'h03;
    localparam logic [7:0] CFG_EV_BITS    = 8'h11;

    localparam logic [7:0] EV_KEY = 8'd1;
    localparam logic [7:0] EV_REP = 8'd20;

    logic [31:0] device_features_sel_q;
    logic [31:0] driver_features_sel_q;
    logic [63:0] driver_features_q;
    logic [31:0] queue_sel_q;
    logic [31:0] queue_num_q [0:1];
    logic        queue_ready_q [0:1];
    logic [63:0] queue_desc_q [0:1];
    logic [63:0] queue_avail_q [0:1];
    logic [63:0] queue_used_q [0:1];
    logic [31:0] interrupt_status_q;
    logic [7:0]  status_q;
    logic [31:0] notify_count_q;
    logic [7:0]  cfg_select_q;
    logic [7:0]  cfg_subsel_q;
    logic [31:0] merged_queue_num;
    logic [31:0] merged_queue_ready;
    logic [31:0] merged_notify_queue;
    logic [31:0] merged_status;
    logic        queue_valid;
    logic        queue_index;
    logic [63:0] active_desc;
    logic [63:0] active_avail;
    logic [63:0] active_used;

    assign ready = valid;
    assign irq_pending = interrupt_status_q != 32'd0;
    assign notify_count = notify_count_q;
    assign device_status = status_q;
    assign event_queue_num = queue_num_q[0];
    assign event_queue_ready = queue_ready_q[0];
    assign event_queue_desc_addr = queue_desc_q[0];
    assign event_queue_avail_addr = queue_avail_q[0];
    assign event_queue_used_addr = queue_used_q[0];
    assign status_queue_num = queue_num_q[1];
    assign status_queue_ready = queue_ready_q[1];
    assign status_queue_desc_addr = queue_desc_q[1];
    assign status_queue_avail_addr = queue_avail_q[1];
    assign status_queue_used_addr = queue_used_q[1];
    assign queue_valid = queue_sel_q < 32'd2;
    assign queue_index = queue_sel_q[0];
    assign merged_queue_num = merge32(active_queue_num(), wdata, wstrb);
    assign merged_queue_ready = merge32({31'd0, active_queue_ready()}, wdata, wstrb);
    assign merged_notify_queue = merge32({16'd0, notify_queue}, wdata, wstrb);
    assign merged_status = merge32({24'd0, status_q}, wdata, wstrb);
    assign active_desc = active_queue_desc();
    assign active_avail = active_queue_avail();
    assign active_used = active_queue_used();

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

    function automatic logic [31:0] active_queue_num();
        active_queue_num = queue_valid ? queue_num_q[queue_index] : 32'd0;
    endfunction

    function automatic logic active_queue_ready();
        active_queue_ready = queue_valid ? queue_ready_q[queue_index] : 1'b0;
    endfunction

    function automatic logic [63:0] active_queue_desc();
        active_queue_desc = queue_valid ? queue_desc_q[queue_index] : 64'd0;
    endfunction

    function automatic logic [63:0] active_queue_avail();
        active_queue_avail = queue_valid ? queue_avail_q[queue_index] : 64'd0;
    endfunction

    function automatic logic [63:0] active_queue_used();
        active_queue_used = queue_valid ? queue_used_q[queue_index] : 64'd0;
    endfunction

    function automatic logic [7:0] cfg_size();
        begin
            unique case (cfg_select_q)
                CFG_ID_NAME:   cfg_size = 8'd20; // "ZX64 virtio keyboard"
                CFG_ID_SERIAL: cfg_size = 8'd11; // "zx64-input0"
                CFG_ID_DEVIDS: cfg_size = 8'd8;
                CFG_EV_BITS: begin
                    unique case (cfg_subsel_q)
                        EV_KEY: cfg_size = 8'd7;
                        EV_REP: cfg_size = 8'd1;
                        default: cfg_size = 8'd0;
                    endcase
                end
                default: cfg_size = 8'd0;
            endcase
        end
    endfunction

    function automatic logic [7:0] cfg_payload_byte(input logic [7:0] index);
        begin
            cfg_payload_byte = 8'd0;
            unique case (cfg_select_q)
                CFG_ID_NAME: begin
                    unique case (index)
                        8'd0: cfg_payload_byte = "Z";
                        8'd1: cfg_payload_byte = "X";
                        8'd2: cfg_payload_byte = "6";
                        8'd3: cfg_payload_byte = "4";
                        8'd4: cfg_payload_byte = " ";
                        8'd5: cfg_payload_byte = "v";
                        8'd6: cfg_payload_byte = "i";
                        8'd7: cfg_payload_byte = "r";
                        8'd8: cfg_payload_byte = "t";
                        8'd9: cfg_payload_byte = "i";
                        8'd10: cfg_payload_byte = "o";
                        8'd11: cfg_payload_byte = " ";
                        8'd12: cfg_payload_byte = "k";
                        8'd13: cfg_payload_byte = "e";
                        8'd14: cfg_payload_byte = "y";
                        8'd15: cfg_payload_byte = "b";
                        8'd16: cfg_payload_byte = "o";
                        8'd17: cfg_payload_byte = "a";
                        8'd18: cfg_payload_byte = "r";
                        8'd19: cfg_payload_byte = "d";
                        default: cfg_payload_byte = 8'd0;
                    endcase
                end
                CFG_ID_SERIAL: begin
                    unique case (index)
                        8'd0: cfg_payload_byte = "z";
                        8'd1: cfg_payload_byte = "x";
                        8'd2: cfg_payload_byte = "6";
                        8'd3: cfg_payload_byte = "4";
                        8'd4: cfg_payload_byte = "-";
                        8'd5: cfg_payload_byte = "i";
                        8'd6: cfg_payload_byte = "n";
                        8'd7: cfg_payload_byte = "p";
                        8'd8: cfg_payload_byte = "u";
                        8'd9: cfg_payload_byte = "t";
                        8'd10: cfg_payload_byte = "0";
                        default: cfg_payload_byte = 8'd0;
                    endcase
                end
                CFG_ID_DEVIDS: begin
                    unique case (index)
                        8'd0: cfg_payload_byte = 8'h06; // BUS_VIRTUAL
                        8'd1: cfg_payload_byte = 8'h00;
                        8'd2: cfg_payload_byte = 8'h32;
                        8'd3: cfg_payload_byte = 8'h5a;
                        8'd4: cfg_payload_byte = 8'h01;
                        8'd5: cfg_payload_byte = 8'h00;
                        8'd6: cfg_payload_byte = 8'h01;
                        8'd7: cfg_payload_byte = 8'h00;
                        default: cfg_payload_byte = 8'd0;
                    endcase
                end
                CFG_EV_BITS: begin
                    if (cfg_subsel_q == EV_KEY) begin
                        unique case (index)
                            8'd3: cfg_payload_byte = 8'h50; // KEY_ENTER(28), KEY_A(30)
                            8'd6: cfg_payload_byte = 8'h01; // KEY_B(48)
                            default: cfg_payload_byte = 8'd0;
                        endcase
                    end
                end
                default: cfg_payload_byte = 8'd0;
            endcase
        end
    endfunction

    function automatic logic [7:0] cfg_byte(input logic [7:0] byte_addr);
        begin
            unique case (byte_addr)
                8'h00: cfg_byte = cfg_select_q;
                8'h01: cfg_byte = cfg_subsel_q;
                8'h02: cfg_byte = cfg_size();
                default: begin
                    if (byte_addr >= 8'h08) begin
                        cfg_byte = cfg_payload_byte(byte_addr - 8'h08);
                    end else begin
                        cfg_byte = 8'd0;
                    end
                end
            endcase
        end
    endfunction

    function automatic logic [31:0] cfg_word(input logic [7:0] byte_addr);
        cfg_word = {cfg_byte(byte_addr + 8'd3),
                    cfg_byte(byte_addr + 8'd2),
                    cfg_byte(byte_addr + 8'd1),
                    cfg_byte(byte_addr)};
    endfunction

    always_comb begin
        rdata = 32'd0;
        if (addr >= 32'h0000_0100) begin
            rdata = cfg_word(addr[7:0]);
        end else begin
            unique case (addr[7:0])
                8'h00: rdata = VIRTIO_MAGIC;
                8'h04: rdata = VIRTIO_VERSION;
                8'h08: rdata = VIRTIO_DEVICE_INPUT;
                8'h0c: rdata = VIRTIO_VENDOR;
                8'h10: rdata = (device_features_sel_q == 32'd0) ? VIRTIO_FEATURES[31:0] :
                                (device_features_sel_q == 32'd1) ? VIRTIO_FEATURES[63:32] : 32'd0;
                8'h34: rdata = queue_valid ? QUEUE_NUM_MAX[31:0] : 32'd0;
                8'h38: rdata = active_queue_num();
                8'h44: rdata = {31'd0, active_queue_ready()};
                8'h60: rdata = interrupt_status_q;
                8'h70: rdata = {24'd0, status_q};
                8'h80: rdata = active_desc[31:0];
                8'h84: rdata = active_desc[63:32];
                8'h90: rdata = active_avail[31:0];
                8'h94: rdata = active_avail[63:32];
                8'ha0: rdata = active_used[31:0];
                8'ha4: rdata = active_used[63:32];
                8'hb0,
                8'hb4,
                8'hb8,
                8'hbc: rdata = 32'hffff_ffff;
                8'hfc: rdata = notify_count_q;
                default: rdata = 32'd0;
            endcase
        end
    end

    task automatic write_cfg_byte(input logic [7:0] byte_addr, input logic [7:0] byte_data);
        begin
            unique case (byte_addr)
                8'h00: cfg_select_q <= byte_data;
                8'h01: cfg_subsel_q <= byte_data;
                default: begin
                end
            endcase
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            device_features_sel_q <= 32'd0;
            driver_features_sel_q <= 32'd0;
            driver_features_q <= 64'd0;
            queue_sel_q <= 32'd0;
            queue_num_q[0] <= 32'd0;
            queue_num_q[1] <= 32'd0;
            queue_ready_q[0] <= 1'b0;
            queue_ready_q[1] <= 1'b0;
            queue_desc_q[0] <= 64'd0;
            queue_desc_q[1] <= 64'd0;
            queue_avail_q[0] <= 64'd0;
            queue_avail_q[1] <= 64'd0;
            queue_used_q[0] <= 64'd0;
            queue_used_q[1] <= 64'd0;
            interrupt_status_q <= 32'd0;
            status_q <= 8'd0;
            notify_count_q <= 32'd0;
            notify_pulse <= 1'b0;
            notify_queue <= 16'd0;
            notify_pending <= 1'b0;
            cfg_select_q <= 8'd0;
            cfg_subsel_q <= 8'd0;
        end else begin
            notify_pulse <= 1'b0;

            if (backend_vring_irq) begin
                interrupt_status_q <= interrupt_status_q | INT_VRING;
            end
            if (backend_notify_ack) begin
                notify_pending <= 1'b0;
            end

            if (valid && ready && we) begin
                if (addr >= 32'h0000_0100) begin
                    for (int i = 0; i < 4; i++) begin
                        if (wstrb[i]) begin
                            write_cfg_byte(addr[7:0] + i[7:0], wdata[i * 8 +: 8]);
                        end
                    end
                end else begin
                    unique case (addr[7:0])
                        8'h14: device_features_sel_q <= merge32(device_features_sel_q, wdata, wstrb);
                        8'h20: begin
                            if (driver_features_sel_q == 32'd0) begin
                                driver_features_q[31:0] <= merge32(driver_features_q[31:0], wdata, wstrb);
                            end else if (driver_features_sel_q == 32'd1) begin
                                driver_features_q[63:32] <= merge32(driver_features_q[63:32], wdata, wstrb);
                            end
                        end
                        8'h24: driver_features_sel_q <= merge32(driver_features_sel_q, wdata, wstrb);
                        8'h30: queue_sel_q <= merge32(queue_sel_q, wdata, wstrb);
                        8'h38: begin
                            if (queue_valid) begin
                                queue_num_q[queue_index] <= (merged_queue_num > QUEUE_NUM_MAX[31:0]) ?
                                                            QUEUE_NUM_MAX[31:0] : merged_queue_num;
                            end
                        end
                        8'h44: begin
                            if (queue_valid) begin
                                queue_ready_q[queue_index] <= merged_queue_ready[0];
                            end
                        end
                        8'h50: begin
                            notify_pulse <= 1'b1;
                            notify_queue <= merged_notify_queue[15:0];
                            notify_pending <= 1'b1;
                            notify_count_q <= notify_count_q + 32'd1;
                        end
                        8'h64: interrupt_status_q <= interrupt_status_q & ~merge32(32'd0, wdata, wstrb);
                        8'h70: begin
                            if (merged_status[7:0] == 8'd0) begin
                                device_features_sel_q <= 32'd0;
                                driver_features_sel_q <= 32'd0;
                                driver_features_q <= 64'd0;
                                queue_sel_q <= 32'd0;
                                queue_num_q[0] <= 32'd0;
                                queue_num_q[1] <= 32'd0;
                                queue_ready_q[0] <= 1'b0;
                                queue_ready_q[1] <= 1'b0;
                                queue_desc_q[0] <= 64'd0;
                                queue_desc_q[1] <= 64'd0;
                                queue_avail_q[0] <= 64'd0;
                                queue_avail_q[1] <= 64'd0;
                                queue_used_q[0] <= 64'd0;
                                queue_used_q[1] <= 64'd0;
                                interrupt_status_q <= 32'd0;
                                notify_count_q <= 32'd0;
                                notify_pending <= 1'b0;
                                cfg_select_q <= 8'd0;
                                cfg_subsel_q <= 8'd0;
                            end
                            status_q <= merged_status[7:0];
                        end
                        8'h80: if (queue_valid) queue_desc_q[queue_index][31:0] <= merge32(queue_desc_q[queue_index][31:0], wdata, wstrb);
                        8'h84: if (queue_valid) queue_desc_q[queue_index][63:32] <= merge32(queue_desc_q[queue_index][63:32], wdata, wstrb);
                        8'h90: if (queue_valid) queue_avail_q[queue_index][31:0] <= merge32(queue_avail_q[queue_index][31:0], wdata, wstrb);
                        8'h94: if (queue_valid) queue_avail_q[queue_index][63:32] <= merge32(queue_avail_q[queue_index][63:32], wdata, wstrb);
                        8'ha0: if (queue_valid) queue_used_q[queue_index][31:0] <= merge32(queue_used_q[queue_index][31:0], wdata, wstrb);
                        8'ha4: if (queue_valid) queue_used_q[queue_index][63:32] <= merge32(queue_used_q[queue_index][63:32], wdata, wstrb);
                        default: begin
                        end
                    endcase
                end
            end
        end
    end
endmodule
