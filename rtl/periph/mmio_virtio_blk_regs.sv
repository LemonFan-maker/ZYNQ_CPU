module mmio_virtio_blk_regs #(
    parameter logic [63:0] DEFAULT_CAPACITY_SECTORS = 64'd0,
    parameter int          QUEUE_NUM_MAX = 128
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

    input  logic [63:0] capacity_sectors,
    input  logic        backend_vring_irq,
    input  logic        backend_notify_ack,
    output logic        notify_pulse,
    output logic [15:0] notify_queue,
    output logic        notify_pending,
    output logic        irq_pending,
    output logic [31:0] notify_count,
    output logic [31:0] queue_num,
    output logic        queue_ready,
    output logic [63:0] queue_desc_addr,
    output logic [63:0] queue_avail_addr,
    output logic [63:0] queue_used_addr,
    output logic [7:0]  device_status
);
    localparam logic [31:0] VIRTIO_MAGIC      = 32'h7472_6976;
    localparam logic [31:0] VIRTIO_VERSION    = 32'd2;
    localparam logic [31:0] VIRTIO_DEVICE_BLK = 32'd2;
    localparam logic [31:0] VIRTIO_VENDOR     = 32'h5a32_3032;
    localparam logic [63:0] VIRTIO_FEATURES   = 64'h0000_0001_0000_0000; // VIRTIO_F_VERSION_1
    localparam logic [31:0] INT_VRING         = 32'h0000_0001;

    logic [31:0] device_features_sel_q;
    logic [31:0] driver_features_sel_q;
    logic [63:0] driver_features_q;
    logic [31:0] queue_sel_q;
    logic [31:0] queue_num_q;
    logic        queue_ready_q;
    logic [63:0] queue_desc_q;
    logic [63:0] queue_avail_q;
    logic [63:0] queue_used_q;
    logic [31:0] interrupt_status_q;
    logic [7:0]  status_q;
    logic [31:0] notify_count_q;
    logic [63:0] active_capacity;
    logic [31:0] merged_queue_num;
    logic [31:0] merged_queue_ready;
    logic [31:0] merged_notify_queue;
    logic [31:0] merged_status;

    assign ready = valid;
    assign irq_pending = interrupt_status_q != 32'd0;
    assign notify_count = notify_count_q;
    assign queue_num = queue_num_q;
    assign queue_ready = queue_ready_q;
    assign queue_desc_addr = queue_desc_q;
    assign queue_avail_addr = queue_avail_q;
    assign queue_used_addr = queue_used_q;
    assign device_status = status_q;
    assign active_capacity = (capacity_sectors != 64'd0) ? capacity_sectors : DEFAULT_CAPACITY_SECTORS;
    assign merged_queue_num = merge32(queue_num_q, wdata, wstrb);
    assign merged_queue_ready = merge32({31'd0, queue_ready_q}, wdata, wstrb);
    assign merged_notify_queue = merge32({16'd0, notify_queue}, wdata, wstrb);
    assign merged_status = merge32({24'd0, status_q}, wdata, wstrb);

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
        rdata = 32'd0;
        if (addr >= 32'h0000_0100) begin
            unique case (addr[7:0])
                8'h00: rdata = active_capacity[31:0];
                8'h04: rdata = active_capacity[63:32];
                default: rdata = 32'd0;
            endcase
        end else begin
            unique case (addr[7:0])
                8'h00: rdata = VIRTIO_MAGIC;
                8'h04: rdata = VIRTIO_VERSION;
                8'h08: rdata = VIRTIO_DEVICE_BLK;
                8'h0c: rdata = VIRTIO_VENDOR;
                8'h10: rdata = (device_features_sel_q == 32'd0) ? VIRTIO_FEATURES[31:0] :
                                (device_features_sel_q == 32'd1) ? VIRTIO_FEATURES[63:32] : 32'd0;
                8'h34: rdata = QUEUE_NUM_MAX[31:0];
                8'h38: rdata = queue_num_q;
                8'h44: rdata = {31'd0, queue_ready_q};
                8'h60: rdata = interrupt_status_q;
                8'h70: rdata = {24'd0, status_q};
                8'h80: rdata = queue_desc_q[31:0];
                8'h84: rdata = queue_desc_q[63:32];
                8'h90: rdata = queue_avail_q[31:0];
                8'h94: rdata = queue_avail_q[63:32];
                8'ha0: rdata = queue_used_q[31:0];
                8'ha4: rdata = queue_used_q[63:32];
                8'hb0,
                8'hb4,
                8'hb8,
                8'hbc: rdata = 32'hffff_ffff;
                8'hfc: rdata = notify_count_q;
                default: rdata = 32'd0;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            device_features_sel_q <= 32'd0;
            driver_features_sel_q <= 32'd0;
            driver_features_q <= 64'd0;
            queue_sel_q <= 32'd0;
            queue_num_q <= 32'd0;
            queue_ready_q <= 1'b0;
            queue_desc_q <= 64'd0;
            queue_avail_q <= 64'd0;
            queue_used_q <= 64'd0;
            interrupt_status_q <= 32'd0;
            status_q <= 8'd0;
            notify_count_q <= 32'd0;
            notify_pulse <= 1'b0;
            notify_queue <= 16'd0;
            notify_pending <= 1'b0;
        end else begin
            notify_pulse <= 1'b0;

            if (backend_vring_irq) begin
                interrupt_status_q <= interrupt_status_q | INT_VRING;
            end
            if (backend_notify_ack) begin
                notify_pending <= 1'b0;
            end

            if (valid && ready && we) begin
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
                        queue_num_q <= (merged_queue_num > QUEUE_NUM_MAX[31:0]) ?
                                       QUEUE_NUM_MAX[31:0] : merged_queue_num;
                    end
                    8'h44: queue_ready_q <= merged_queue_ready[0];
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
                            queue_num_q <= 32'd0;
                            queue_ready_q <= 1'b0;
                            queue_desc_q <= 64'd0;
                            queue_avail_q <= 64'd0;
                            queue_used_q <= 64'd0;
                            interrupt_status_q <= 32'd0;
                            notify_count_q <= 32'd0;
                            notify_pending <= 1'b0;
                        end
                        status_q <= merged_status[7:0];
                    end
                    8'h80: queue_desc_q[31:0] <= merge32(queue_desc_q[31:0], wdata, wstrb);
                    8'h84: queue_desc_q[63:32] <= merge32(queue_desc_q[63:32], wdata, wstrb);
                    8'h90: queue_avail_q[31:0] <= merge32(queue_avail_q[31:0], wdata, wstrb);
                    8'h94: queue_avail_q[63:32] <= merge32(queue_avail_q[63:32], wdata, wstrb);
                    8'ha0: queue_used_q[31:0] <= merge32(queue_used_q[31:0], wdata, wstrb);
                    8'ha4: queue_used_q[63:32] <= merge32(queue_used_q[63:32], wdata, wstrb);
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
