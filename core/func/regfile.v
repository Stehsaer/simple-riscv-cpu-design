module reg_file (
    input wire [4:0] raddr1_i,
    input wire [4:0] raddr2_i,
    input wire [4:0] waddr_i,
    input wire [31:0] wdata_i,
    input wire wen_i,
    input wire clk_i,
    input wire rst_i,

    output wire [31:0] rdata1_o,
    output wire [31:0] rdata2_o
);

    reg [31:0] reg_file[1:31];

    integer i;

    always @(posedge clk_i) begin
        if (rst_i)
            for (i = 1; i < 32; i = i + 1) begin
                reg_file[i] <= 32'd0;
            end
        else begin
            if (wen_i && waddr_i != 0) begin
                reg_file[waddr_i] <= wdata_i;
            end
        end
    end

    assign rdata1_o = raddr1_i == 0 ? 32'd0 : reg_file[raddr1_i];
    assign rdata2_o = raddr2_i == 0 ? 32'd0 : reg_file[raddr2_i];

endmodule
