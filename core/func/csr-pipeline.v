module csr_pipeline (
    input wire clk,
    input wire rst,

    input wire wb_flush_i,

    output reg  [31:0] csr_ex_o,
    output wire [31:0] csr_mem_o,
    output wire [31:0] csr_wb_o,

    input wire [31:0] csr_ex_wdata,
    input wire [31:0] csr_ex_wmask,
    input wire [31:0] csr_mem_wdata,
    input wire [31:0] csr_mem_wmask,
    input wire [31:0] csr_wb_wdata,
    input wire [31:0] csr_wb_wmask,

    input wire csr_ex_wen_i,
    input wire csr_mem_wen_i,
    input wire csr_wb_wen_i,

    input wire csr_id_ex_valid_i,
    input wire csr_ex_mem_valid_i,
    input wire csr_mem_wb_valid_i,

    input wire csr_ex_mem_step_i,
    input wire csr_mem_wb_step_i,

    input wire [31:0] csr_reg_i,
    output wire csr_reg_wen_o,
    output wire [31:0] csr_reg_wdata_o
);

    reg [31:0] csr_ex_mem_reg, csr_mem_wb_reg;
    reg csr_ex_mem_dirty, csr_mem_wb_dirty;

    /* Output Logic */

    assign csr_wb_o  = csr_reg_i;
    assign csr_mem_o = csr_mem_wb_dirty && csr_mem_wb_valid_i ? csr_mem_wb_reg : csr_reg_i;

    always @(*) begin
        case ({
            csr_ex_mem_dirty && csr_ex_mem_valid_i, csr_mem_wb_dirty && csr_mem_wb_valid_i
        })
            2'b00: csr_ex_o = csr_reg_i;
            2'b01: csr_ex_o = csr_mem_wb_reg;
            2'b10, 2'b11: csr_ex_o = csr_ex_mem_reg;
        endcase
    end

    /* Pipeline Logic */

    always @(posedge clk) begin
        if (rst || wb_flush_i) begin
            csr_ex_mem_reg   <= 0;
            csr_ex_mem_dirty <= 0;
        end else begin
            if (csr_ex_mem_step_i) begin
                if (csr_ex_wen_i) begin
                    csr_ex_mem_reg   <= csr_ex_o & ~csr_ex_wmask | csr_ex_wdata & csr_ex_wmask;
                    csr_ex_mem_dirty <= 1;
                end else if (csr_id_ex_valid_i) begin
                    csr_ex_mem_reg   <= csr_ex_o;
                    csr_ex_mem_dirty <= 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst || wb_flush_i) begin
            csr_mem_wb_reg   <= 0;
            csr_mem_wb_dirty <= 0;
        end else begin
            if (csr_mem_wb_step_i) begin
                if (csr_mem_wen_i) begin
                    csr_mem_wb_reg   <= csr_mem_o & ~csr_mem_wmask | csr_mem_wdata & csr_mem_wmask;
                    csr_mem_wb_dirty <= 1;
                end else if (csr_ex_mem_valid_i) begin
                    csr_mem_wb_reg   <= csr_ex_mem_reg;
                    csr_mem_wb_dirty <= csr_ex_mem_dirty;
                end
            end
        end
    end

    assign csr_reg_wen_o   = csr_mem_wb_valid_i && (csr_wb_wen_i || csr_mem_wb_dirty);
    assign csr_reg_wdata_o = csr_wb_wen_i ? (csr_reg_i & ~csr_wb_wmask | csr_wb_wdata & csr_wb_wmask) : csr_mem_wb_reg;

endmodule

module csr_pipeline_complex (
    input wire clk,
    input wire rst,

    input wire wb_flush_i,

    output reg  [31:0] csr_ex_o,
    output wire [31:0] csr_mem_o,
    output wire [31:0] csr_wb_o,

    input wire [31:0] csr_ex_wdata,
    input wire [31:0] csr_ex_wmask,
    input wire [31:0] csr_mem_wdata,
    input wire [31:0] csr_mem_wmask,
    input wire [31:0] csr_wb_wdata,
    input wire [31:0] csr_wb_wmask,

    input wire csr_ex_wen_i,
    input wire csr_mem_wen_i,
    input wire csr_wb_wen_i,

    input wire csr_id_ex_valid_i,
    input wire csr_ex_mem_valid_i,
    input wire csr_mem_wb_valid_i,

    input wire csr_ex_mem_step_i,
    input wire csr_mem_wb_step_i,

    input  wire [31:0] csr_reg_i,
    output wire [31:0] csr_reg_wmask_o,
    output wire [31:0] csr_reg_wdata_o
);

    reg [31:0] csr_ex_mem_reg, csr_mem_wb_reg;
    reg [31:0] csr_ex_mem_dirty, csr_mem_wb_dirty;

    /* Output Logic */

    assign csr_wb_o  = csr_reg_i;
    assign csr_mem_o = (|csr_mem_wb_dirty) && csr_mem_wb_valid_i ? csr_mem_wb_reg : csr_reg_i;

    always @(*) begin
        case ({
            (|csr_ex_mem_dirty) && csr_ex_mem_valid_i, (|csr_mem_wb_dirty) && csr_mem_wb_valid_i
        })
            2'b00: csr_ex_o = csr_reg_i;
            2'b01: csr_ex_o = csr_mem_wb_reg;
            2'b10, 2'b11: csr_ex_o = csr_ex_mem_reg;
        endcase
    end

    /* Pipeline Logic */

    always @(posedge clk) begin
        if (rst || wb_flush_i) begin
            csr_ex_mem_reg   <= 0;
            csr_ex_mem_dirty <= 0;
        end else begin
            if (csr_ex_mem_step_i) begin
                if (csr_ex_wen_i) begin
                    csr_ex_mem_reg   <= csr_ex_o & ~csr_ex_wmask | csr_ex_wdata & csr_ex_wmask;
                    csr_ex_mem_dirty <= csr_ex_wmask;
                end else if (csr_id_ex_valid_i) begin
                    csr_ex_mem_reg   <= csr_ex_o;
                    csr_ex_mem_dirty <= 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst || wb_flush_i) begin
            csr_mem_wb_reg   <= 0;
            csr_mem_wb_dirty <= 0;
        end else begin
            if (csr_mem_wb_step_i) begin
                if (csr_mem_wen_i) begin
                    csr_mem_wb_reg   <= csr_mem_o & ~csr_mem_wmask | csr_mem_wdata & csr_mem_wmask;
                    csr_mem_wb_dirty <= csr_mem_wmask | csr_ex_mem_dirty;
                end else if (csr_ex_mem_valid_i) begin
                    csr_mem_wb_reg   <= csr_ex_mem_reg;
                    csr_mem_wb_dirty <= csr_ex_mem_dirty;
                end
            end
        end
    end

    assign csr_reg_wmask_o = csr_mem_wb_valid_i ? ((csr_wb_wen_i ? csr_wb_wmask : 0) | csr_mem_wb_dirty) : 0;
    assign csr_reg_wdata_o = csr_wb_wen_i ? (csr_reg_i & ~csr_wb_wmask | csr_wb_wdata & csr_wb_wmask) : csr_mem_wb_reg;

endmodule
