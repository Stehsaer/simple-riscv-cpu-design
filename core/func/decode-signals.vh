/*===== Decode Stage Output Signal Definitions =====*/

// ALU Number Selection

`define ALU_NUM_SEL_SIGWIDTH [3:0]

`define ALU_NUM_SEL_REG 4'd0
`define ALU_NUM_SEL_SHAMT 4'd1
`define ALU_NUM_SEL_I 4'd2
`define ALU_NUM_SEL_U 4'd3
`define ALU_NUM_SEL_PC 4'd4
`define ALU_NUM_SEL_J 4'd5
`define ALU_NUM_SEL_S 4'd6
`define ALU_NUM_SEL_B 4'd7
`define ALU_NUM_SEL_Z 4'd8
`define ALU_NUM_SEL_CSR_UIMM 4'd9

// ALU Operation

`define ALU_SECTION_SIGWIDTH [1:0]
`define ALU_OP_SIGWIDTH [3:0]

`define ALU_SECTION_INTEGER 2'b00
`define ALU_SECTION_MULDIV 2'b01
`define ALU_SECTION_ZICOND 2'b10

// Write Back Source Selection

`define WB_SRC_SIGWIDTH [2:0]

`define WB_ALU 3'b000
`define WB_PC_NEXT 3'b001
`define WB_MEM 3'b010
`define WB_NONE 3'b011
`define WB_CSR 3'b100

// PC Source Selection

`define PC_SRC_SIGWIDTH [0:0]

`define PC_SEQ 1'b0
`define PC_BRANCH 1'b1

// Compare Operation

`define CMP_OP_SIGWIDTH [1:0]
`define CMP_FUNCT_SIGWIDTH [2:0]

`define CMP_OP_NONE 2'b00
`define CMP_OP_COMPARE 2'b01
`define CMP_OP_ALWAYS 2'b10

// Memory Operation

`define MEM_OP_SIGWIDTH [1:0]
`define MEM_FUNCT_SIGWIDTH [2:0]

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

// CSR Operation

`define CSR_WRITE_SIGWIDTH [1:0]

`define CSR_WRITE_NONE 2'b00
`define CSR_WRITE_OVERWRITE 2'd1
`define CSR_WRITE_SETBITS 2'd2
`define CSR_WRITE_CLEARBITS 2'd3

// Interrupt Signals

`define INT_SIGWIDTH [5:0]
`define INT_SIGWIDTH_NUM 6

`define INT_INSTR_MISALIGN 0
`define INT_INSTR_ACCESS_FAULT 1
`define INT_ILLEGAL_INSTR 2
`define INT_LOAD_MISALIGN 4
`define INT_LOAD_ACCESS_FAULT 5
`define INT_STORE_MISALIGN 6
`define INT_STORE_ACCESS_FAULT 7
`define INT_ECALL_M 11
`define INT_MTIMER 7
`define INT_MEXT 11

// System Signals

`define SYS_SIGWIDTH [1:0]
`define SYS_ECALL 2'b01
`define SYS_EBREAK 2'b10
`define SYS_MRET 2'b11
