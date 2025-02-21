`timescale 1ns / 1ps

module tb_noddr;

    // Declare signals
    reg  clk_i;
    reg  rst_i;

    wire rx_i;
    wire tx_o;

    sim_bench top (
        .clk(clk_i),
        .rst(rst_i),
        .tx(tx_o),
        .rx(rx_i)
    );

    // Generate a 100MHz clock signal
    initial begin
        clk_i = 1;
        forever #(3.571) clk_i = ~clk_i;
    end

    integer fd;

    always @(posedge top.cpu.core_module.inst.u_cpu_core.clk_i) begin
        if (top.cpu.core_module.inst.u_cpu_core.reg_file_wen && top.cpu.core_module.inst.u_cpu_core.reg_file_waddr != 0 ) begin
            $fdisplay(fd, "%08h, Reg, x%02d, %h",
                      top.cpu.core_module.inst.u_cpu_core.mem1_mem2_pc4 - 4,
                      top.cpu.core_module.inst.u_cpu_core.reg_file_waddr,
                      top.cpu.core_module.inst.u_cpu_core.reg_file_wdata);
        end

        // if (top.cpu.core_module.inst.u_cpu_core.ex_mem1_accept_ready && top.cpu.core_module.inst.u_cpu_core.ex_product_ready) begin
        //     $fdisplay(fd, "%08h, %08h",
        //               top.cpu.core_module.inst.u_cpu_core.id_ex_pc,
        //               top.cpu.core_module.inst.u_cpu_core.id_ex_inst
        //               );
        // end

        if(top.uart_axi_0.inst.tx_fifo.wr_en) begin
            $write("%c", top.uart_axi_0.inst.tx_fifo.din);
        end
    end

    reg uart_rx;
    assign rx_i = uart_rx;

    localparam parity = 3'b001;  // Odd
    localparam stopbits = 1'b0;  // 1 stop bit
    // 100MHz / 115200 = 868.0555555555556
    localparam divisor = 1000;  // 115200 baud rate

    localparam STRLEN = 1148;

    reg [7:0] string[0:STRLEN - 1] = ":0200000480106A\n:10000000130101FF232411001702000013028218BC\n:1000100017050000130505189305000013060000DE\n:10002000EF004009170500001305C51693050000F1\n:1000300013060000EF00000897020000938282156B\n:100040001703000013030315638E620083A30200ED\n:1000500023225100E7800300832241009382420063\n:100060006FF01FFE1305000093050000EF00C003B2\n:1000700097020000938202121703000013038311FA\n:10008000638E620083A3020023225100E7800300F5\n:1000900083224100938242006FF01FFE8320810083\n:1000A000130101016780000037C50100130525F524\n:1000B000678000001303F00013070500637EC3028E\n:1000C0009377F7006390070A63920508937606FF1B\n:1000D0001376F600B386E6002320B7002322B7008C\n:1000E0002324B7002326B70013070701E366D7FED2\n:1000F0006314060067800000B306C3409396260091\n:1001000097020000B38656006780C6002307B70039\n:10011000A306B7002306B700A305B7002305B70061\n:10012000A304B7002304B700A303B7002303B70059\n:10013000A302B7002302B700A301B7002301B70051\n:10014000A300B7002300B7006780000093F5F50F08\n:1001500093968500B3E5D50093960501B3E5D500E8\n:100160006FF0DFF69396270097020000B3865600E3\n:1001700093820000E78006FA93800200938707FFCE\n:100180003307F7403306F600E378C3F66FF0DFF38A\n:040000058010000067\n:00000001FF\n";
    integer i;


    // Test sequence
    initial begin
        $display("Simulation starts.");

        // Initialize inputs
        rst_i   = 1;
        uart_rx = 1;

        // Apply reset
        #1 rst_i = 0;
        #13 rst_i = 1;

        #100000;  // Wait for 500us for UART to be ready
        $display("Start sending data to UART");
        
        for(i = 0; i < STRLEN; i = i + 1) begin
            $display("Sending (%d)-th letter \'%c\'", i, string[i]);
            uart_tx_task(string[i], parity, stopbits, divisor);
        end
    end

    initial begin
        fd = $fopen("log.txt", "w");
        // #100000;
        // $fclose(fd);
    end

    task uart_tx_task;
        input [7:0] data;  // 8位数据
        input [2:0] parity;  // 3位校验位设置
        input stopbits;  // 1位停止位设置
        input [23:0] divisor;  // 24位分频器，控制每一位的持续时间
        reg [10:0] tx_frame;       // 11位帧：1起始位 + 8数据位 + 1校验位 + 1停止位（或2停止位）
        reg parity_bit;  // 校验位
        integer i;
        begin
            // 起始位
            uart_rx = 1'b0;  // UART起始位为0
            #(divisor);  // 等待一个位时间

            // 数据位
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];  // 发送数据位
                #(divisor);  // 等待一个位时间
            end

            // 计算校验位
            case (parity)
                3'b000:  parity_bit = 1'b0;  // 无校验位
                3'b001:  parity_bit = ~(^data);  // 奇校验：确保1的总数为奇数
                3'b010:  parity_bit = ^data;  // 偶校验：确保1的总数为偶数
                3'b100:  parity_bit = 1'b0;  // 零校验：固定为0
                3'b101:  parity_bit = 1'b1;  // 一校验：固定为1
                default: parity_bit = 1'b0;  // 默认无校验
            endcase

            // 发送校验位（如果有）
            if (parity != 3'b000) begin
                uart_rx = parity_bit;
                #(divisor);  // 等待一个位时间
            end

            // 停止位
            uart_rx = 1'b1;  // UART停止位为1
            #(divisor);  // 等待一个位时间
            if (stopbits) begin
                uart_rx = 1'b1;  // 如果有2位停止位，再发送一个停止位
                #(divisor);  // 等待一个位时间
            end
        end
    endtask



endmodule
