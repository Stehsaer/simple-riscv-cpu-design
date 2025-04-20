`include "inst-const.vh"

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
    output reg  [1:0] cmp_op_o,      // Branch Unit Compare Opcode
    output reg  [2:0] cmp_funct_o,
    output reg  [1:0] mem_op_o,      // Memory Unit Opcode
    output reg  [2:0] mem_funct_o,
    output reg        bp_enabled_o,  // Branch Prediction Enabled
    output wire       fencei_o       // Fence.i instruction
);
    `include "decode-signals.vh"

    /* INSTR CONSTANT */

    assign wb_reg_onehot_o = 1 << wb_reg_o;

    // Input Slicing
    wire [1:0] op_length = inst_i[1:0];
    wire [4:0] opcode = inst_i[6:2];
    wire [2:0] funct3 = inst_i[14:12];
    wire [6:0] funct7 = inst_i[31:25];
    wire [4:0] rd = inst_i[11:7];

    always @(*) begin
        case (opcode)
            `OP_ALU_RTYPE: begin
                rs1_req_o = 1;
                rs2_req_o = 1;
            end
            `OP_ALU_ITYPE: begin
                rs1_req_o = 1;
                rs2_req_o = 0;
            end
            `OP_JALR: begin
                rs1_req_o = 1;
                rs2_req_o = 0;
            end
            `OP_BRANCH: begin
                rs1_req_o = 1;
                rs2_req_o = 1;
            end
            `OP_LOAD: begin
                rs1_req_o = 1;
                rs2_req_o = 0;
            end
            `OP_STORE: begin
                rs1_req_o = 1;
                rs2_req_o = 1;
            end

            // LUI, AUIPC, JAL, SYNC
            default: begin
                rs1_req_o = 0;
                rs2_req_o = 0;
            end
        endcase
    end

    // Alu Opcode
    always @(*) begin
        case (opcode)
            `OP_ALU_RTYPE: begin
                case (funct7[2:0])
                    `FUNCT7_INTEGER: begin
                        alu_section_o = `ALU_SECTION_INTEGER;
                        alu_op_o      = {funct7[5], funct3};
                    end
                    `FUNCT7_MULDIV: begin
                        alu_section_o = `ALU_SECTION_MULDIV;
                        alu_op_o      = {1'b0, funct3};
                    end
                    `FUNCT7_ZICOND: begin
                        alu_section_o = `ALU_SECTION_ZICOND;
                        alu_op_o      = {1'b0, funct3};
                    end
                    default: begin
                        alu_section_o = `ALU_SECTION_INTEGER;
                        alu_op_o      = 0;
                    end
                endcase
            end
            `OP_ALU_ITYPE: begin
                alu_section_o = `ALU_SECTION_INTEGER;
                case (funct3)
                    3'b101:  alu_op_o = {funct7[5], funct3};  // SRLI/SRAI
                    default: alu_op_o = {1'b0, funct3};  // Others
                endcase
            end
            default: begin
                alu_section_o = `ALU_SECTION_INTEGER;
                alu_op_o      = 0;
            end
        endcase
    end

    // Alu Operand Selection
    always @(*) begin
        case (opcode)
            `OP_ALU_RTYPE: begin
                alu_num1_sel_o = `ALU_NUM_SEL_REG;
                alu_num2_sel_o = `ALU_NUM_SEL_REG;
            end
            `OP_ALU_ITYPE: begin
                alu_num1_sel_o = `ALU_NUM_SEL_REG;
                case (funct3)
                    3'b101:  alu_num2_sel_o = `ALU_NUM_SEL_SHAMT;
                    default: alu_num2_sel_o = `ALU_NUM_SEL_I;
                endcase
            end
            `OP_LUI: begin
                alu_num1_sel_o = `ALU_NUM_SEL_Z;
                alu_num2_sel_o = `ALU_NUM_SEL_U;
            end
            `OP_AUIPC: begin
                alu_num1_sel_o = `ALU_NUM_SEL_PC;
                alu_num2_sel_o = `ALU_NUM_SEL_U;
            end
            `OP_JAL: begin
                alu_num1_sel_o = `ALU_NUM_SEL_PC;
                alu_num2_sel_o = `ALU_NUM_SEL_J;
            end
            `OP_JALR: begin
                alu_num1_sel_o = `ALU_NUM_SEL_REG;
                alu_num2_sel_o = `ALU_NUM_SEL_I;
            end
            `OP_BRANCH: begin
                alu_num1_sel_o = `ALU_NUM_SEL_PC;
                alu_num2_sel_o = `ALU_NUM_SEL_B;
            end
            `OP_LOAD: begin
                alu_num1_sel_o = `ALU_NUM_SEL_REG;
                alu_num2_sel_o = `ALU_NUM_SEL_I;
            end
            `OP_STORE: begin
                alu_num1_sel_o = `ALU_NUM_SEL_REG;
                alu_num2_sel_o = `ALU_NUM_SEL_S;
            end
            default: begin
                alu_num1_sel_o = `ALU_NUM_SEL_Z;
                alu_num2_sel_o = `ALU_NUM_SEL_Z;
            end
        endcase
    end

    // Writeback Selection
    always @(*) begin
        case (opcode)
            // ALU as writeback result
            `OP_ALU_RTYPE, `OP_ALU_ITYPE, `OP_LUI, `OP_AUIPC: wb_sel_o = `WB_ALU;
            // PC of next adjacent instruction
            `OP_JAL, `OP_JALR: wb_sel_o = `WB_PC_NEXT;
            // No writeback
            `OP_BRANCH, `OP_STORE: wb_sel_o = `WB_NONE;
            // Memory Load as writeback result
            `OP_LOAD: wb_sel_o = `WB_MEM;
            default: wb_sel_o = `WB_NONE;
        endcase
    end

    // Writeback Register
    always @(*) begin
        case (opcode)
            `OP_BRANCH, `OP_STORE: wb_reg_o = 5'b0;
            default: wb_reg_o = rd;
        endcase
    end

    // PC Selection
    always @(*) begin
        case (opcode)
            `OP_JAL, `OP_JALR, `OP_BRANCH: pc_sel_o = `PC_BRANCH;
            default: pc_sel_o = `PC_SEQ;
        endcase
    end

    // Compare Opcode
    always @(*) begin
        case (opcode)
            `OP_JAL, `OP_JALR: begin
                cmp_op_o    = `CMP_OP_ALWAYS;
                cmp_funct_o = 3'b0;
            end
            `OP_BRANCH: begin
                cmp_op_o    = `CMP_OP_COMPARE;
                cmp_funct_o = funct3;
            end
            default: begin
                cmp_op_o    = `CMP_OP_NONE;
                cmp_funct_o = 3'b0;
            end
        endcase
    end

    // Memory Unit Opcode
    always @(*) begin
        case (opcode)
            `OP_LOAD:  {mem_op_o, mem_funct_o} = {`MEM_OP_LD, funct3};
            `OP_STORE: {mem_op_o, mem_funct_o} = {`MEM_OP_ST, funct3};
            default:   {mem_op_o, mem_funct_o} = {`MEM_OP_NONE, 3'b0};
        endcase
    end

    // Branch Prediction Enabled
    always @(*) begin
        case (opcode)
            `OP_JAL, `OP_BRANCH: bp_enabled_o = 1;
            default: bp_enabled_o = 0;
        endcase
    end

    assign fencei_o = opcode == `OP_MISC_MEM && funct3 == `FUNCT3_ZICOND;  // Zifencei

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

    /* Data Hazard Detection */

    input wire [31:1] wb_reg_onfly_i,

    input wire [ 4:0] ex_modify_reg_i,
    input wire [31:0] ex_modify_data_i,
    input wire        ex_modify_data_valid_i,

    input wire [ 4:0] mem1_modify_reg_i,
    input wire [31:0] mem1_modify_data_i,
    input wire        mem1_modify_data_valid_i,

    input wire [ 4:0] mem2_modify_reg_i,
    input wire [31:0] mem2_modify_data_i,
    input wire        mem2_modify_data_valid_i,

    output reg [31:0] alu_num1_o,
    output reg [31:0] alu_num2_o,

    output wire [31:0] cmp_num1_o,
    output wire [31:0] cmp_num2_o,

    output wire [31:0] mem_wdata_o,

    output wire stall_o
);
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

    // One Hot Mask
    // [0] = None
    // [1] = EX
    // [2] = MEM1
    // [3] = MEM2/WB
    // [4] = Register

    wire [4:0] rs1_raw_bits = {
        1'b1, rs1 == mem2_modify_reg_i, rs1 == mem1_modify_reg_i, rs1 == ex_modify_reg_i, rs1 == 0
    };

    wire [4:0] rs2_raw_bits = {
        1'b1, rs2 == mem2_modify_reg_i, rs2 == mem1_modify_reg_i, rs2 == ex_modify_reg_i, rs2 == 0
    };

    wire [4:0] rs1_raw_bits_onehot = rs1_raw_bits & ~(rs1_raw_bits - 1);
    wire [4:0] rs2_raw_bits_onehot = rs2_raw_bits & ~(rs2_raw_bits - 1);

    wire [31:0] rs1_read_data = 
    {32{rs1_raw_bits_onehot[1]}} & ex_modify_data_i |  
    {32{rs1_raw_bits_onehot[2]}} & mem1_modify_data_i |
    {32{rs1_raw_bits_onehot[3]}} & mem2_modify_data_i |
    {32{rs1_raw_bits_onehot[4]}} & reg_rdata1;

    wire [31:0] rs2_read_data = 
    {32{rs2_raw_bits_onehot[1]}} & ex_modify_data_i |
    {32{rs2_raw_bits_onehot[2]}} & mem1_modify_data_i |
    {32{rs2_raw_bits_onehot[3]}} & mem2_modify_data_i |
    {32{rs2_raw_bits_onehot[4]}} & reg_rdata2;

    wire rs1_raw = 
    rs1_raw_bits_onehot[1] & !ex_modify_data_valid_i |
    rs1_raw_bits_onehot[2] & !mem1_modify_data_valid_i |
    rs1_raw_bits_onehot[3] & !mem2_modify_data_valid_i |
    rs1_raw_bits_onehot[4] & (|(wb_reg_onfly_i & rs1_onehot)); // TODO: Remove redundant logic

    wire rs2_raw = 
    rs2_raw_bits_onehot[1] & !ex_modify_data_valid_i |
    rs2_raw_bits_onehot[2] & !mem1_modify_data_valid_i |
    rs2_raw_bits_onehot[3] & !mem2_modify_data_valid_i |
    rs2_raw_bits_onehot[4] & (|(wb_reg_onfly_i & rs2_onehot)); // TODO: Remove redundant logic

    assign stall_o     = rs1_raw && rs1_req_i || rs2_raw && rs2_req_i;

    // Selection

    assign cmp_num1_o  = rs1_read_data;
    assign cmp_num2_o  = rs2_read_data;
    assign mem_wdata_o = rs2_read_data;

    always @(*)
        case (alu_num1_sel_i)
            `ALU_NUM_SEL_REG: alu_num1_o = rs1_read_data;
            `ALU_NUM_SEL_SHAMT: alu_num1_o = shamt_sext;
            `ALU_NUM_SEL_I: alu_num1_o = imm_i_sext;
            `ALU_NUM_SEL_U: alu_num1_o = imm_u;
            `ALU_NUM_SEL_PC: alu_num1_o = pc_i;
            `ALU_NUM_SEL_J: alu_num1_o = imm_j_sext;
            `ALU_NUM_SEL_S: alu_num1_o = imm_s_sext;
            `ALU_NUM_SEL_B: alu_num1_o = imm_b_sext;
            default: alu_num1_o = 32'd0;
        endcase

    always @(*)
        case (alu_num2_sel_i)
            `ALU_NUM_SEL_REG: alu_num2_o = rs2_read_data;
            `ALU_NUM_SEL_SHAMT: alu_num2_o = shamt_sext;
            `ALU_NUM_SEL_I: alu_num2_o = imm_i_sext;
            `ALU_NUM_SEL_U: alu_num2_o = imm_u;
            `ALU_NUM_SEL_PC: alu_num2_o = pc_i;
            `ALU_NUM_SEL_J: alu_num2_o = imm_j_sext;
            `ALU_NUM_SEL_S: alu_num2_o = imm_s_sext;
            `ALU_NUM_SEL_B: alu_num2_o = imm_b_sext;
            default: alu_num2_o = 32'd0;
        endcase

endmodule



