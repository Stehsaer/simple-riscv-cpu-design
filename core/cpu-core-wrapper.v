module cpu_core_wrapper (

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *) input wire clk_i,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_i RST" *) input wire rst_i,

    /* L1i Cache */

    // Signals from IF stage
    output wire if_product_ready_o,
    input  wire cache_accept_ready_i,

    // Signals to ID stage
    output wire id_accept_ready_o,
    input  wire cache_product_ready_i,

    output wire [31:0] if_pc_o,
    output wire [30:0] if_branch_target_o,

    input wire [31:0] cache_pc_i,
    input wire [31:0] cache_inst_i,
    input wire [30:0] cache_branch_target_i,


    output wire flush_pipeline_o,
    output wire flush_dcache_o,
    input  wire flush_dcache_done_i,

    /* L1d Cache */

    output wire [29:0] ram_addr,

    output wire ram_rd_ready,
    input wire ram_rd_valid,
    input wire [31:0] ram_rdata,

    output wire ram_wr_valid,
    output wire [3:0] ram_wr_byte,
    output wire [31:0] ram_wdata,
    input wire ram_busy
);

    parameter PC_INIT = 32'h0010_0000;

    cpu_core_v6 #(
        .PC_INIT(PC_INIT)
    ) u_cpu_core (
        .clk_i(clk_i),
        .rst_i(rst_i),

        /* L1i Cache */

        // Signals from IF stage
        .if_product_ready_o  (if_product_ready_o),
        .cache_accept_ready_i(cache_accept_ready_i),

        // Signals to ID stage
        .id_accept_ready_o(id_accept_ready_o),
        .cache_product_ready_i(cache_product_ready_i),

        .if_pc_o(if_pc_o),
        .if_branch_target_o(if_branch_target_o),

        .cache_pc_i(cache_pc_i),
        .cache_inst_i(cache_inst_i),
        .cache_branch_target_i(cache_branch_target_i),

        .flush_pipeline_o(flush_pipeline_o),
        .flush_dcache_o(flush_dcache_o),
        .flush_dcache_done_i(flush_dcache_done_i),

        /* L1d Cache */

        .ram_addr(ram_addr),

        .ram_rd_ready(ram_rd_ready),
        .ram_rd_valid(ram_rd_valid),
        .ram_rdata(ram_rdata),

        .ram_wr_valid(ram_wr_valid),
        .ram_wr_byte(ram_wr_byte),
        .ram_wdata(ram_wdata),
        .ram_busy(ram_busy)
    );

endmodule
