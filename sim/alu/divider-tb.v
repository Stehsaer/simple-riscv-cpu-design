module tb_divider;

    reg clk, rstn;
    reg [31:0] dividend, divisor;
    reg input_valid;

    wire [31:0] quotient, remainder;
    reg [31:0] correct_quotient, correct_remainder;
    wire output_valid;

    base4_divider u_base4_divider (
        .clk         (clk),
        .rstn        (rstn),
        .dividend    (dividend),
        .divisor     (divisor),
        .input_valid (input_valid),
        .quotient    (quotient),
        .remainder   (remainder),
        .output_valid(output_valid)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end

    // Reset logic
    initial begin
        #10;
        rstn = 0;
        #20 rstn = 1;  // Assert reset for 20ns
    end

    real log_dividend_real, log_divisor_real;

    task test_divider;
        input wire [31:0] dividend_i, divisor_i;
        begin

            @(posedge clk);
            #1;

            // Perform division
            input_valid = 1;
            dividend    = dividend_i;
            divisor     = divisor_i == 0 ? 1 : divisor_i;

            @(posedge clk);
            #1;
            input_valid = 0;

            // Wait for computation to complete
            wait (output_valid);
            #1;

            // Calculate correct result
            correct_quotient  = dividend_i / divisor;
            correct_remainder = dividend_i % divisor;

            // Print results
            if (correct_quotient != quotient || correct_remainder != remainder) begin
                $display("Dividend: %d, Divisor: %d", dividend, divisor);
                $display("Expected: Quotient=%d, Remainder=%d", correct_quotient,
                         correct_remainder);
                $display("Acquired: Quotient=%d, Remainder=%d", quotient, remainder);
                $stop;
            end
        end
    endtask
    
    integer loop;

    // Test logic
    initial begin
        // Wait for reset deassertion
        @(negedge rstn);
        @(posedge rstn);

        // Loop to perform multiple tests
        for (loop = 0; loop < 10000000; loop = loop + 1) begin
            // Randomly generate two 32-bit unsigned numbers
            log_dividend_real = $random / 2147483647.0 * 31.0;
            log_divisor_real  = $random / 2147483647.0 * 31.0;
            test_divider($pow(2, log_dividend_real) - 1, $pow(2, log_divisor_real));

            if(loop % 10000 == 0) begin
                $display("Testing %d", loop);
            end
        end

        // End simulation
        $finish;
    end

endmodule
