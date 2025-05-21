module Count_population_4bits (
    input  wire [3:0] data,
    output reg  [1:0] population
);

    (* parallel_case *) always @(*)
        case (data)
            4'b0000: population = 2'b00;
            4'b0001: population = 2'b01;
            4'b0010: population = 2'b01;
            4'b0011: population = 2'b10;
            4'b0100: population = 2'b01;
            4'b0101: population = 2'b10;
            4'b0110: population = 2'b10;
            4'b0111: population = 2'b11;
            4'b1000: population = 2'b01;
            4'b1001: population = 2'b10;
            4'b1010: population = 2'b10;
            4'b1011: population = 2'b11;
            4'b1100: population = 2'b10;
            4'b1101: population = 2'b11;
            4'b1110: population = 2'b11;
            4'b1111: population = 2'b11;
        endcase

endmodule

module find_min (
    input  wire [1:0] i0,
    input  wire [1:0] i1,
    input  wire [1:0] i2,
    input  wire [1:0] i3,
    output wire [1:0] o
);

    wire [1:0] grp0_val, grp0_idx;
    wire [1:0] grp1_val, grp1_idx;

    assign {grp0_val, grp0_idx} = (i0 <= i1) ? {i0, 2'd0} : {i1, 2'd1};
    assign {grp1_val, grp1_idx} = (i2 <= i3) ? {i2, 2'd2} : {i3, 2'd3};

    assign o                    = (grp0_val <= grp1_val) ? grp0_idx : grp1_idx;

endmodule


module Lru_find_set (
    input  wire [15:0] lru_matrix,
    output wire [ 1:0] set
);

    wire [1:0] population0, population1, population2, population3;

    Count_population_4bits count0 (
        .data(lru_matrix[3:0]),
        .population(population0)
    );

    Count_population_4bits count1 (
        .data(lru_matrix[7:4]),
        .population(population1)
    );

    Count_population_4bits count2 (
        .data(lru_matrix[11:8]),
        .population(population2)
    );

    Count_population_4bits count3 (
        .data(lru_matrix[15:12]),
        .population(population3)
    );

    find_min find (
        .i0(population0),
        .i1(population1),
        .i2(population2),
        .i3(population3),
        .o (set)
    );

endmodule

module Lru_update (
    input  wire [15:0] original,
    input  wire [ 1:0] set,
    output reg  [15:0] updated
);

    wire [15:0] updated0 = original & 16'b1110_1110_1110_1110 | 16'b0000_0000_0000_1110; // LRU Matrix when set 0 is accessed
    wire [15:0] updated1 = original & 16'b1101_1101_1101_1101 | 16'b0000_0000_1101_0000; // LRU Matrix when set 1 is accessed
    wire [15:0] updated2 = original & 16'b1011_1011_1011_1011 | 16'b0000_1011_0000_0000; // LRU Matrix when set 2 is accessed
    wire [15:0] updated3 = original & 16'b0111_0111_0111_0111 | 16'b0111_0000_0000_0000; // LRU Matrix when set 3 is accessed

    always @(*)
        case (set)
            2'b00: updated = updated0;
            2'b01: updated = updated1;
            2'b10: updated = updated2;
            2'b11: updated = updated3;
        endcase

endmodule

module Replace_bit(
    input wire [3:0] i,
    input wire [1:0] bit,
    input wire replace,
    output reg [3:0] o
);

    always @(*) 
        case (bit)
            2'b00: o = {i[3:1], replace};
            2'b01: o = {i[3:2], replace, i[0]};
            2'b10: o = {i[3], replace, i[1:0]};
            2'b11: o = {replace, i[2:0]};
        endcase

endmodule
