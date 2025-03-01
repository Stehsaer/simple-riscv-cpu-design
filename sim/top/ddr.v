`timescale 1ns/1ps

module tb_cpu_ddr;

    // Declare signals
    reg clk_i;
    reg rst_i;

    wire rx_i;
    wire tx_o;

    wire [14:0] ddr3_addr;
    wire [2:0] ddr3_ba;
    wire ddr3_cas_n;
    wire ddr3_ck_p;
    wire ddr3_ck_n;
    wire ddr3_cke;
    wire ddr3_cs_n;
    wire [7:0] ddr3_dm;
    wire [63:0] ddr3_dq;
    wire [7:0] ddr3_dqs_p;
    wire [7:0] ddr3_dqs_n;
    wire ddr3_odt;
    wire ddr3_ras_n;
    wire ddr3_reset_n;
    wire ddr3_we_n;

    ddr_design_wrapper top (
        .clk_pair_clk_p(clk_i),
        .clk_pair_clk_n(~clk_i),
        .rst(rst_i),
        .tx(tx_o),
        .rx(rx_i),
        .DDR3_0_addr(ddr3_addr),
        .DDR3_0_ba(ddr3_ba),
        .DDR3_0_cas_n(ddr3_cas_n),
        .DDR3_0_ck_n(ddr3_ck_n),
        .DDR3_0_ck_p(ddr3_ck_p),
        .DDR3_0_cke(ddr3_cke),
        .DDR3_0_cs_n(ddr3_cs_n),
        .DDR3_0_dm(ddr3_dm),
        .DDR3_0_dq(ddr3_dq),
        .DDR3_0_dqs_n(ddr3_dqs_n),
        .DDR3_0_dqs_p(ddr3_dqs_p),
        .DDR3_0_odt(ddr3_odt),
        .DDR3_0_ras_n(ddr3_ras_n),
        .DDR3_0_reset_n(ddr3_reset_n),
        .DDR3_0_we_n(ddr3_we_n)
    );

    ddr3_model u_ddr3_model_0 (
        .rst_n  (ddr3_reset_n),
        .ck     (ddr3_ck_p),
        .ck_n   (ddr3_ck_n),
        .cke    (ddr3_cke),
        .cs_n   (ddr3_cs_n),
        .ras_n  (ddr3_ras_n),
        .cas_n  (ddr3_cas_n),
        .we_n   (ddr3_we_n),
        .dm_tdqs(ddr3_dm[1:0]),
        .ba     (ddr3_ba),
        .addr   (ddr3_addr),
        .dq     (ddr3_dq[15:0]),
        .dqs    (ddr3_dqs_p[1:0]),
        .dqs_n  (ddr3_dqs_n[1:0]),
        .tdqs_n (),
        .odt    (ddr3_odt)
    );

    ddr3_model u_ddr3_model_1 (
        .rst_n  (ddr3_reset_n),
        .ck     (ddr3_ck_p),
        .ck_n   (ddr3_ck_n),
        .cke    (ddr3_cke),
        .cs_n   (ddr3_cs_n),
        .ras_n  (ddr3_ras_n),
        .cas_n  (ddr3_cas_n),
        .we_n   (ddr3_we_n),
        .dm_tdqs(ddr3_dm[3:2]),
        .ba     (ddr3_ba),
        .addr   (ddr3_addr),
        .dq     (ddr3_dq[31:16]),
        .dqs    (ddr3_dqs_p[3:2]),
        .dqs_n  (ddr3_dqs_n[3:2]),
        .tdqs_n (),
        .odt    (ddr3_odt)
    );

    ddr3_model u_ddr3_model_2 (
        .rst_n  (ddr3_reset_n),
        .ck     (ddr3_ck_p),
        .ck_n   (ddr3_ck_n),
        .cke    (ddr3_cke),
        .cs_n   (ddr3_cs_n),
        .ras_n  (ddr3_ras_n),
        .cas_n  (ddr3_cas_n),
        .we_n   (ddr3_we_n),
        .dm_tdqs(ddr3_dm[5:4]),
        .ba     (ddr3_ba),
        .addr   (ddr3_addr),
        .dq     (ddr3_dq[47:32]),
        .dqs    (ddr3_dqs_p[5:4]),
        .dqs_n  (ddr3_dqs_n[5:4]),
        .tdqs_n (),
        .odt    (ddr3_odt)
    );

    ddr3_model u_ddr3_model_3 (
        .rst_n  (ddr3_reset_n),
        .ck     (ddr3_ck_p),
        .ck_n   (ddr3_ck_n),
        .cke    (ddr3_cke),
        .cs_n   (ddr3_cs_n),
        .ras_n  (ddr3_ras_n),
        .cas_n  (ddr3_cas_n),
        .we_n   (ddr3_we_n),
        .dm_tdqs(ddr3_dm[7:6]),
        .ba     (ddr3_ba),
        .addr   (ddr3_addr),
        .dq     (ddr3_dq[63:48]),
        .dqs    (ddr3_dqs_p[7:6]),
        .dqs_n  (ddr3_dqs_n[7:6]),
        .tdqs_n (),
        .odt    (ddr3_odt)
    );

    // Generate a 100MHz clock signal
    initial begin
        clk_i = 1;
        forever #5 clk_i = ~clk_i;
    end

    integer fd;

    always @(posedge top.ddr_design_i.cpu.inst.clk_i) begin
        if (top.ddr_design_i.cpu.inst.reg_file_wen && top.ddr_design_i.cpu.inst.reg_file_waddr != 0 ) begin
            $fdisplay(fd, "%h, Reg, x%02d, %h",
                      top.ddr_design_i.cpu.inst.mem1_mem2_pc4 - 4,
                      top.ddr_design_i.cpu.inst.reg_file_waddr,
                      top.ddr_design_i.cpu.inst.reg_file_wdata);
        end

        if(top.ddr_design_i.uart_module.inst.tx_fifo.wr_en) begin
            $display("Tx <- \'%c\'", top.ddr_design_i.uart_module.inst.tx_fifo.din);
        end
    end

    reg uart_rx;
    assign rx_i = uart_rx;

    localparam parity = 3'b001;  // Odd
    localparam stopbits = 1'b0;  // 1 stop bit

    localparam divisor = 8680;  // 115200 baud rate

    localparam STRLEN = 94;

    reg [7:0] string[0:STRLEN-1] = ":0200000480106A\r\n:1000000037C50100130525F51300000067800000C7\r\n:040000058010000067\r\n:00000001FF\r\n";
    integer i;


    // Test sequence
    initial begin
        $display("Simulation starts.");

        // Initialize inputs
        rst_i   = 1;
        uart_rx = 1;

        // Open file
        fd      = $fopen("log.txt", "w");

        // Apply reset
        #1 rst_i = 0;
        #2000 rst_i = 1;

        #90000;  // Wait for 500us for UART to be ready
        // $display("Start sending data to UART");
        // // Send "15 21\n" to UART
        
        for(i = 0; i < STRLEN; i = i + 1) begin
            $display("Sending (%d)-th letter \'%c\'", i, string[i]);
            // uart_tx_task(string[i], parity, stopbits, divisor);
            uart_tx_force_task(string[i]);
        end
    end

    task uart_tx_task;
        input [7:0] data;  // 8位数据
        input [2:0] parity;  // 3位校验位设置
        input stopbits;  // 1位停止位设置
        input [23:0] divisor;  // 24位分频器，控制每一位的持续时间
        reg [10:0] tx_frame;       
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

    task uart_tx_force_task;
        input [7:0] data; 

        begin
            wait (top.ddr_design_i.cpu.core_module.clk_i == 0);
            wait (top.ddr_design_i.cpu.core_module.clk_i == 1);
            #1;

            force top.ddr_design_i.uart_module.inst.rx_fifo.wr_en = 1;
            force top.ddr_design_i.uart_module.inst.rx_fifo.din = data;

            wait (top.ddr_design_i.cpu.core_module.clk_i == 0);
            wait (top.ddr_design_i.cpu.core_module.clk_i == 1);
            #1;

            release top.ddr_design_i.uart_module.inst.rx_fifo.wr_en;
            release top.ddr_design_i.uart_module.inst.rx_fifo.din;
        end
    endtask

endmodule