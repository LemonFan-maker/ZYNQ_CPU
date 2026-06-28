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
            encoded <= 10'b1101010100;
            disparity_q <= 6'sd0;
        end else if (!de) begin
            disparity_q <= 6'sd0;
            unique case (control)
                2'b00: encoded <= 10'b1101010100;
                2'b01: encoded <= 10'b0010101011;
                2'b10: encoded <= 10'b0101010100;
                default: encoded <= 10'b1010101011;
            endcase
        end else if (disparity_q == 6'sd0 || balance == 5'sd0) begin
            encoded <= {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
            disparity_q <= q_m[8] ? (disparity_q + $signed({balance[4], balance}))
                                   : (disparity_q - $signed({balance[4], balance}));
        end else if ((disparity_q > 6'sd0 && balance > 5'sd0) ||
                     (disparity_q < 6'sd0 && balance < 5'sd0)) begin
            encoded <= {1'b1, q_m[8], ~q_m[7:0]};
            disparity_q <= disparity_q + $signed({5'd0, q_m[8]}) -
                           $signed({balance[4], balance});
        end else begin
            encoded <= {1'b0, q_m[8], q_m[7:0]};
            disparity_q <= disparity_q - $signed({5'd0, ~q_m[8]}) +
                           $signed({balance[4], balance});
        end
    end
endmodule
