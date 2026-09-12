`include "cpu_defs.svh"

module alu64 (
    input  alu_op_t     op,
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic [63:0] y
);
    always_comb begin
        case (op)
            ALU_ADD:  y = a + b;
            ALU_SUB:  y = a - b;
            ALU_AND:  y = a & b;
            ALU_OR:   y = a | b;
            ALU_XOR:  y = a ^ b;
            ALU_SLL:  y = a << b[5:0];
            ALU_SRL:  y = a >> b[5:0];
            ALU_SRA:  y = $signed(a) >>> b[5:0];
            ALU_SLT:  y = ($signed(a) < $signed(b)) ? 64'd1 : 64'd0;
            ALU_SLTU: y = (a < b) ? 64'd1 : 64'd0;
            default:  y = 64'd0;
        endcase
    end
endmodule
