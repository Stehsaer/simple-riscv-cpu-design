module priority_encoder_4bits (
    input wire [3:0] data,

    output reg [1:0] result,
    output wire zero
);

    assign zero = (data == 4'b0000);

    always @(*)
        case (data)
            0, 1: result = 2'b00;
            2, 3: result = 2'b01;
            4, 5, 6, 7: result = 2'b10;
            default: result = 2'b11;
        endcase

endmodule

module priority_encoder_16bits (
    input wire [15:0] data,

    output wire [3:0] result,
    output wire zero
);

    wire [3:0] reduction = {(|data[15:12]), (|data[11:8]), (|data[7:4]), (|data[3:0])};

    wire [1:0] level1_result;
    wire level1_zero;

    priority_encoder_4bits level1 (
        .data  (reduction),
        .result(level1_result),
        .zero  (level1_zero)
    );

    wire [1:0] level2_result[3:0];
    wire [3:0] level2_zero;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin
            priority_encoder_4bits level2 (
                .data  (data[4*i+:4]),
                .result(level2_result[i]),
                .zero  (level2_zero[i])
            );
        end
    endgenerate

    wire [1:0] level2_result_summary = level2_result[level1_result];
    wire level2_zero_summary = level2_zero[level1_result];

    assign result = {level1_result, level2_result_summary};
    assign zero   = level2_zero_summary;

endmodule

module base4_divider (
    input wire clk,
    input wire rst,

    input wire [31:0] dividend,
    input wire [31:0] divisor,
    input wire input_valid,

    output wire [31:0] quotient,
    output wire [31:0] remainder,
    output wire output_valid
);

    localparam STATE_IDLE = 0;
    localparam STATE_PREPROCESS = 1;
    localparam STATE_SHIFT = 2;
    localparam STATE_DIVIDE = 3;
    localparam STATE_CACHED = 4;

    reg [4:0] cycle_counter;
    reg [2:0] state;

    reg [31:0] dividend_reg, divisor_reg;
    reg [15:0] interleaved_dividend_reg;

    reg [33:0] divisor_1, divisor_2, divisor_3;
    reg [65:0] dividend_shift;
    reg [31:0] quotient_shift;

    reg [31:0] last_dividend, last_divisor, last_quotient, last_remainder;  // Cache for output

    // ===== ALGORITHM =====

    wire [15:0] interleaved_dividend_result = {
        dividend[31] | dividend[30],
        dividend[29] | dividend[28],
        dividend[27] | dividend[26],
        dividend[25] | dividend[24],
        dividend[23] | dividend[22],
        dividend[21] | dividend[20],
        dividend[19] | dividend[18],
        dividend[17] | dividend[16],
        dividend[15] | dividend[14],
        dividend[13] | dividend[12],
        dividend[11] | dividend[10],
        dividend[9] | dividend[8],
        dividend[7] | dividend[6],
        dividend[5] | dividend[4],
        dividend[3] | dividend[2],
        dividend[1] | dividend[0]
    };

    wire [3:0] counter_value;
    wire counter_zero;

    priority_encoder_16bits counter (
        .data  (interleaved_dividend_result),
        .result(counter_value),
        .zero  (counter_zero)
    );

    wire [4:0] counter_init = {!counter_zero, counter_value};
    wire counter_end = !cycle_counter[4];

    wire cache_hit = last_dividend == dividend_reg && last_divisor == divisor_reg;

    // Generate 3 compare values
    wire [33:0] divisor_1_gen = divisor_reg;
    wire [33:0] divisor_2_gen = {divisor_reg, 1'b0};
    wire [33:0] divisor_3_gen = divisor_2_gen + divisor_1_gen;

    // Target dividend
    wire [33:0] dividend_target = dividend_shift[65:32];

    // Compare results
    wire lt1 = dividend_target < divisor_1;  // dividend < 1 * divisor
    wire lt2 = dividend_target < divisor_2;  // dividend < 2 * divisor
    wire lt3 = dividend_target < divisor_3;  // dividend < 3 * divisor

    reg [1:0] gen_res;

    always @(*)
        case ({
            lt1, lt2, lt3
        })
            3'b111, 3'b110, 3'b101, 3'b100: gen_res = 0;  // 0 * divisor <= dividend < 1 * divisor
            3'b011, 3'b010: gen_res = 1;  // 1 * divisor <= dividend < 2 * divisor
            3'b001: gen_res = 2;  // 2 * divisor <= dividend < 3 * divisor
            3'b000: gen_res = 3;  // 3 * divisor <= dividend
        endcase

    // Select the number to substract
    reg [33:0] sel_sub;

    always @(*)
        case (gen_res)
            0: sel_sub = 0;  // dividend = dividend - 0 * divisor
            1: sel_sub = divisor_1_gen;  // dividend = dividend - 1 * divisor
            2: sel_sub = divisor_2_gen;  // dividend = dividend - 2 * divisor
            3: sel_sub = divisor_3_gen;  // dividend = dividend - 3 * divisor
        endcase

    wire [33:0] dividend_sub = dividend_target - sel_sub;

    // ===== STATE MACHINE =====

    always @(posedge clk)
        if (rst) begin
            cycle_counter            <= 0;
            state                    <= STATE_IDLE;
            dividend_reg             <= 0;
            divisor_reg              <= 0;
            interleaved_dividend_reg <= 0;
            divisor_1                <= 0;
            divisor_2                <= 0;
            divisor_3                <= 0;
            dividend_shift           <= 0;
            quotient_shift           <= 0;
            last_dividend            <= 0;
            last_divisor             <= 0;
            last_quotient            <= 0;
            last_remainder           <= 0;
        end else
            case (state)
                STATE_IDLE: begin
                    if (input_valid) begin
                        state                    <= STATE_PREPROCESS;
                        dividend_reg             <= dividend;
                        divisor_reg              <= divisor;
                        interleaved_dividend_reg <= interleaved_dividend_result;
                    end
                end

                STATE_PREPROCESS: begin
                    if (cache_hit) state <= STATE_CACHED;
                    else state <= STATE_SHIFT;

                    // Init
                    quotient_shift <= 0;

                    // Precalculate
                    dividend_shift <= {34'b0, dividend_reg};
                    divisor_1      <= divisor_1_gen;
                    divisor_2      <= divisor_2_gen;
                    divisor_3      <= divisor_3_gen;
                    cycle_counter  <= counter_init;
                end

                STATE_SHIFT: begin
                    state <= STATE_DIVIDE;
                    dividend_shift <= dividend_shift << {16 - cycle_counter[3:0], 1'b0};  // Pre-shifting, reduce calculation time for small dividend
                end

                STATE_DIVIDE: begin
                    if (counter_end) begin
                        state          <= STATE_IDLE;
                        last_dividend  <= dividend_reg;
                        last_divisor   <= divisor_reg;
                        last_quotient  <= quotient;
                        last_remainder <= remainder;
                    end else begin
                        cycle_counter  <= cycle_counter - 1;
                        quotient_shift <= {quotient_shift[29:0], gen_res};
                    end

                    if (cycle_counter != 5'b10000)
                        dividend_shift <= {dividend_sub[31:0], dividend_shift[31:0], 2'b00};
                    else dividend_shift <= {2'b00, dividend_sub[31:0], 32'b00};
                end

                STATE_CACHED: state <= STATE_IDLE;

                default: state <= STATE_IDLE;
            endcase

    assign output_valid = state == STATE_DIVIDE && counter_end || state == STATE_CACHED;
    assign quotient     = state == STATE_CACHED ? last_quotient : quotient_shift;
    assign remainder    = state == STATE_CACHED ? last_remainder : dividend_shift[63:32];

endmodule
