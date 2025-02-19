// RAM 操作模块

// 第一阶段：写入/读取
module memory_stage1 (
    input wire [ 4:0] mem_op_i,
    input wire [31:0] mem_addr_i,
    input wire [31:0] mem_wdata_i,

    output wire [29:0] ram_addr_o,
    output reg [31:0] ram_wdata_o,
    output reg [3:0] ram_wen_o,
    output reg ram_ren_o
);

    parameter MEM_OP_NONE = 2'b00;
    parameter MEM_OP_LD = 2'b01;
    parameter MEM_OP_ST = 2'b10;

    assign ram_addr_o = mem_addr_i >> 2;

    wire [1:0] mem_op = mem_op_i[4:3];
    wire [2:0] func = mem_op_i[2:0];
    wire [1:0] byte_addr = mem_addr_i[1:0];

    always @(*) begin
        case (mem_op)
            MEM_OP_LD: begin
                ram_wen_o   = 4'b0000;
                ram_ren_o   = 1;
                ram_wdata_o = mem_wdata_i;
            end
            MEM_OP_ST: begin
                ram_ren_o = 0;

                case (func)
                    3'b010: begin
                        ram_wen_o   = 4'b1111;  // SW, 写入一个字
                        ram_wdata_o = mem_wdata_i;
                    end
                    3'b001: begin
                        ram_wen_o = byte_addr[1] ? 4'b1100 : 4'b0011;  // SH, 写入半字
                        ram_wdata_o = byte_addr[1] ? {mem_wdata_i[15:0], 16'b0} : {16'b0, mem_wdata_i[15:0]};
                    end
                    3'b000: begin
                        ram_wen_o = 4'b0001 << byte_addr;  // SB, 写入字节
                        case (byte_addr)
                            2'b00: ram_wdata_o = {24'b0, mem_wdata_i[7:0]};
                            2'b01: ram_wdata_o = {16'b0, mem_wdata_i[7:0], 8'b0};
                            2'b10: ram_wdata_o = {8'b0, mem_wdata_i[7:0], 16'b0};
                            2'b11: ram_wdata_o = {mem_wdata_i[7:0], 24'b0};
                        endcase
                    end
                    default: begin
                        ram_wen_o   = 4'b0000;
                        ram_wdata_o = 0;
                    end
                endcase
            end
            default: begin
                ram_wen_o   = 4'b0000;
                ram_ren_o   = 0;
                ram_wdata_o = 0;
            end
        endcase
    end

endmodule

module memory_stage2 (
    input  wire [ 4:0] mem_op_i,
    input  wire [31:0] mem_addr_i,
    input  wire [31:0] ram_data_i,
    output reg  [31:0] mem_rdata_o
);

    parameter MEM_OP_NONE = 2'b00;
    parameter MEM_OP_LD = 2'b01;
    parameter MEM_OP_ST = 2'b10;

    wire [1:0] mem_op = mem_op_i[4:3];
    wire [2:0] func = mem_op_i[2:0];
    wire [1:0] byte_addr = mem_addr_i[1:0];


    always @(*) begin
        case (mem_op)
            MEM_OP_LD:
            case (func)
                3'b010: mem_rdata_o = ram_data_i;  // LW
                3'b001:  // LH
                mem_rdata_o = byte_addr[1] 
                    ? {{16{ram_data_i[31]}}, ram_data_i[31:16]} 
                    : {{16{ram_data_i[15]}}, ram_data_i[15:0]};
                3'b000:  // LB
                case (byte_addr)
                    2'b00:   mem_rdata_o = {{24{ram_data_i[7]}}, ram_data_i[7:0]};
                    2'b01:   mem_rdata_o = {{24{ram_data_i[15]}}, ram_data_i[15:8]};
                    2'b10:   mem_rdata_o = {{24{ram_data_i[23]}}, ram_data_i[23:16]};
                    2'b11:   mem_rdata_o = {{24{ram_data_i[31]}}, ram_data_i[31:24]};
                    default: mem_rdata_o = 32'b0;
                endcase
                3'b100:  // LBU
                case (byte_addr)
                    2'b00: mem_rdata_o = {24'b0, ram_data_i[7:0]};
                    2'b01: mem_rdata_o = {24'b0, ram_data_i[15:8]};
                    2'b10: mem_rdata_o = {24'b0, ram_data_i[23:16]};
                    2'b11: mem_rdata_o = {24'b0, ram_data_i[31:24]};
                endcase
                3'b101:  // LHU
                mem_rdata_o = byte_addr[1] ? {16'b0, ram_data_i[31:16]} : {16'b0, ram_data_i[15:0]};

                default: mem_rdata_o = 32'b0;
            endcase
            default: mem_rdata_o = 32'b0;
        endcase
    end

endmodule
