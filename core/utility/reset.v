module Reset_utility (
    input wire clk,
    input wire rstn,
    input wire pll_lock_1,
    input wire pll_lock_2,
    input wire ddr_calib_done,

    output wire rst_o
);

    reg [3:0] clock_counter;
    reg rst_keep;

    wire clock_available = pll_lock_1 && pll_lock_2 && ddr_calib_done;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rst_keep <= 1'b1;
        end else if (clock_available) begin
            rst_keep <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst_keep) begin
            clock_counter <= 4'hF;
        end else begin
            if (clock_available && clock_counter != 4'h0) begin
                clock_counter <= clock_counter - 1;
            end
        end
    end

    assign rst_o = (clock_counter == 4'h0);

endmodule
