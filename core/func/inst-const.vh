// Length => inst[1:0]
`define INST_NOT_COMPRESSED 2'b11

// Opcode => inst[6:2]
`define OP_ALU_RTYPE 5'b01100
`define OP_ALU_ITYPE 5'b00100
`define OP_LUI 5'b01101
`define OP_AUIPC 5'b00101
`define OP_JAL 5'b11011
`define OP_JALR 5'b11001
`define OP_BRANCH 5'b11000
`define OP_LOAD 5'b00000
`define OP_STORE 5'b01000
`define OP_MISC_MEM 5'b00011

// Lower 3 bits of funct7 of ALU RTYPE
`define FUNCT7_INTEGER 3'b000
`define FUNCT7_MULDIV 3'b001
`define FUNCT7_ZICOND 3'b111

// Branch Funct3
`define FUNCT3_BEQ 3'b000
`define FUNCT3_BNE 3'b001
`define FUNCT3_BLT 3'b100
`define FUNCT3_BGE 3'b101
`define FUNCT3_BLTU 3'b110
`define FUNCT3_BGEU 3'b111

// Load Funct3
`define FUNCT3_LB 3'b000
`define FUNCT3_LH 3'b001
`define FUNCT3_LW 3'b010
`define FUNCT3_LBU 3'b100
`define FUNCT3_LHU 3'b101

// Store Funct3
`define FUNCT3_SB 3'b000
`define FUNCT3_SH 3'b001
`define FUNCT3_SW 3'b010

// Sync Funct3
`define FUNCT3_ZICOND 3'b001
