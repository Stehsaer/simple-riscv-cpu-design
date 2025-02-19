//===============
// ALU Module
//===============
// alu_op_i：ALU Opcode
// alu_num1_i：ALU Number 1
// alu_num2_i：ALU Number 2
// alu_result_o：ALU Result
// alu_valid_i：ALU Valid Input. Performs ALU operation when high.
// alu_busy_o：ALU Busy Output. Indicates that the ALU is busy.
// 
// Opcode Section (2 MSB)：
// +=========+===============+
// |  Name   | alu_op_i[5:4] |
// +=========+===============+
// | Integer | 2'b00         |
// +---------+---------------+
// | Mul&Div | 2'b01         |
// +---------+---------------+
//
// Integer Opcode：
// +======+===============+=============+
// |  Op  | alu_op_i[2:0] | alu_op_i[3] |
// +======+===============+=============+
// | Add  |           000 |           0 |
// +------+---------------+-------------+
// | Sub  |           000 |           1 |
// +------+---------------+-------------+
// | Sll  |           001 |           0 |
// +------+---------------+-------------+
// | Slt  |           010 |           0 |
// +------+---------------+-------------+
// | Sltu |           011 |           0 |
// +------+---------------+-------------+
// | Xor  |           100 |           0 |
// +------+---------------+-------------+
// | Srl  |           101 |           0 |
// +------+---------------+-------------+
// | Sra  |           101 |           1 |
// +------+---------------+-------------+
// | Or   |           110 |           0 |
// +------+---------------+-------------+
// | And  |           111 |           0 |
// +------+---------------+-------------+
//
// Mul&Div Opcode：
// +========+===============+=============+
// |   Op   | alu_op_i[2:0] | alu_op_i[3] |
// +========+===============+=============+
// | Mul    |           000 |           0 |
// +--------+---------------+-------------+
// | Mulh   |           001 |           0 |
// +--------+---------------+-------------+
// | Mulhsu |           010 |           0 |
// +--------+---------------+-------------+
// | Mulhu  |           011 |           0 |
// +--------+---------------+-------------+
// | Div    |           100 |           0 |
// +--------+---------------+-------------+
// | Divu   |           101 |           0 |
// +--------+---------------+-------------+
// | Rem    |           110 |           0 |
// +--------+---------------+-------------+
// | Remu   |           111 |           0 |
// +--------+---------------+-------------+
//
// ALU FSM:
// +------------+--------+-------+
// |    Name    | Number | Busy  |
// +------------+--------+-------+
// | Init.      |      0 | False |
// | Mul Clk1   |      1 | True  |
// | Mul Clk2   |      2 | True  |
// | Mul Clk3   |      3 | True  |
// | Mul Clk4   |      4 | True  |
// | Mul Finish |      5 | False |
// | Div Wait   |      6 | True  |
// +------------+--------+-------+

module alu (
    input wire clk_i,
    input wire rst_i,
    input wire [3:0] alu_op_i,
    input wire [1:0] alu_section_i,
    input wire [31:0] alu_num1_i,
    input wire [31:0] alu_num2_i,
    output reg [31:0] alu_result_o,
    output wire [31:0] alu_add_result_o,
    input wire alu_valid_i,
    output reg alu_busy_o
);
    /* PARAMETERS */

    localparam ALU_SECTION_INTEGER = 2'b00;
    localparam ALU_SECTION_MULDIV = 2'b01;
    localparam ALU_SECTION_ZICOND = 2'b10;

    localparam ALU_OP_INTEGER_ADD = 4'b0000;
    localparam ALU_OP_INTEGER_SUB = 4'b1000;
    localparam ALU_OP_INTEGER_SLL = 4'b0001;
    localparam ALU_OP_INTEGER_SLT = 4'b0010;
    localparam ALU_OP_INTEGER_SLTU = 4'b0011;
    localparam ALU_OP_INTEGER_XOR = 4'b0100;
    localparam ALU_OP_INTEGER_SRL = 4'b0101;
    localparam ALU_OP_INTEGER_SRA = 4'b1101;
    localparam ALU_OP_INTEGER_OR = 4'b0110;
    localparam ALU_OP_INTEGER_AND = 4'b0111;

    localparam ALU_OP_MULDIV_MUL = 3'b000;
    localparam ALU_OP_MULDIV_MULH = 3'b001;
    localparam ALU_OP_MULDIV_MULHSU = 3'b010;
    localparam ALU_OP_MULDIV_MULHU = 3'b011;
    localparam ALU_OP_MULDIV_DIV = 3'b100;
    localparam ALU_OP_MULDIV_DIVU = 3'b101;
    localparam ALU_OP_MULDIV_REM = 3'b110;
    localparam ALU_OP_MULDIV_REMU = 3'b111;

    localparam ALU_OP_ZICOND_CZERO_EQZ = 3'b101;
    localparam ALU_OP_ZICOND_CZERO_NEZ = 3'b111;

    localparam ALU_STATE_INTEGER = 0;
    localparam ALU_STATE_MUL_CLK1 = 1;
    localparam ALU_STATE_MUL_CLK2 = 2;
    localparam ALU_STATE_MUL_CLK3 = 3;
    localparam ALU_STATE_MUL_CLK4 = 4;
    localparam ALU_STATE_MUL_FINISH = 5;
    localparam ALU_STATE_DIV_WAIT = 6;

    /* FSM TRANSFER LOGIC */

    reg [2:0] alu_state;
    wire div_done;  // Division Done

    wire is_division = alu_op_i[2] == 1;

    always @(posedge clk_i or negedge rst_i) begin
        if (!rst_i) alu_state <= 0;
        else begin
            case (alu_state)

                ALU_STATE_INTEGER:
                if (alu_valid_i)
                    if (alu_section_i == ALU_SECTION_MULDIV) begin
                        alu_state <= is_division ? 6 : 1; // Multiply -> Go to Mul Clk1, Divide -> Go to Div Wait
                    end

                ALU_STATE_MUL_CLK1:   alu_state <= 2;
                ALU_STATE_MUL_CLK2:   alu_state <= 3;
                ALU_STATE_MUL_CLK3:   alu_state <= 4;
                ALU_STATE_MUL_CLK4:   alu_state <= 5;
                ALU_STATE_MUL_FINISH: alu_state <= 0;

                ALU_STATE_DIV_WAIT: if (div_done) alu_state <= 0;
            endcase
        end
    end

    // Divisor Transmit Valid
    wire div_tx_valid = 
        alu_valid_i 
        && alu_state != ALU_STATE_DIV_WAIT 
        && alu_section_i == ALU_SECTION_MULDIV 
        && is_division;

    wire [63:0] div_result;
    wire [63:0] mul_result;
    wire divide_by_zero = alu_num2_i == 0;

    // Sign Detection
    wire num1_sign = alu_num1_i[31], num2_sign = alu_num2_i[31];
    reg num1_sign_en, num2_sign_en;  // Sign Detection Enable
    wire result_sign_flip = (num1_sign && num1_sign_en) ^ (num2_sign && num2_sign_en);  // Result Sign Flip

    // Flip Division Results & Handle Division by Zero
    wire[31:0] div_result_quotient = divide_by_zero ? 32'hFFFFFFFF : result_sign_flip ? -div_result[63:32] : div_result[63:32];  // Division Result Quotient
    wire[31:0] div_result_remainder = divide_by_zero ? alu_num1_i : result_sign_flip ? -div_result[31:0] : div_result[31:0];  // Division Result Remainder

    // Flip Multiplication Results
    wire [63:0] signed_mul_result = result_sign_flip ? -mul_result : mul_result;  // Signed Multiplication Result

    // Generate absolute values for hardware multiplier and divider
    wire [31:0] abs_num1 = num1_sign && num1_sign_en ? -alu_num1_i : alu_num1_i, 
        abs_num2 = num2_sign && num2_sign_en ? -alu_num2_i : alu_num2_i;

    always @(*) begin
        case (alu_op_i[2:0])

            ALU_OP_MULDIV_MUL, ALU_OP_MULDIV_MULH, ALU_OP_MULDIV_DIV, ALU_OP_MULDIV_REM: begin
                num1_sign_en = 1;
                num2_sign_en = 1;
            end

            ALU_OP_MULDIV_MULHSU: begin
                num1_sign_en = 1;
                num2_sign_en = 0;
            end

            default: begin
                num1_sign_en = 0;
                num2_sign_en = 0;
            end
        endcase
    end

    always @(*) begin
        case (alu_state)
            ALU_STATE_INTEGER: alu_busy_o = alu_section_i == ALU_SECTION_MULDIV;
            ALU_STATE_MUL_CLK1, ALU_STATE_MUL_CLK2, ALU_STATE_MUL_CLK3, ALU_STATE_MUL_CLK4:
            alu_busy_o = 1;
            ALU_STATE_MUL_FINISH: alu_busy_o = 0;
            ALU_STATE_DIV_WAIT: alu_busy_o = !div_done;
            default: alu_busy_o = 0;
        endcase
    end

    mult_dsp mul_module (
        .CLK(clk_i),
        .A  (abs_num1),
        .B  (abs_num2),
        .P  (mul_result)
    );

    div_radix2 div_module (
        .aclk(clk_i),
        .aresetn(rst_i),
        .s_axis_divisor_tvalid(div_tx_valid),
        .s_axis_divisor_tready(),
        .s_axis_divisor_tdata(abs_num2),
        .s_axis_dividend_tvalid(div_tx_valid),
        .s_axis_dividend_tready(),
        .s_axis_dividend_tdata(abs_num1),
        .m_axis_dout_tvalid(div_done),
        .m_axis_dout_tdata(div_result)
    );

    assign alu_add_result_o = alu_num1_i + alu_num2_i;

    reg [31:0] integer_result, muldiv_result, zicond_result;

    always @(*)
        case (alu_op_i)
            ALU_OP_INTEGER_ADD: integer_result = alu_add_result_o;
            ALU_OP_INTEGER_SUB: integer_result = alu_num1_i - alu_num2_i;
            ALU_OP_INTEGER_SLL: integer_result = alu_num1_i << alu_num2_i;
            ALU_OP_INTEGER_SLT: integer_result = $signed(alu_num1_i) < $signed(alu_num2_i);
            ALU_OP_INTEGER_SLTU: integer_result = alu_num1_i < alu_num2_i;
            ALU_OP_INTEGER_XOR: integer_result = alu_num1_i ^ alu_num2_i;
            ALU_OP_INTEGER_SRL: integer_result = alu_num1_i >> $signed(alu_num2_i);
            ALU_OP_INTEGER_SRA: integer_result = $signed(alu_num1_i) >>> $signed(alu_num2_i);
            ALU_OP_INTEGER_OR: integer_result = alu_num1_i | alu_num2_i;
            ALU_OP_INTEGER_AND: integer_result = alu_num1_i & alu_num2_i;
            default: integer_result = 0;
        endcase

    always @(*)
        case (alu_op_i[2:0])
            // Mul
            ALU_OP_MULDIV_MUL: muldiv_result = signed_mul_result[31:0];

            // Mulh*
            ALU_OP_MULDIV_MULH, ALU_OP_MULDIV_MULHSU, ALU_OP_MULDIV_MULHU:
            muldiv_result = signed_mul_result[63:32];

            // Div
            ALU_OP_MULDIV_DIV, ALU_OP_MULDIV_DIVU: muldiv_result = div_result_quotient;

            // Rem
            ALU_OP_MULDIV_REM, ALU_OP_MULDIV_REMU: muldiv_result = div_result_remainder;
        endcase

    wire num2_eqz = alu_num2_i == 0;

    always @(*)
        case (alu_op_i[2:0])
            ALU_OP_ZICOND_CZERO_EQZ: zicond_result = num2_eqz ? 0 : alu_num1_i;
            ALU_OP_ZICOND_CZERO_NEZ: zicond_result = num2_eqz ? alu_num1_i : 0;
            default: zicond_result = 0;
        endcase

    always @(*)
        case (alu_section_i)
            ALU_SECTION_INTEGER: alu_result_o = integer_result;
            ALU_SECTION_MULDIV: alu_result_o = muldiv_result;
            ALU_SECTION_ZICOND: alu_result_o = zicond_result;
            default: alu_result_o = 0;
        endcase

endmodule
