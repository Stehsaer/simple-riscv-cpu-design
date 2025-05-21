// Memory Module

`include "decode-signals.vh"

// Stage 1: Generate write data
module memory_stage1 (
    input wire `MEM_OP_SIGWIDTH mem_op_i,
    input wire `MEM_FUNCT_SIGWIDTH mem_funct_i,

    input wire [31:0] mem_addr_i,
    input wire [31:0] mem_wdata_i,

    output wire [29:0] ram_addr_o,
    output reg [31:0] ram_wdata_o,
    output reg [3:0] ram_wen_o,
    output reg ram_ren_o,
    output reg ram_misaligned_o
);

    assign ram_addr_o = mem_addr_i >> 2;

    wire [1:0] byte_addr = mem_addr_i[1:0];

    always @(*) begin
        case (mem_op_i)
            `MEM_OP_LD: begin
                ram_wen_o   = 4'b0000;
                ram_ren_o   = 1;
                ram_wdata_o = mem_wdata_i;
            end
            `MEM_OP_ST: begin
                ram_ren_o = 0;

                case (mem_funct_i)
                    `MEM_FUNCT_SW: begin
                        ram_wen_o   = 4'b1111;
                        ram_wdata_o = mem_wdata_i;
                    end
                    `MEM_FUNCT_SH: begin
                        ram_wen_o = byte_addr[1] ? 4'b1100 : 4'b0011;
                        ram_wdata_o = byte_addr[1] ? {mem_wdata_i[15:0], 16'b0} : {16'b0, mem_wdata_i[15:0]};
                    end
                    `MEM_FUNCT_SB: begin
                        ram_wen_o = 4'b0001 << byte_addr;
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

    always @(*) begin
        case (mem_op_i)
            `MEM_OP_NONE: ram_misaligned_o = 0;
            default:
            case (mem_funct_i)
                `MEM_FUNCT_NONE: ram_misaligned_o = 0;
                `MEM_FUNCT_LB, `MEM_FUNCT_LBU, `MEM_FUNCT_SB: ram_misaligned_o = 0;
                `MEM_FUNCT_LH, `MEM_FUNCT_LHU, `MEM_FUNCT_SH: ram_misaligned_o = mem_addr_i[0] != 0;
                `MEM_FUNCT_LW, `MEM_FUNCT_SW: ram_misaligned_o = mem_addr_i[1:0] != 2'b00;
            endcase
        endcase
    end

endmodule

// Stage 2: Parse and crop read-back data
module memory_stage2 (
    input  wire [ 1:0] mem_op_i,
    input  wire [ 2:0] mem_funct_i,
    input  wire [31:0] mem_addr_i,
    input  wire [31:0] ram_data_i,
    output reg  [31:0] mem_rdata_o
);

    wire [1:0] byte_addr = mem_addr_i[1:0];

    always @(*) begin
        case (mem_op_i)
            `MEM_OP_LD:
            case (mem_funct_i)
                `MEM_FUNCT_LW: mem_rdata_o = ram_data_i;

                `MEM_FUNCT_LH:
                mem_rdata_o = byte_addr[1] 
                    ? {{16{ram_data_i[31]}}, ram_data_i[31:16]} 
                    : {{16{ram_data_i[15]}}, ram_data_i[15:0]};

                `MEM_FUNCT_LB:
                case (byte_addr)
                    2'b00:   mem_rdata_o = {{24{ram_data_i[7]}}, ram_data_i[7:0]};
                    2'b01:   mem_rdata_o = {{24{ram_data_i[15]}}, ram_data_i[15:8]};
                    2'b10:   mem_rdata_o = {{24{ram_data_i[23]}}, ram_data_i[23:16]};
                    2'b11:   mem_rdata_o = {{24{ram_data_i[31]}}, ram_data_i[31:24]};
                    default: mem_rdata_o = 32'b0;
                endcase

                `MEM_FUNCT_LBU:
                case (byte_addr)
                    2'b00: mem_rdata_o = {24'b0, ram_data_i[7:0]};
                    2'b01: mem_rdata_o = {24'b0, ram_data_i[15:8]};
                    2'b10: mem_rdata_o = {24'b0, ram_data_i[23:16]};
                    2'b11: mem_rdata_o = {24'b0, ram_data_i[31:24]};
                endcase

                `MEM_FUNCT_LHU:
                mem_rdata_o = byte_addr[1] ? {16'b0, ram_data_i[31:16]} : {16'b0, ram_data_i[15:0]};

                default: mem_rdata_o = 32'b0;
            endcase

            default: mem_rdata_o = 32'b0;
        endcase
    end

endmodule
