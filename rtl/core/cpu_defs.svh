`ifndef ZYNQ_CPU_DEFS_SVH
`define ZYNQ_CPU_DEFS_SVH

localparam int XLEN = 32;

localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
localparam logic [6:0] OPCODE_JALR   = 7'b1100111;
localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
localparam logic [6:0] OPCODE_MISC_MEM = 7'b0001111;
localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
localparam logic [6:0] OPCODE_AMO    = 7'b0101111;
localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
localparam logic [6:0] OPCODE_OP     = 7'b0110011;
localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;
localparam logic [6:0] OPCODE_CUSTOM0 = 7'b0001011;

typedef enum logic [3:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_AND,
    ALU_OR,
    ALU_XOR,
    ALU_SLL,
    ALU_SRL,
    ALU_SRA,
    ALU_SLT,
    ALU_SLTU
} alu_op_t;

`endif
