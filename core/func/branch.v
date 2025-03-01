// 分支模块

module branch (
    input  wire [ 4:0] cmp_op_i,
    input  wire [31:0] cmp_num1_i,
    input  wire [31:0] cmp_num2_i,
    output wire        do_branch_o
);

    wire [1:0] op = cmp_op_i[4:3];
    wire [2:0] func = cmp_op_i[2:0];

    wire signed [31:0] cmp_num1_signed = cmp_num1_i;
    wire signed [31:0] cmp_num2_signed = cmp_num2_i;

    reg do_branch;
    assign do_branch_o = do_branch;

    // new

    reg  branch_simple;

    (* use_dsp="yes" *)wire equal = (cmp_num1_i == cmp_num2_i);
    (* use_dsp="yes" *)wire signed_less = ($signed(cmp_num1_i) < $signed(cmp_num2_i));
    (* use_dsp="yes" *)wire unsigned_less = (cmp_num1_i < cmp_num2_i);

    always @(*)
        case (func[2:1])
            2'b00:   branch_simple = equal;
            2'b10:   branch_simple = signed_less;
            2'b11:   branch_simple = unsigned_less;
            default: branch_simple = 0;
        endcase

    always @(*) begin
        case (op)
            2'b00:   do_branch = 0;
            2'b01:   do_branch = branch_simple ^ func[0];
            2'b10:   do_branch = 1;
            default: do_branch = 0;
        endcase
    end
endmodule
