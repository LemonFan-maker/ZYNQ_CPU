`ifndef ZYNQ_CPU64_DEFS_SVH
`define ZYNQ_CPU64_DEFS_SVH

localparam int ZX64_XLEN = 64;

localparam logic [6:0] OPCODE64_LUI       = 7'b0110111;
localparam logic [6:0] OPCODE64_AUIPC     = 7'b0010111;
localparam logic [6:0] OPCODE64_JAL       = 7'b1101111;
localparam logic [6:0] OPCODE64_JALR      = 7'b1100111;
localparam logic [6:0] OPCODE64_BRANCH    = 7'b1100011;
localparam logic [6:0] OPCODE64_LOAD      = 7'b0000011;
localparam logic [6:0] OPCODE64_LOAD_FP   = 7'b0000111;
localparam logic [6:0] OPCODE64_MISC_MEM  = 7'b0001111;
localparam logic [6:0] OPCODE64_STORE     = 7'b0100011;
localparam logic [6:0] OPCODE64_STORE_FP  = 7'b0100111;
localparam logic [6:0] OPCODE64_AMO       = 7'b0101111;
localparam logic [6:0] OPCODE64_OP_IMM    = 7'b0010011;
localparam logic [6:0] OPCODE64_OP_IMM_32 = 7'b0011011;
localparam logic [6:0] OPCODE64_OP        = 7'b0110011;
localparam logic [6:0] OPCODE64_OP_32     = 7'b0111011;
localparam logic [6:0] OPCODE64_MADD      = 7'b1000011;
localparam logic [6:0] OPCODE64_MSUB      = 7'b1000111;
localparam logic [6:0] OPCODE64_NMSUB     = 7'b1001011;
localparam logic [6:0] OPCODE64_NMADD     = 7'b1001111;
localparam logic [6:0] OPCODE64_OP_FP     = 7'b1010011;
localparam logic [6:0] OPCODE64_SYSTEM    = 7'b1110011;

`endif
