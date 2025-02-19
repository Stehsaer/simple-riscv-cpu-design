task axi_write;
    input [31:0] addr;
    input [31:0] data;
    begin
        // 写地址通道
        axi_awaddr  = addr;
        axi_awvalid = 1;
        #9;
        while (!axi_awready) #10;
        #1;

        // 写数据通道
        axi_wdata   = data;
        axi_wstrb   = 4'b1111;  // 写入所有字节
        axi_wvalid  = 1;
        axi_awvalid = 0;

        #9;
        while (!axi_wready) #10;
        #1;

        // 完成写操作
        axi_wvalid = 0;

        // 等待写响应
        axi_bready = 1;
        #9;
        while (!axi_bvalid) #10;
        #1;
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
        #9;
        while (!axi_arready) #10;
        #1;

        // 完成读地址操作
        axi_arvalid = 0;

        // 等待读数据
        axi_rready  = 1;
        #9;
        while (!axi_rvalid) #10;
        #1;

        $display("Read from 0x%h gets: 0x%h", addr, axi_rdata);
        axi_rready = 0;
    end
endtask
