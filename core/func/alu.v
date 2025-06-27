`include "decode-signals.vh"

module alu_integer (
    input  wire [ 3:0] op,
    input  wire [31:0] num1,
    input  wire [31:0] num2,
    output reg  [31:0] result,
    output wire [31:0] add
);

    `define OP_ADD 4'b0000
    `define OP_SUB 4'b1000
    `define OP_SLL 4'b0001
    `define OP_SLT 4'b0010
    `define OP_SLTU 4'b0011
    `define OP_XOR 4'b0100
    `define OP_SRL 4'b0101
    `define OP_SRA 4'b1101
    `define OP_OR 4'b0110
    `define OP_AND 4'b0111

    assign add = num1 + num2;

    always @(*)
        case (op)
            `OP_ADD:  result = add;
            `OP_SUB:  result = num1 - num2;
            `OP_SLL:  result = num1 << num2;
            `OP_SLT:  result = $signed(num1) < $signed(num2);
            `OP_SLTU: result = num1 < num2;
            `OP_XOR:  result = num1 ^ num2;
            `OP_SRL:  result = num1 >> $signed(num2);
            `OP_SRA:  result = $signed(num1) >>> $signed(num2);
            `OP_OR:   result = num1 | num2;
            `OP_AND:  result = num1 & num2;
            default:  result = 0;
        endcase

endmodule

module alu_muldiv (
    input wire clk,
    input wire rst,
    input wire [2:0] op,
    input wire input_valid,
    input wire [31:0] num1,
    input wire [31:0] num2,

    output reg [31:0] result,
    output reg busy
);

    `define OP_MUL 3'b000
    `define OP_MULH 3'b001
    `define OP_MULHSU 3'b010
    `define OP_MULHU 3'b011
    `define OP_DIV 3'b100
    `define OP_DIVU 3'b101
    `define OP_REM 3'b110
    `define OP_REMU 3'b111

    `define STATE_IDLE 0
    `define STATE_MUL_CLK1 1
    `define STATE_MUL_CLK2 2
    `define STATE_MUL_CLK3 3
    `define STATE_MUL_CLK4 4
    `define STATE_MUL_FINISH 5
    `define STATE_DIV_WAIT 6

    // ===== MODULES =====

    wire [31:0] mul_num1, mul_num2;
    wire [63:0] mul_result;

    mult_dsp mul_module (
        .CLK(clk),
        .A  (mul_num1),
        .B  (mul_num2),
        .P  (mul_result)
    );


    wire [31:0] div_dividend, div_divisor;
    wire [31:0] div_quotient, div_remainder;

    wire div_done;
    wire div_tx_valid;

    base4_divider div_module (
        .clk         (clk),
        .rst         (rst),
        .dividend    (div_dividend),
        .divisor     (div_divisor),
        .input_valid (div_tx_valid),
        .quotient    (div_quotient),
        .remainder   (div_remainder),
        .output_valid(div_done)
    );


    // ===== DATA PRE-PROCESSING =====

    // Operand sign
    wire num1_sign = num1[31], num2_sign = num2[31];

    // Operand sign detection on/off
    reg num1_signed, num2_signed;

    // Should we flip the sign of result?
    wire result_sign_flip = (num1_sign && num1_signed) ^ (num2_sign && num2_signed);

    // Division by zero flag
    wire divide_by_zero = num2 == 0;

    // Effective values that are passed to computation modules
    wire [31:0] abs_num1 = num1_sign && num1_signed ? -num1 : num1, abs_num2 = num2_sign && num2_signed ? -num2 : num2;

    assign mul_num1     = abs_num1;
    assign mul_num2     = abs_num2;
    assign div_dividend = abs_num1;
    assign div_divisor  = abs_num2;

    always @(*) begin
        case (op)

            `OP_MUL, `OP_MULH, `OP_DIV, `OP_REM: begin
                num1_signed = 1;
                num2_signed = 1;
            end

            `OP_MULHSU: begin
                num1_signed = 1;
                num2_signed = 0;
            end

            `OP_MULHU, `OP_DIVU, `OP_REMU: begin
                num1_signed = 0;
                num2_signed = 0;
            end

        endcase
    end


    // ===== STATE MACHINE =====

    reg [2:0] state;

    wire op_is_division = op[2] == 1;
    assign div_tx_valid = input_valid && state != `STATE_DIV_WAIT && op_is_division;

    always @(posedge clk)
        if (rst) state <= `STATE_IDLE;
        else
            case (state)
                `STATE_IDLE: if (input_valid) state <= op_is_division ? `STATE_DIV_WAIT : `STATE_MUL_CLK1;

                `STATE_MUL_CLK1:   state <= `STATE_MUL_CLK2;
                `STATE_MUL_CLK2:   state <= `STATE_MUL_CLK3;
                `STATE_MUL_CLK3:   state <= `STATE_MUL_FINISH;
                `STATE_MUL_FINISH: state <= `STATE_IDLE;

                `STATE_DIV_WAIT: if (div_done) state <= `STATE_IDLE;

                default: state <= `STATE_IDLE;
            endcase

    always @(*)
        case (state)
            `STATE_IDLE: busy = input_valid;
            `STATE_MUL_CLK1, `STATE_MUL_CLK2, `STATE_MUL_CLK3, `STATE_MUL_CLK4: busy = 1;
            `STATE_MUL_FINISH: busy = 0;
            `STATE_DIV_WAIT: busy = !div_done;
            default: busy = 0;
        endcase

    // ===== POST-PROCESSING =====

    reg [31:0] div_result_quotient, div_result_remainder;

    always @(*)
        case ({
            divide_by_zero, result_sign_flip
        })
            2'b00: begin
                div_result_quotient  = div_quotient;
                div_result_remainder = div_remainder;
            end
            2'b01: begin
                div_result_quotient  = -div_quotient;
                div_result_remainder = -div_remainder;
            end
            2'b10, 2'b11: begin
                div_result_quotient  = 32'hFFFFFFFF;
                div_result_remainder = num1;
            end
        endcase

    wire [63:0] mul_result_signed = result_sign_flip ? -mul_result : mul_result;

    always @(*)
        case (op)
            `OP_MUL: result = mul_result_signed[31:0];

            `OP_MULH, `OP_MULHU, `OP_MULHSU: result = mul_result_signed[63:32];

            `OP_DIV, `OP_DIVU: result = div_result_quotient;

            `OP_REM, `OP_REMU: result = div_result_remainder;
        endcase

endmodule

module alu_zicond (
    input wire [31:0] num1,
    input wire [31:0] num2,
    input wire [ 2:0] op,

    output reg [31:0] result
);

    `define OP_CZERO_EQZ 3'b101
    `define OP_CZERO_NEZ 3'b111

    wire num2_eqz = num2 == 0;

    always @(*)
        case (op)
            `OP_CZERO_EQZ: result = num2_eqz ? 0 : num1;
            `OP_CZERO_NEZ: result = num2_eqz ? num1 : 0;
            default: result = 0;
        endcase

endmodule

module alu (
    input wire clk_i,
    input wire rst_i,
    input wire `ALU_OP_SIGWIDTH alu_op_i,
    input wire `ALU_SECTION_SIGWIDTH alu_section_i,
    input wire [31:0] alu_num1_i,
    input wire [31:0] alu_num2_i,
    output reg [31:0] alu_result_o,
    output wire [31:0] alu_add_result_o,
    input wire alu_valid_i,
    output wire alu_busy_o
);
    /* PARAMETERS */

    `define ALU_SECTION_INTEGER 2'b00
    `define ALU_SECTION_MULDIV 2'b01
    `define ALU_SECTION_ZICOND 2'b10

    wire [31:0] integer_result, muldiv_result, zicond_result;
    wire muldiv_busy;

    alu_integer integer_module (
        .op    (alu_op_i),
        .num1  (alu_num1_i),
        .num2  (alu_num2_i),
        .result(integer_result),
        .add   (alu_add_result_o)
    );

    alu_muldiv muldiv_module (
        .clk        (clk_i),
        .rst        (rst_i),
        .op         (alu_op_i[2:0]),
        .input_valid(alu_valid_i && alu_section_i == `ALU_SECTION_MULDIV),
        .num1       (alu_num1_i),
        .num2       (alu_num2_i),
        .result     (muldiv_result),
        .busy       (muldiv_busy)
    );

    alu_zicond zicond_module (
        .num1  (alu_num1_i),
        .num2  (alu_num2_i),
        .op    (alu_op_i[2:0]),
        .result(zicond_result)
    );

    assign alu_busy_o = muldiv_busy;

    always @(*)
        case (alu_section_i)
            `ALU_SECTION_INTEGER: alu_result_o = integer_result;
            `ALU_SECTION_MULDIV: alu_result_o = muldiv_result;
            `ALU_SECTION_ZICOND: alu_result_o = zicond_result;
            default: alu_result_o = 0;
        endcase

endmodule
