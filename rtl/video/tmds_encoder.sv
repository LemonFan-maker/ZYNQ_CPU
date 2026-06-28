module tmds_encoder (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data,
    input  logic [1:0] control,
    input  logic       de,
    output logic [9:0] encoded
);
    logic [3:0] ones_data;
    logic       use_xnor;
    logic [8:0] q_m;
    logic [3:0] ones_q_m;
    logic signed [4:0] balance;
    logic [8:0] q_m_q;
    logic signed [4:0] balance_q;
    logic [1:0] control_q;
    logic       de_q;
    logic signed [5:0] disparity_q;

    assign ones_data = {3'd0, data[0]} + {3'd0, data[1]} +
                       {3'd0, data[2]} + {3'd0, data[3]} +
                       {3'd0, data[4]} + {3'd0, data[5]} +
                       {3'd0, data[6]} + {3'd0, data[7]};
    assign use_xnor = ones_data > 4'd4 || (ones_data == 4'd4 && data[0] == 1'b0);
    assign q_m[0] = data[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ data[1]) : (q_m[0] ^ data[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ data[2]) : (q_m[1] ^ data[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ data[3]) : (q_m[2] ^ data[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ data[4]) : (q_m[3] ^ data[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ data[5]) : (q_m[4] ^ data[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ data[6]) : (q_m[5] ^ data[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ data[7]) : (q_m[6] ^ data[7]);
    assign q_m[8] = !use_xnor;

    assign ones_q_m = {3'd0, q_m[0]} + {3'd0, q_m[1]} +
                      {3'd0, q_m[2]} + {3'd0, q_m[3]} +
                      {3'd0, q_m[4]} + {3'd0, q_m[5]} +
                      {3'd0, q_m[6]} + {3'd0, q_m[7]};
    assign balance = $signed({1'b0, ones_q_m}) - $signed(5'd4);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_m_q <= 9'd0;
            balance_q <= 5'sd0;
            control_q <= 2'b00;
            de_q <= 1'b0;
            encoded <= 10'b1101010100;
            disparity_q <= 6'sd0;
        end else begin
            q_m_q <= q_m;
            balance_q <= balance;
            control_q <= control;
            de_q <= de;
            if (!de_q) begin
            disparity_q <= 6'sd0;
            unique case (control_q)
                2'b00: encoded <= 10'b1101010100;
                2'b01: encoded <= 10'b0010101011;
                2'b10: encoded <= 10'b0101010100;
                default: encoded <= 10'b1010101011;
            endcase
            end else if (disparity_q == 6'sd0 || balance_q == 5'sd0) begin
                encoded <= {~q_m_q[8], q_m_q[8], q_m_q[8] ? q_m_q[7:0] : ~q_m_q[7:0]};
                disparity_q <= q_m_q[8] ? (disparity_q + $signed({balance_q[4], balance_q}))
                                         : (disparity_q - $signed({balance_q[4], balance_q}));
            end else if ((disparity_q > 6'sd0 && balance_q > 5'sd0) ||
                         (disparity_q < 6'sd0 && balance_q < 5'sd0)) begin
                encoded <= {1'b1, q_m_q[8], ~q_m_q[7:0]};
                disparity_q <= disparity_q + $signed({5'd0, q_m_q[8]}) -
                               $signed({balance_q[4], balance_q});
            end else begin
                encoded <= {1'b0, q_m_q[8], q_m_q[7:0]};
                disparity_q <= disparity_q - $signed({5'd0, ~q_m_q[8]}) +
                               $signed({balance_q[4], balance_q});
            end
        end
    end
endmodule
