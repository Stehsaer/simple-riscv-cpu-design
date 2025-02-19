`timescale 1ns / 1ps

module axi4_lite_tb;

    // 时钟和复位信号
    reg         aclk;
    reg         aresetn;

    // 写地址通道
    reg  [31:0] axi_awaddr;
    reg         axi_awvalid;
    wire        axi_awready;
    reg  [ 2:0] axi_awprot;  // AxPROT 信号，固定为 0

    // 写数据通道
    reg  [31:0] axi_wdata;
    reg  [ 3:0] axi_wstrb;
    reg         axi_wvalid;
    wire        axi_wready;

    // 写响应通道
    wire [ 1:0] axi_bresp;
    wire        axi_bvalid;
    reg         axi_bready;

    // 读地址通道
    reg  [31:0] axi_araddr;
    reg         axi_arvalid;
    wire        axi_arready;
    reg  [ 2:0] axi_arprot;  // AxPROT 信号，固定为 0

    // 读数据通道
    wire [31:0] axi_rdata;
    wire [ 1:0] axi_rresp;
    wire        axi_rvalid;
    reg         axi_rready;

    // 实例化 AXI4-Lite 从机
    axi4_lite_slave uut (
        .aclk(aclk),
        .aresetn(aresetn),
        .axi_awaddr(axi_awaddr),
        .axi_awvalid(axi_awvalid),
        .axi_awready(axi_awready),
        .axi_awprot(axi_awprot),
        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready),
        .axi_bresp(axi_bresp),
        .axi_bvalid(axi_bvalid),
        .axi_bready(axi_bready),
        .axi_araddr(axi_araddr),
        .axi_arvalid(axi_arvalid),
        .axi_arready(axi_arready),
        .axi_arprot(axi_arprot),
        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready)
    );

    // 时钟生成
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;  // 100MHz 时钟
    end

    // 复位信号
    initial begin
        aresetn = 0;
        #20 aresetn = 1;
    end

    // 初始化 AxPROT 信号
    initial begin
        axi_awprot = 3'b000;  // 固定为 0
        axi_arprot = 3'b000;  // 固定为 0
    end

    // 测试任务
    initial begin
        // 等待复位完成
        #30;

        // 写入数据到地址 0x1000
        axi_write(32'h1000, 32'h12345678);

        // 从地址 0x1000 读取数据
        axi_read(32'h1000);

        // 结束仿真
        #100;
        $finish;
    end

    // AXI4-Lite 写操作任务
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // 写地址通道
            axi_awaddr  = addr;
            axi_awvalid = 1;
            while (!axi_awready) #10;

            // 写数据通道
            axi_wdata  = data;
            axi_wstrb  = 4'b1111;  // 写入所有字节
            axi_wvalid = 1;
            while (!axi_wready) #10;

            // 完成写操作
            axi_awvalid = 0;
            axi_wvalid  = 0;

            // 等待写响应
            axi_bready  = 1;
            while (!axi_bvalid) #10;
            axi_bready = 0;
        end
    endtask

    // AXI4-Lite 读操作任务
    task axi_read;
        input [31:0] addr;
        begin
            // 读地址通道
            axi_araddr  = addr;
            axi_arvalid = 1;
            while (!axi_arready) #10;

            // 完成读地址操作
            axi_arvalid = 0;

            // 等待读数据
            axi_rready  = 1;
            while (!axi_rvalid) #10;
            $display("Read Data: 0x%h", axi_rdata);
            axi_rready = 0;
        end
    endtask

endmodule
