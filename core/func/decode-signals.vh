// Decode Stage Output Signal Definitions

`define ALU_NUM_SEL_REG 4'd0
`define ALU_NUM_SEL_SHAMT 4'd1
`define ALU_NUM_SEL_I 4'd2
`define ALU_NUM_SEL_U 4'd3
`define ALU_NUM_SEL_PC 4'd4
`define ALU_NUM_SEL_J 4'd5
`define ALU_NUM_SEL_S 4'd6
`define ALU_NUM_SEL_B 4'd7
`define ALU_NUM_SEL_Z 4'd8

`define ALU_SECTION_INTEGER 2'b00
`define ALU_SECTION_MULDIV 2'b01
`define ALU_SECTION_ZICOND 2'b10

// Write Back Source Selection
`define WB_ALU 2'b00
`define WB_PC_NEXT 2'b01
`define WB_MEM 2'b10
`define WB_NONE 2'b11

`define PC_SEQ 1'b0
`define PC_BRANCH 1'b1

`define CMP_OP_NONE 2'b00
`define CMP_OP_COMPARE 2'b01
`define CMP_OP_ALWAYS 2'b10

`define MEM_OP_NONE 2'b00
`define MEM_OP_LD 2'b01
`define MEM_OP_ST 2'b10

`define MEM_FUNCT_NONE 3'b000
`define MEM_FUNCT_LB 3'b000
`define MEM_FUNCT_LH 3'b001
`define MEM_FUNCT_LW 3'b010
`define MEM_FUNCT_LBU 3'b100
`define MEM_FUNCT_LHU 3'b101
`define MEM_FUNCT_SB 3'b000
`define MEM_FUNCT_SH 3'b001
`define MEM_FUNCT_SW 3'b010
