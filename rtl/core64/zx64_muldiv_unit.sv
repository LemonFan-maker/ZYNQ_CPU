module zx64_muldiv_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        word_op,
    input  logic [2:0]  funct3,
    input  logic [63:0] rs1,
    input  logic [63:0] rs2,

    output logic        busy,
    output logic        done,
    output logic [63:0] result
);
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_MUL,
        ST_DIV
    } state_t;

    state_t state_q;

    logic [127:0] mul_acc_q;
    logic [127:0] mul_multiplicand_q;
    logic [63:0]  mul_multiplier_q;
    logic [6:0]   mul_count_q;
    logic         mul_neg_q;
    logic         mul_word_q;
    logic [2:0]   mul_funct3_q;

    logic [63:0] div_dividend_q;
    logic [63:0] div_divisor_q;
    logic [64:0] div_remainder_q;
    logic [63:0] div_quotient_q;
    logic [6:0]  div_count_q;
    logic        div_neg_quot_q;
    logic        div_neg_rem_q;
    logic        div_word_q;
    logic        div_rem_op_q;

    logic [63:0] result_q;
    logic        done_q;

    assign busy = (state_q != ST_IDLE);
    assign done = done_q;
    assign result = result_q;

    function automatic logic [63:0] sext32(input logic [31:0] v);
        sext32 = {{32{v[31]}}, v};
    endfunction

    function automatic logic operand_sign(input logic word_mode,
                                          input logic [63:0] v);
        operand_sign = word_mode ? v[31] : v[63];
    endfunction

    function automatic logic [63:0] operand_abs(input logic word_mode,
                                                input logic signed_mode,
                                                input logic [63:0] v);
        logic [31:0] w;
        begin
            if (word_mode) begin
                w = v[31:0];
                if (signed_mode && w[31]) begin
                    w = ~w + 32'd1;
                end
                operand_abs = {32'd0, w};
            end else if (signed_mode && v[63]) begin
                operand_abs = ~v + 64'd1;
            end else begin
                operand_abs = v;
            end
        end
    endfunction

    function automatic logic div_overflow(input logic word_mode,
                                          input logic signed_mode,
                                          input logic [63:0] dividend,
                                          input logic [63:0] divisor);
        begin
            if (!signed_mode) begin
                div_overflow = 1'b0;
            end else if (word_mode) begin
                div_overflow = (dividend[31:0] == 32'h8000_0000) &&
                               (divisor[31:0] == 32'hffff_ffff);
            end else begin
                div_overflow = (dividend == 64'h8000_0000_0000_0000) &&
                               (divisor == 64'hffff_ffff_ffff_ffff);
            end
        end
    endfunction

    function automatic logic [63:0] div_zero_result(input logic word_mode,
                                                    input logic rem_op,
                                                    input logic [63:0] dividend);
        begin
            if (rem_op) begin
                div_zero_result = word_mode ? sext32(dividend[31:0]) : dividend;
            end else begin
                div_zero_result = word_mode ? 64'hffff_ffff_ffff_ffff :
                                             64'hffff_ffff_ffff_ffff;
            end
        end
    endfunction

    function automatic logic [63:0] div_overflow_result(input logic word_mode,
                                                        input logic rem_op,
                                                        input logic [63:0] dividend);
        begin
            if (rem_op) begin
                div_overflow_result = 64'd0;
            end else begin
                div_overflow_result = word_mode ? sext32(dividend[31:0]) : dividend;
            end
        end
    endfunction

    function automatic logic [63:0] mul_final_result(input logic word_mode,
                                                     input logic [2:0] f3,
                                                     input logic [127:0] product);
        begin
            if (word_mode) begin
                mul_final_result = sext32(product[31:0]);
            end else if (f3 == 3'b001 || f3 == 3'b010 || f3 == 3'b011) begin
                mul_final_result = product[127:64];
            end else begin
                mul_final_result = product[63:0];
            end
        end
    endfunction

    function automatic logic [63:0] div_final_result(input logic word_mode,
                                                     input logic rem_op,
                                                     input logic neg_quot,
                                                     input logic neg_rem,
                                                     input logic [63:0] quotient,
                                                     input logic [63:0] remainder);
        logic [63:0] signed_value;
        begin
            if (rem_op) begin
                signed_value = neg_rem ? (~remainder + 64'd1) : remainder;
            end else begin
                signed_value = neg_quot ? (~quotient + 64'd1) : quotient;
            end
            div_final_result = word_mode ? sext32(signed_value[31:0]) : signed_value;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        logic         signed_a;
        logic         signed_b;
        logic         div_signed;
        logic         div_rem_op;
        logic [63:0]  dividend_abs;
        logic [63:0]  divisor_abs;
        logic [127:0] mul_acc_next;
        logic [127:0] mul_product_next;
        logic [6:0]   div_bit_idx;
        logic [64:0]  div_remainder_next;
        logic [63:0]  div_quotient_next;

        if (!rst_n) begin
            state_q <= ST_IDLE;
            mul_acc_q <= 128'd0;
            mul_multiplicand_q <= 128'd0;
            mul_multiplier_q <= 64'd0;
            mul_count_q <= 7'd0;
            mul_neg_q <= 1'b0;
            mul_word_q <= 1'b0;
            mul_funct3_q <= 3'd0;
            div_dividend_q <= 64'd0;
            div_divisor_q <= 64'd0;
            div_remainder_q <= 65'd0;
            div_quotient_q <= 64'd0;
            div_count_q <= 7'd0;
            div_neg_quot_q <= 1'b0;
            div_neg_rem_q <= 1'b0;
            div_word_q <= 1'b0;
            div_rem_op_q <= 1'b0;
            result_q <= 64'd0;
            done_q <= 1'b0;
        end else begin
            done_q <= 1'b0;

            unique case (state_q)
                ST_IDLE: begin
                    if (start) begin
                        if (funct3[2] == 1'b0) begin
                            signed_a = !word_op && (funct3 == 3'b001 || funct3 == 3'b010);
                            signed_b = !word_op && (funct3 == 3'b001);
                            dividend_abs = operand_abs(word_op, signed_a, rs1);
                            divisor_abs = operand_abs(word_op, signed_b, rs2);
                            mul_acc_q <= 128'd0;
                            mul_multiplicand_q <= {64'd0, dividend_abs};
                            mul_multiplier_q <= divisor_abs;
                            mul_count_q <= word_op ? 7'd32 : 7'd64;
                            mul_neg_q <= (signed_a && operand_sign(word_op, rs1)) ^
                                         (signed_b && operand_sign(word_op, rs2));
                            mul_word_q <= word_op;
                            mul_funct3_q <= funct3;
                            state_q <= ST_MUL;
                        end else begin
                            div_signed = (funct3 == 3'b100) || (funct3 == 3'b110);
                            div_rem_op = funct3[1];
                            dividend_abs = operand_abs(word_op, div_signed, rs1);
                            divisor_abs = operand_abs(word_op, div_signed, rs2);

                            if (divisor_abs == 64'd0) begin
                                result_q <= div_zero_result(word_op, div_rem_op, rs1);
                                done_q <= 1'b1;
                            end else if (div_overflow(word_op, div_signed, rs1, rs2)) begin
                                result_q <= div_overflow_result(word_op, div_rem_op, rs1);
                                done_q <= 1'b1;
                            end else begin
                                div_dividend_q <= dividend_abs;
                                div_divisor_q <= divisor_abs;
                                div_remainder_q <= 65'd0;
                                div_quotient_q <= 64'd0;
                                div_count_q <= word_op ? 7'd32 : 7'd64;
                                div_neg_quot_q <= div_signed &&
                                                  (operand_sign(word_op, rs1) ^
                                                   operand_sign(word_op, rs2));
                                div_neg_rem_q <= div_signed && operand_sign(word_op, rs1);
                                div_word_q <= word_op;
                                div_rem_op_q <= div_rem_op;
                                state_q <= ST_DIV;
                            end
                        end
                    end
                end

                ST_MUL: begin
                    mul_acc_next = mul_acc_q;
                    if (mul_multiplier_q[0]) begin
                        mul_acc_next = mul_acc_q + mul_multiplicand_q;
                    end

                    if (mul_count_q == 7'd1) begin
                        mul_product_next = mul_neg_q ? (~mul_acc_next + 128'd1) : mul_acc_next;
                        result_q <= mul_final_result(mul_word_q, mul_funct3_q, mul_product_next);
                        done_q <= 1'b1;
                        state_q <= ST_IDLE;
                    end else begin
                        mul_acc_q <= mul_acc_next;
                        mul_multiplicand_q <= mul_multiplicand_q << 1;
                        mul_multiplier_q <= mul_multiplier_q >> 1;
                        mul_count_q <= mul_count_q - 7'd1;
                    end
                end

                ST_DIV: begin
                    div_bit_idx = div_count_q - 7'd1;
                    div_remainder_next = {div_remainder_q[63:0],
                                          div_dividend_q[div_bit_idx[5:0]]};
                    div_quotient_next = div_quotient_q;
                    if (div_remainder_next >= {1'b0, div_divisor_q}) begin
                        div_remainder_next = div_remainder_next - {1'b0, div_divisor_q};
                        div_quotient_next[div_bit_idx[5:0]] = 1'b1;
                    end

                    if (div_count_q == 7'd1) begin
                        result_q <= div_final_result(div_word_q, div_rem_op_q,
                                                     div_neg_quot_q, div_neg_rem_q,
                                                     div_quotient_next,
                                                     div_remainder_next[63:0]);
                        done_q <= 1'b1;
                        state_q <= ST_IDLE;
                    end else begin
                        div_remainder_q <= div_remainder_next;
                        div_quotient_q <= div_quotient_next;
                        div_count_q <= div_count_q - 7'd1;
                    end
                end

                default: begin
                    state_q <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
