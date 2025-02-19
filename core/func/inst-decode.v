module inst_decode_v2_stage1 (
    input wire [31:0] inst_i,  // Instruction Input
    input wire [31:0] pc_i,    // PC Input

    output reg [3:0] alu_op_o,  // ALU Opcode
    output reg [1:0] alu_section_o,  // ALU Section
    output reg [3:0] alu_num1_sel_o,  // ALU Operand 1 Select
    output reg [3:0] alu_num2_sel_o,  // ALU Operand 2 Select

    output reg [1:0] wb_sel_o,  // Writeback Source Select
    output reg [4:0] wb_reg_o,  // Writeback Register
    output wire [31:1] wb_reg_onehot_o,  // Writeback Register Onehot, for bypass

    output reg rs1_req_o,  // Read Register 1 Request, HIGH if needed
    output reg rs2_req_o,  // Read Register 2 Request, HIGH if needed

    output reg        pc_sel_o,      // PC Write Select
    output reg  [4:0] cmp_op_o,      // Branch Unit Compare Opcode
    output reg  [4:0] mem_op_o,      // Memory Unit Opcode
    output reg        bp_enabled_o,  // Branch Prediction Enabled
    output wire       fencei_o       // Fence.i instruction
);

    `include "control-signals.vh"

    localparam ALU_NUM_SEL_REG = 4'd0;
    localparam ALU_NUM_SEL_SHAMT = 4'd1;
    localparam ALU_NUM_SEL_I = 4'd2;
    localparam ALU_NUM_SEL_U = 4'd3;
    localparam ALU_NUM_SEL_PC = 4'd4;
    localparam ALU_NUM_SEL_J = 4'd5;
    localparam ALU_NUM_SEL_S = 4'd6;
    localparam ALU_NUM_SEL_B = 4'd7;
    localparam ALU_NUM_SEL_Z = 4'd8;

    localparam ALU_SECTION_INTEGER = 2'b00;
    localparam ALU_SECTION_MULDIV = 2'b01;
    localparam ALU_SECTION_ZICOND = 2'b10;


    /* INSTR CONSTANT */

    localparam ALU_OP_RTYPE = 7'b0110011;
    localparam ALU_OP_ITYPE = 7'b0010011;

    localparam LUI = 7'b0110111;
    localparam AUIPC = 7'b0010111;

    localparam JAL = 7'b1101111;
    localparam JALR = 7'b1100111;

    localparam BRANCH_OP = 7'b1100011;

    localparam SYNC_OP = 7'b0001111;  // Fence.i

    localparam BEQ = 3'b000;
    localparam BNE = 3'b001;
    localparam BLT = 3'b100;
    localparam BGE = 3'b101;
    localparam BLTU = 3'b110;
    localparam BGEU = 3'b111;

    localparam LD_OP = 7'b0000011;

    localparam LW = 3'b010;
    localparam LH = 3'b001;
    localparam LB = 3'b000;
    localparam LHU = 3'b101;
    localparam LBU = 3'b100;

    localparam ST_OP = 7'b0100011;

    localparam SW = 3'b010;
    localparam SH = 3'b001;
    localparam SB = 3'b000;

    localparam INTEGER_FUNCT7 = 3'b000;
    localparam MULDIV_FUNCT7 = 3'b001;
    localparam ZICOND_FUNCT7 = 3'b111;

    assign wb_reg_onehot_o = 1 << wb_reg_o;

    wire [6:0] opcode = inst_i[6:0];

    wire [2:0] funct3 = inst_i[14:12];
    wire [6:0] funct7 = inst_i[31:25];

    wire [4:0] rd = inst_i[11:7];

    always @(*) begin
        case (opcode)
            ALU_OP_RTYPE: begin
                rs1_req_o = 1;
                rs2_req_o = 1;
            end
            ALU_OP_ITYPE: begin
                rs1_req_o = 1;
                rs2_req_o = 0;
            end
            JALR: begin
                rs1_req_o = 1;
                rs2_req_o = 0;
            end
            BRANCH_OP: begin
                rs1_req_o = 1;
                rs2_req_o = 1;
            end
            LD_OP: begin
                rs1_req_o = 1;
                rs2_req_o = 0;
            end
            ST_OP: begin
                rs1_req_o = 1;
                rs2_req_o = 1;
            end
            default: begin
                rs1_req_o = 0;
                rs2_req_o = 0;
            end
        endcase
    end

    // Alu Opcode
    always @(*) begin
        case (opcode)
            ALU_OP_RTYPE: begin
                case (funct7[2:0])
                    INTEGER_FUNCT7: begin
                        alu_section_o = ALU_SECTION_INTEGER;
                        alu_op_o      = {funct7[5], funct3};
                    end
                    MULDIV_FUNCT7: begin
                        alu_section_o = ALU_SECTION_MULDIV;
                        alu_op_o      = {1'b0, funct3};
                    end
                    ZICOND_FUNCT7: begin
                        alu_section_o = ALU_SECTION_ZICOND;
                        alu_op_o      = {1'b0, funct3};
                    end
                    default: begin
                        alu_section_o = ALU_SECTION_INTEGER;
                        alu_op_o      = 0;
                    end
                endcase
            end
            ALU_OP_ITYPE: begin
                alu_section_o = ALU_SECTION_INTEGER;
                case (funct3)
                    3'b101:  alu_op_o = {funct7[5], funct3};  // SRLI/SRAI
                    default: alu_op_o = {1'b0, funct3};  // Others
                endcase
            end
            default: begin
                alu_section_o = ALU_SECTION_INTEGER;
                alu_op_o      = 0;
            end
        endcase
    end

    // Alu Operand Selection
    always @(*) begin
        case (opcode)
            ALU_OP_RTYPE: begin
                alu_num1_sel_o = ALU_NUM_SEL_REG;
                alu_num2_sel_o = ALU_NUM_SEL_REG;
            end
            ALU_OP_ITYPE: begin
                alu_num1_sel_o = ALU_NUM_SEL_REG;
                case (funct3)
                    3'b101:  alu_num2_sel_o = ALU_NUM_SEL_SHAMT;
                    default: alu_num2_sel_o = ALU_NUM_SEL_I;
                endcase
            end
            LUI: begin
                alu_num1_sel_o = ALU_NUM_SEL_Z;
                alu_num2_sel_o = ALU_NUM_SEL_U;
            end
            AUIPC: begin
                alu_num1_sel_o = ALU_NUM_SEL_PC;
                alu_num2_sel_o = ALU_NUM_SEL_U;
            end
            JAL: begin
                alu_num1_sel_o = ALU_NUM_SEL_PC;
                alu_num2_sel_o = ALU_NUM_SEL_J;
            end
            JALR: begin
                alu_num1_sel_o = ALU_NUM_SEL_REG;
                alu_num2_sel_o = ALU_NUM_SEL_I;
            end
            BRANCH_OP: begin
                alu_num1_sel_o = ALU_NUM_SEL_PC;
                alu_num2_sel_o = ALU_NUM_SEL_B;
            end
            LD_OP: begin
                alu_num1_sel_o = ALU_NUM_SEL_REG;
                alu_num2_sel_o = ALU_NUM_SEL_I;
            end
            ST_OP: begin
                alu_num1_sel_o = ALU_NUM_SEL_REG;
                alu_num2_sel_o = ALU_NUM_SEL_S;
            end
            default: begin
                alu_num1_sel_o = ALU_NUM_SEL_Z;
                alu_num2_sel_o = ALU_NUM_SEL_Z;
            end
        endcase
    end

    // Writeback Selection
    always @(*) begin
        case (opcode)
            ALU_OP_RTYPE, ALU_OP_ITYPE, LUI, AUIPC: wb_sel_o = WB_ALU;
            JAL, JALR: wb_sel_o = WB_PC_NEXT;
            BRANCH_OP, ST_OP: wb_sel_o = WB_NONE;
            LD_OP: wb_sel_o = WB_MEM;
            default: wb_sel_o = WB_NONE;
        endcase
    end

    // Writeback Register
    always @(*) begin
        case (opcode)
            BRANCH_OP, ST_OP: wb_reg_o = 5'b0;
            default: wb_reg_o = rd;
        endcase
    end

    // PC Selection
    always @(*) begin
        case (opcode)
            JAL, JALR, BRANCH_OP: pc_sel_o = PC_BRANCH;
            default: pc_sel_o = PC_SEQ;
        endcase
    end

    // Compare Opcode
    always @(*) begin
        case (opcode)
            JAL, JALR: cmp_op_o = CMP_OP_ALWAYS;
            BRANCH_OP: cmp_op_o = {2'b01, funct3};
            default:   cmp_op_o = CMP_OP_NONE;
        endcase
    end

    // Memory Unit Opcode
    always @(*) begin
        case (opcode)
            LD_OP:   mem_op_o = {MEM_OP_LD, funct3};
            ST_OP:   mem_op_o = {MEM_OP_ST, funct3};
            default: mem_op_o = {MEM_OP_NONE, 3'b0};
        endcase
    end

    // Branch Prediction Enabled
    always @(*) begin
        case (opcode)
            JAL, BRANCH_OP: bp_enabled_o = 1;
            default: bp_enabled_o = 0;
        endcase
    end

    assign fencei_o = opcode == SYNC_OP && funct3 == 3'b001;  // Zifencei

endmodule

module inst_decode_v2_stage2 (
    input wire [31:0] inst_i,
    input wire [31:0] pc_i,

    // Register File Access

    output wire [ 4:0] reg_raddr1,
    output wire [ 4:0] reg_raddr2,
    input  wire [31:0] reg_rdata1,
    input  wire [31:0] reg_rdata2,

    input wire rs1_req_i,
    input wire rs2_req_i,

    input wire [3:0] alu_num1_sel_i,  // ALU Operand 1 Select
    input wire [3:0] alu_num2_sel_i,  // ALU Operand 2 Select

    /* Bypass */

    input wire [31:1] wb_reg_onfly_i,

    input wire [ 4:0] ex_id_wb_reg_i,
    input wire [31:0] ex_id_wb_data_i,
    input wire        ex_id_wb_valid_i,


    input wire [ 4:0] mem1_id_wb_reg_i,
    input wire [31:0] mem1_id_wb_data_i,
    input wire        mem1_id_wb_valid_i,

    input wire [ 4:0] mem2_id_wb_reg_i,
    input wire [31:0] mem2_id_wb_data_i,
    input wire        mem2_id_wb_valid_i,

    output reg [31:0] alu_num1_o,
    output reg [31:0] alu_num2_o,

    output wire [31:0] cmp_num1_o,
    output wire [31:0] cmp_num2_o,

    output wire [31:0] mem_wdata_o,

    output wire stall_o
);
    localparam ALU_NUM_SEL_REG = 4'd0;
    localparam ALU_NUM_SEL_SHAMT = 4'd1;
    localparam ALU_NUM_SEL_I = 4'd2;
    localparam ALU_NUM_SEL_U = 4'd3;
    localparam ALU_NUM_SEL_PC = 4'd4;
    localparam ALU_NUM_SEL_J = 4'd5;
    localparam ALU_NUM_SEL_S = 4'd6;
    localparam ALU_NUM_SEL_B = 4'd7;
    localparam ALU_NUM_SEL_Z = 4'd8;

    wire [ 6:0] opcode = inst_i[6:0];

    wire [ 4:0] rd = inst_i[11:7];

    wire [ 4:0] rs1 = inst_i[19:15];

    wire [ 4:0] rs2 = inst_i[24:20];

    wire [11:0] imm_i = inst_i[31:20];
    wire [31:0] imm_i_sext = {{20{imm_i[11]}}, imm_i};

    wire [ 4:0] shamt = inst_i[24:20];
    wire [31:0] shamt_sext = {27'b0, shamt};

    wire [11:0] imm_s = {inst_i[31:25], inst_i[11:7]};
    wire [31:0] imm_s_sext = {{20{imm_s[11]}}, imm_s};

    wire [12:0] imm_b = {inst_i[31], inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
    wire [31:0] imm_b_sext = {{19{imm_b[12]}}, imm_b};

    wire [31:0] imm_u = {inst_i[31:12], 12'b0};

    wire [20:0] imm_j = {inst_i[31], inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
    wire [31:0] imm_j_sext = {{11{imm_j[20]}}, imm_j};

    // Data Hazard Detection

    assign reg_raddr1 = rs1;
    assign reg_raddr2 = rs2;

    wire [31:1] rs1_onehot = 1 << rs1;
    wire [31:1] rs2_onehot = 1 << rs2;

    wire [4:0] rs1_raw_bits = {
        1'b1, rs1 == mem2_id_wb_reg_i, rs1 == mem1_id_wb_reg_i, rs1 == ex_id_wb_reg_i, rs1 == 0
    };

    wire [4:0] rs2_raw_bits = {
        1'b1, rs2 == mem2_id_wb_reg_i, rs2 == mem1_id_wb_reg_i, rs2 == ex_id_wb_reg_i, rs2 == 0
    };

    wire [4:0] rs1_raw_bits_onehot = rs1_raw_bits & ~(rs1_raw_bits - 1);
    wire [4:0] rs2_raw_bits_onehot = rs2_raw_bits & ~(rs2_raw_bits - 1);

    wire [31:0] rs1_read_data = 
    {32{rs1_raw_bits_onehot[1]}} & ex_id_wb_data_i |  
    {32{rs1_raw_bits_onehot[2]}} & mem1_id_wb_data_i |
    {32{rs1_raw_bits_onehot[3]}} & mem2_id_wb_data_i |
    {32{rs1_raw_bits_onehot[4]}} & reg_rdata1;

    wire [31:0] rs2_read_data = 
    {32{rs2_raw_bits_onehot[1]}} & ex_id_wb_data_i |
    {32{rs2_raw_bits_onehot[2]}} & mem1_id_wb_data_i |
    {32{rs2_raw_bits_onehot[3]}} & mem2_id_wb_data_i |
    {32{rs2_raw_bits_onehot[4]}} & reg_rdata2;

    wire rs1_raw = 
    rs1_raw_bits_onehot[1] & !ex_id_wb_valid_i |
    rs1_raw_bits_onehot[2] & !mem1_id_wb_valid_i |
    rs1_raw_bits_onehot[3] & !mem2_id_wb_valid_i |
    rs1_raw_bits_onehot[4] & (|(wb_reg_onfly_i & rs1_onehot));

    wire rs2_raw = 
    rs2_raw_bits_onehot[1] & !ex_id_wb_valid_i |
    rs2_raw_bits_onehot[2] & !mem1_id_wb_valid_i |
    rs2_raw_bits_onehot[3] & !mem2_id_wb_valid_i |
    rs2_raw_bits_onehot[4] & (|(wb_reg_onfly_i & rs2_onehot));

    assign stall_o     = rs1_raw && rs1_req_i || rs2_raw && rs2_req_i;

    // Selection

    assign cmp_num1_o  = rs1_read_data;
    assign cmp_num2_o  = rs2_read_data;
    assign mem_wdata_o = rs2_read_data;

    always @(*)
        case (alu_num1_sel_i)
            ALU_NUM_SEL_REG: alu_num1_o = rs1_read_data;
            ALU_NUM_SEL_SHAMT: alu_num1_o = shamt_sext;
            ALU_NUM_SEL_I: alu_num1_o = imm_i_sext;
            ALU_NUM_SEL_U: alu_num1_o = imm_u;
            ALU_NUM_SEL_PC: alu_num1_o = pc_i;
            ALU_NUM_SEL_J: alu_num1_o = imm_j_sext;
            ALU_NUM_SEL_S: alu_num1_o = imm_s_sext;
            ALU_NUM_SEL_B: alu_num1_o = imm_b_sext;
            default: alu_num1_o = 32'd0;
        endcase

    always @(*)
        case (alu_num2_sel_i)
            ALU_NUM_SEL_REG: alu_num2_o = rs2_read_data;
            ALU_NUM_SEL_SHAMT: alu_num2_o = shamt_sext;
            ALU_NUM_SEL_I: alu_num2_o = imm_i_sext;
            ALU_NUM_SEL_U: alu_num2_o = imm_u;
            ALU_NUM_SEL_PC: alu_num2_o = pc_i;
            ALU_NUM_SEL_J: alu_num2_o = imm_j_sext;
            ALU_NUM_SEL_S: alu_num2_o = imm_s_sext;
            ALU_NUM_SEL_B: alu_num2_o = imm_b_sext;
            default: alu_num2_o = 32'd0;
        endcase

endmodule



