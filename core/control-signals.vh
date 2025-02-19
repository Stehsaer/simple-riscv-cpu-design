localparam WB_ALU = 2'b00;
localparam WB_PC_NEXT = 2'b01;
localparam WB_MEM = 2'b10;
localparam WB_NONE = 2'b11;

localparam PC_SEQ = 0;
localparam PC_BRANCH = 1;

localparam CMP_OP_NONE = 5'b00000;
localparam CMP_OP_ALWAYS = 5'b10000;

localparam MEM_OP_NONE = 2'b00;
localparam MEM_OP_LD = 2'b01;
localparam MEM_OP_ST = 2'b10;
