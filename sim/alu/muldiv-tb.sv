`timescale 1ns / 1ps

module tb_alu;

    integer fd;
    reg clk, rst, input_valid;
    reg [2:0] op;
    reg [31:0] num1, num2;

    wire [31:0] result;
    wire busy;

    alu_muldiv u_alu_muldiv (
        .clk        (clk),
        .rst        (rst),
        .op         (op),
        .input_valid(input_valid),
        .num1       (num1),
        .num2       (num2),
        .result     (result),
        .busy       (busy)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    // Reset logic
    initial begin
        #10;
        rst = 1;
        #20 rst = 0;  // Assert reset for 20ns
    end

    reg [2:0] file_op;
    reg [31:0] file_num1, file_num2, file_expected;

    task test_alu;
        begin
            @(posedge clk);
            #1;

            input_valid = 1;
            op          = file_op;
            num1        = file_num1;
            num2        = file_num2;

            @(posedge clk);
            #1;
            input_valid = 0;

            // Wait for computation to complete
            wait (busy == 0);
            #2;

            // Calculate correct result
            if (result != file_expected) begin
                $display("Error: op=%d num1=%d num2=%d result=%d expected=%d", file_op, file_num1,
                         file_num2, result, file_expected);
                #50;
                $stop;
            end
        end
    endtask

    initial begin
        fd = $fopen("/mnt/Dev/Dev/riscv/simulator/cpp-riscv-sim/emulator_dump.txt", "r");
        #100;

        while (!$feof(
            fd
        )) begin
            $fscanf(fd, "%d,%d,%d,%d", file_op, file_num1, file_num2, file_expected);
            test_alu();
        end

        $finish;
    end


endmodule
