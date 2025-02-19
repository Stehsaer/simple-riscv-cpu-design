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
        #(divisor * 10);  // 等待一个位时间

        // 数据位
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx = data[i];  // 发送数据位
            #(divisor * 10);  // 等待一个位时间
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
            #(divisor * 10);  // 等待一个位时间
        end

        // 停止位
        uart_rx = 1'b1;  // UART停止位为1
        #(divisor * 10);  // 等待一个位时间
        if (stopbits) begin
            uart_rx = 1'b1;  // 如果有2位停止位，再发送一个停止位
            #(divisor * 10);  // 等待一个位时间
        end
    end
endtask
