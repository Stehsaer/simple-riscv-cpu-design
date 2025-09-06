module cpu_core (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF data:icache, ASSOCIATED_RESET rst_i" *)
    input wire clk_i,
    input wire rst_i,

    /* Interrupt */

    input wire timer_interrupt_i,
    input wire external_interrupt_i,

    /* L1i Cache */
    (* X_INTERFACE_PARAMETER = "MAX_BURST_LENGTH 8, SUPPORTS_NARROW_BURST 0, NUM_WRITE_OUTSTANDING 0, NUM_READ_OUTSTANDING 0" *)

    output wire icache_arvalid,
    input wire icache_arready,
    output wire [31:0] icache_araddr,
    output wire [7:0] icache_arlen,
    output wire [3:0] icache_arcache,
    output wire [2:0] icache_arburst,
    output wire [0:0] icache_arid,
    output wire [2:0] icache_arsize,
    output wire icache_arlock,

    input wire icache_rvalid,
    output wire icache_rready,
    input wire [127:0] icache_rdata,
    input wire icache_rlast,
    input wire [0:0] icache_rid,
    input wire [1:0] icache_rresp,

    /* L1d Cache */
    (* X_INTERFACE_PARAMETER = "MAX_BURST_LENGTH 8, SUPPORTS_NARROW_BURST 1, NUM_WRITE_OUTSTANDING 0, NUM_READ_OUTSTANDING 0" *)

    output wire data_awvalid,
    input wire data_awready,
    output wire [31:0] data_awaddr,
    output wire [7:0] data_awlen,
    output wire [3:0] data_awcache,
    output wire [2:0] data_awsize,
    output wire [1:0] data_awburst,  // FIXED
    output wire [0:0] data_awid,  // FIXED
    output wire data_awlock,  // FIXED

    output wire data_wvalid,
    input wire data_wready,
    output wire data_wlast,
    output wire [127:0] data_wdata,
    output wire [15:0] data_wstrb,

    input wire data_bvalid,
    input wire [1:0] data_bresp,
    output wire data_bready,

    output wire data_arvalid,
    input wire data_arready,
    output wire [31:0] data_araddr,
    output wire [7:0] data_arlen,
    output wire [3:0] data_arcache,
    output wire [2:0] data_arsize,
    output wire [2:0] data_arburst,
    output wire [0:0] data_arid,
    output wire data_arlock,

    input wire data_rvalid,
    output wire data_rready,
    input wire [127:0] data_rdata,
    input wire data_rlast,
    input wire [0:0] data_rid,
    input wire [1:0] data_rresp
);

    `include "func/decode-signals.vh"
    `include "func/csr-encoding.vh"

    //========== Register File ==========*/

    wire [4:0] reg_file_raddr1, reg_file_raddr2;
    wire [31:0] reg_file_rdata1, reg_file_rdata2;
    wire reg_file_wen;
    wire [4:0] reg_file_waddr;
    wire [31:0] reg_file_wdata;

    reg_file reg_file_module (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .raddr1_i(reg_file_raddr1),
        .raddr2_i(reg_file_raddr2),
        .waddr_i(reg_file_waddr),
        .wdata_i(reg_file_wdata),
        .wen_i(reg_file_wen),

        .rdata1_o(reg_file_rdata1),
        .rdata2_o(reg_file_rdata2)
    );

    //========== Pipeline Signals ==========*/

    wire ex_flush, wb_flush;
    wire clean_dcache;
    wire clean_dcache_done;
    wire invalidate_icache;
    wire invalidate_dcache;

    reg cache_id_valid, id_ex_valid, ex_mem1_valid, mem1_mem2_valid;

    wire if_ready_go, id_ready_go, ex_ready_go, mem1_ready_go, mem2_ready_go;

    wire cache_id_accept_ready, id_ex_accept_ready, ex_mem1_accept_ready, mem1_mem2_accept_ready;

    wire id_product_ready = cache_id_valid && id_ready_go;
    wire ex_product_ready = id_ex_valid && ex_ready_go;
    wire mem1_product_ready = ex_mem1_valid && mem1_ready_go;
    wire mem2_product_ready = mem1_mem2_valid && mem2_ready_go;

    assign cache_id_accept_ready  = !cache_id_valid || id_product_ready && id_ex_accept_ready;
    assign id_ex_accept_ready     = !id_ex_valid || ex_product_ready && ex_mem1_accept_ready;
    assign ex_mem1_accept_ready   = !ex_mem1_valid || mem1_product_ready && mem1_mem2_accept_ready;
    assign mem1_mem2_accept_ready = !mem1_mem2_valid || mem2_product_ready && mem2_ready_go;

    //========== CSR ==========*/
    // Currently ignoring side-effects of reading CSR

    wire [11:0] csr_addr;
    wire [31:0] csr_read_result;
    wire csr_read_failed;
    wire [31:0] csr_ex_wdata;
    wire [31:0] csr_ex_wmask;
    wire csr_ex_wen;

    // Predefined CSR Value
    localparam HART_ID = 0;
    localparam ARCH_ID = 0;
    localparam IMPL_ID = 0;
    localparam VENDOR_ID = 0;
    localparam CONFIG_PTR = 0;
    localparam ISA_FLAGS = 32'h40001100;

    // CSR: mscratch

    reg [31:0] mscratch;
    wire mscrarch_wen;
    wire [31:0] mscratch_wdata;
    wire [31:0] mscratch_ex_data;

    csr_pipeline mscratch_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mscratch_ex_data),
        .csr_mem_o          (),
        .csr_wb_o           (),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (0),
        .csr_wb_wmask       (0),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MSCRATCH), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (0),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mscratch),
        .csr_reg_wen_o      (mscrarch_wen),
        .csr_reg_wdata_o    (mscratch_wdata)
    );
    
    always @(posedge clk_i) begin
        if (rst_i) mscratch <= 0;
        else if (mscrarch_wen) mscratch <= mscratch_wdata;
    end

    // CSR: mepc

    reg [31:0] mepc;
    wire mepc_wen;
    wire [31:0] mepc_wdata;
    wire [31:0] mepc_ex_data, mepc_wb_data;
    wire [31:0] mepc_wb_wdata;
    wire mepc_wb_wen;

    csr_pipeline mepc_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mepc_ex_data),
        .csr_mem_o          (),
        .csr_wb_o           (mepc_wb_data),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (mepc_wb_wdata),
        .csr_wb_wmask       (32'hFFFFFFFF),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MEPC), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (mepc_wb_wen),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mepc),
        .csr_reg_wen_o      (mepc_wen),
        .csr_reg_wdata_o    (mepc_wdata)
    );
    
    always @(posedge clk_i) begin
        if (rst_i) mepc <= 0;
        else if (mepc_wen) mepc <= mepc_wdata;
    end

    // CSR: mcause

    reg [31:0] mcause;
    wire mcause_wen;
    wire [31:0] mcause_wdata;
    wire [31:0] mcause_ex_data;
    wire [31:0] mcause_wb_wdata;
    wire mcause_wb_wen;

    csr_pipeline mcause_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mcause_ex_data),
        .csr_mem_o          (),
        .csr_wb_o           (),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (mcause_wb_wdata),
        .csr_wb_wmask       (32'hFFFFFFFF),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MCAUSE), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (mcause_wb_wen),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mcause),
        .csr_reg_wen_o      (mcause_wen),
        .csr_reg_wdata_o    (mcause_wdata)
    );
    
    always @(posedge clk_i) begin
        if (rst_i) mcause <= 0;
        else if (mcause_wen) mcause <= mcause_wdata;
    end

    // CSR: mtval

    reg [31:0] mtval;
    wire mtval_wen;
    wire [31:0] mtval_wdata;
    wire [31:0] mtval_ex_data;
    wire [31:0] mtval_wb_wdata;
    wire mtval_wb_wen;

    csr_pipeline mtval_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mtval_ex_data),
        .csr_mem_o          (),
        .csr_wb_o           (),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (mtval_wb_wdata),
        .csr_wb_wmask       (32'hFFFFFFFF),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MTVAL), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (mtval_wb_wen),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mtval),
        .csr_reg_wen_o      (mtval_wen),
        .csr_reg_wdata_o    (mtval_wdata)
    );
    
    always @(posedge clk_i) begin
        if (rst_i) mtval <= 0;
        else if (mtval_wen) mtval <= mtval_wdata;
    end

    // CSR: mtvec

    reg [31:0] mtvec;
    wire mtvec_wen;
    wire [31:0] mtvec_wdata;
    wire [31:0] mtvec_ex_data;
    wire [31:0] mtvec_mem_data;

    csr_pipeline mtvec_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mtvec_ex_data),
        .csr_mem_o          (mtvec_mem_data),
        .csr_wb_o           (),
        .csr_ex_wdata       (csr_ex_wdata & 32'hfffffffd),
        .csr_ex_wmask       (csr_ex_wmask),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (0),
        .csr_wb_wmask       (0),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MTVEC), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (0),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mtvec),
        .csr_reg_wen_o      (mtvec_wen),
        .csr_reg_wdata_o    (mtvec_wdata)
    );
    
    always @(posedge clk_i) begin
        if (rst_i) mtvec <= 0;
        else if (mtvec_wen) mtvec <= mtvec_wdata;
    end

    // CSR: mie

    reg [31:0] mie;
    wire mie_wen;
    wire [31:0] mie_wdata;
    wire [31:0] mie_ex_data;
    wire [31:0] mie_mem_data;
    wire [31:0] mie_wb_data;

    csr_pipeline mie_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mie_ex_data),
        .csr_mem_o          (mie_mem_data),
        .csr_wb_o           (mie_wb_data),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (0),
        .csr_wb_wmask       (0),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MIE), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (0),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mie),
        .csr_reg_wen_o      (mie_wen),
        .csr_reg_wdata_o    (mie_wdata)
    );

    always @(posedge clk_i) begin
        if (rst_i) mie <= 0;
        else if (mie_wen) mie <= mie_wdata;
    end

    // CSR: mip

    reg [31:0] mip;
    wire [31:0] mip_wmask;
    wire [31:0] mip_wdata;
    wire [31:0] mip_ex_data;
    wire [31:0] mip_mem_data;
    wire [31:0] mip_wb_data;

    reg timer_interrupt_reg, external_interrupt_reg;

    csr_pipeline_complex mip_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mip_ex_data),
        .csr_mem_o          (mip_mem_data),
        .csr_wb_o           (mip_wb_data),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (0),
        .csr_wb_wmask       (0),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MIP), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (0),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mip),
        .csr_reg_wmask_o    (mip_wmask),
        .csr_reg_wdata_o    (mip_wdata)
    );


    always @(posedge clk_i) begin
        if (rst_i) mip <= 0;
        else begin
            mip <= 
                mip & ~mip_wmask 
                | mip_wdata & mip_wmask 
                | {24'b0, timer_interrupt_reg, 7'b0} 
                | {20'b0, external_interrupt_reg, 11'b0};
        end
    end

    always @(posedge clk_i) begin
        if (rst_i) begin
            timer_interrupt_reg    <= 0;
            external_interrupt_reg  <= 0;
        end else begin
            timer_interrupt_reg <= timer_interrupt_i;
            external_interrupt_reg <= external_interrupt_i;
        end
    end

    // CSR: mstatus

    reg [63:0] mstatus;
    wire mstatush_wen, mstatus_wen;
    wire [31:0] mstatush_wdata, mstatus_wdata;
    wire [31:0] mstatush_ex_data, mstatus_ex_data;
    wire [63:0] mstatus_wb_wdata;
    wire mstatus_wb_wen;
    wire [63:0] mstatus_mem_data;
    wire [63:0] mstatus_wb_data;

    csr_pipeline mstatush_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mstatush_ex_data),
        .csr_mem_o          (mstatus_mem_data[63:32]),
        .csr_wb_o           (mstatus_wb_data[63:32]),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask & 0),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (mstatus_wb_wdata[63:32]),
        .csr_wb_wmask       (32'hFFFFFFFF),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MSTATUSH), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (mstatus_wb_wen),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mstatus[63:32]),
        .csr_reg_wen_o      (mstatush_wen),
        .csr_reg_wdata_o    (mstatush_wdata)
    );

    csr_pipeline mstatus_pipeline(
        .clk                (clk_i),
        .rst                (rst_i),
        .wb_flush_i         (wb_flush),
        .csr_ex_o           (mstatus_ex_data),
        .csr_mem_o          (mstatus_mem_data[31:0]),
        .csr_wb_o           (mstatus_wb_data[31:0]),
        .csr_ex_wdata       (csr_ex_wdata),
        .csr_ex_wmask       (csr_ex_wmask & 32'h88),
        .csr_mem_wdata      (0),
        .csr_mem_wmask      (0),
        .csr_wb_wdata       (mstatus_wb_wdata[31:0]),
        .csr_wb_wmask       (32'hFFFFFFFF),
        .csr_ex_wen_i       (csr_ex_wen && csr_addr == `CSR_MSTATUS), 
        .csr_mem_wen_i      (0),
        .csr_wb_wen_i       (mstatus_wb_wen),
        .csr_id_ex_valid_i  (id_ex_valid),
        .csr_ex_mem_valid_i (ex_mem1_valid),
        .csr_mem_wb_valid_i (mem1_mem2_valid),
        .csr_ex_mem_step_i  (ex_mem1_accept_ready && ex_product_ready),
        .csr_mem_wb_step_i  (mem1_mem2_accept_ready && mem1_product_ready),
        .csr_reg_i          (mstatus[31:0]),
        .csr_reg_wen_o      (mstatus_wen),
        .csr_reg_wdata_o    (mstatus_wdata)
    );
    
    always @(posedge clk_i) begin
        if (rst_i) mstatus <= 0;
        else begin
            if (mstatush_wen) mstatus[63:32] <= mstatush_wdata;
            if (mstatus_wen) mstatus[31:0] <= mstatus_wdata;
        end
    end

    // CSR Mux

    csr_mux ex_csr_muxer(
        .addr       (csr_addr),
        .csr_data   (csr_read_result),
        .fail       (csr_read_failed),

        .mvendorid  (VENDOR_ID),
        .marchid    (ARCH_ID),
        .mimpid     (IMPL_ID),
        .mhartid    (HART_ID),
        .mconfigptr (CONFIG_PTR),
        .mstatus    (mstatus[31:0]),
        .misa       (ISA_FLAGS),
        .mie        (mie_ex_data),
        .mtvec      (mtvec_ex_data),
        .mstatush   (mstatus[63:32]),
        .medelegh   (0),
        .mscratch   (mscratch_ex_data),
        .mepc       (mepc_ex_data),
        .mcause     (mcause_ex_data),
        .mtval      (mtval_ex_data),
        .mip        (mip_ex_data),
        .menvcfg    (0),
        .menvcfgh   (0)
    );


    //========== BP ==========*/

    `define BP_STRONG_NOT_TAKEN 2'b00
    `define BP_WEAK_NOT_TAKEN 2'b01
    `define BP_WEAK_TAKEN 2'b10
    `define BP_STRONG_TAKEN 2'b11

    // Read

    wire [7:0] bp_history_raddr;
    wire [9:0] bp_history_rdata;
    wire [9:0] bp_counter_raddr;
    wire [1:0] bp_counter_rdata;
    wire [6:0] bp_target_raddr;
    wire [60:0] bp_target_rdata;  // 60-31：PC[31:2]；30-0：Target Address
    wire bp_target_valid_rdata;

    // Write

    wire [7:0] bp_history_waddr;
    wire [9:0] bp_history_wdata;
    wire bp_history_wen;
    wire [9:0] bp_history_rwdata;

    wire [9:0] bp_counter_waddr;
    reg [1:0] bp_counter_wdata;
    wire bp_counter_wen;
    wire [1:0] bp_counter_rwdata;

    wire [6:0] bp_target_waddr;
    wire [60:0] bp_target_wdata;
    wire bp_target_wen;

    // 256-Entry BHR
    branch_predict_history_register bp_history (
        .a(bp_history_waddr),
        .d(bp_history_wdata),
        .dpra(bp_history_raddr),
        .clk(clk_i),
        .we(bp_history_wen),
        .spo(bp_history_rwdata),
        .dpo(bp_history_rdata)
    );

    // 1024-Entry PHB
    branch_predict_counter bp_counter (
        .a(bp_counter_waddr),
        .d(bp_counter_wdata),
        .dpra(bp_counter_raddr),
        .clk(clk_i),
        .we(bp_counter_wen),
        .spo(bp_counter_rwdata),
        .dpo(bp_counter_rdata)
    );

    // 128-Entry BTB
    branch_predict_target bp_target (
        .a(bp_target_waddr),
        .d(bp_target_wdata),
        .dpra(bp_target_raddr),
        .clk(clk_i),
        .we(bp_target_wen),
        .dpo(bp_target_rdata)
    );

    reg [127:0] bp_target_valid_reg;

    always @(posedge clk_i) begin
        if (rst_i) bp_target_valid_reg <= 128'b0;
        else if (bp_target_wen) bp_target_valid_reg[bp_target_waddr[6:0]] <= 1;
    end

    assign bp_target_valid_rdata = bp_target_valid_reg[bp_target_raddr[6:0]];

    //========== ICACHE ==========*/

    wire [31:0] icache_pc_out;
    wire [31:0] icache_inst_out;
    wire [30:0] icache_branch_target_out;
    wire `INT_SIGWIDTH icache_trapno_out;
    wire icache_have_trap_out;

    wire [31:0] icache_pc_in;
    wire [30:0] icache_branch_target_in;
    wire `INT_SIGWIDTH icache_trapno_in;
    wire icache_have_trap_in;

    wire icache_valid;
    wire icache_ready;

    Inst_cache_w32_addr32 #(`INT_SIGWIDTH_NUM, `INT_INSTR_ACCESS_FAULT) inst_cache (
        .clk(clk_i),
        .rst(rst_i),

        .input_valid    (1'b1),
        .cache_ready    (icache_ready),
        .pc_i           (icache_pc_in),
        .branch_target_i(icache_branch_target_in),
        .trapno_i(icache_trapno_in),
        .have_trap_i(icache_have_trap_in),

        .output_ready   (cache_id_accept_ready),
        .cache_valid    (icache_valid),
        .pc_o           (icache_pc_out),
        .branch_target_o(icache_branch_target_out),
        .inst_o         (icache_inst_out),
        .trapno_o       (icache_trapno_out),
        .have_trap_o    (icache_have_trap_out),

        .fence_i(invalidate_icache),
        .flush_i(ex_flush || wb_flush),

        .m_axi_arready(icache_arready),
        .m_axi_arvalid(icache_arvalid),
        .m_axi_araddr (icache_araddr),
        .m_axi_arlen  (icache_arlen),
        .m_axi_arcache(icache_arcache),
        .m_axi_arburst(icache_arburst),
        .m_axi_arid   (icache_arid),
        .m_axi_arsize (icache_arsize),
        .m_axi_arlock (icache_arlock),

        .m_axi_rvalid(icache_rvalid),
        .m_axi_rready(icache_rready),
        .m_axi_rdata (icache_rdata),
        .m_axi_rlast (icache_rlast),
        .m_axi_rid   (icache_rid),
        .m_axi_rresp (icache_rresp)
    );

    //========== DCACHE ==========*/

    wire [29:0] dcache_addr;

    wire dcache_wen;
    wire [31:0] dcache_din;
    wire [3:0] dcache_wmask;
    wire dcache_ren;
    wire dcache_resp;
    wire [31:0] dcache_dout;
    wire dcache_busy;
    wire dcache_flush_en;
    wire dcache_flush_done;
    wire dcache_have_trap_in;

    assign dcache_flush_en   = clean_dcache;
    assign clean_dcache_done = dcache_flush_done;

    wire dcache_fetch_error;

    Data_cache_w32_addr32 data_cache (
        .clk(clk_i),
        .rst(rst_i),

        .addr(dcache_addr),

        .wen  (dcache_wen),
        .din  (dcache_din),
        .wmask(dcache_wmask),

        .ren  (dcache_ren),
        .dout (dcache_dout),

        .have_trap_i(dcache_have_trap_in),
        .fetch_error_o(dcache_fetch_error),
        .busy(dcache_busy),
        .resp(dcache_resp),

        .flush_en  (dcache_flush_en),
        .flush_done(dcache_flush_done),

        .wb_flush(wb_flush),

        .m_axi_awaddr (data_awaddr),
        .m_axi_awlen  (data_awlen),
        .m_axi_awsize (data_awsize),
        .m_axi_awburst(data_awburst),
        .m_axi_awlock (data_awlock),
        .m_axi_awcache(data_awcache),
        .m_axi_awid   (data_awid),
        .m_axi_awvalid(data_awvalid),
        .m_axi_awready(data_awready),

        .m_axi_wdata (data_wdata),
        .m_axi_wstrb (data_wstrb),
        .m_axi_wlast (data_wlast),
        .m_axi_wvalid(data_wvalid),
        .m_axi_wready(data_wready),

        .m_axi_bvalid(data_bvalid),
        .m_axi_bready(data_bready),
        .m_axi_bresp (data_bresp),

        .m_axi_araddr (data_araddr),
        .m_axi_arlen  (data_arlen),
        .m_axi_arsize (data_arsize),
        .m_axi_arburst(data_arburst),
        .m_axi_arlock (data_arlock),
        .m_axi_arcache(data_arcache),
        .m_axi_arid   (data_arid),
        .m_axi_arvalid(data_arvalid),
        .m_axi_arready(data_arready),

        .m_axi_rdata (data_rdata),
        .m_axi_rresp (data_rresp),
        .m_axi_rlast (data_rlast),
        .m_axi_rvalid(data_rvalid),
        .m_axi_rready(data_rready)
    );

    //========== IF ==========*/

    reg [31:0] if_pc;
    assign icache_pc_in = if_pc;

    wire [31:0] ex_if_pc_wdata, wb_if_pc_wdata;
    wire ex_if_pc_wen, wb_if_pc_wen;

    // Counter == Strong Taken && Target Cache Hit

    wire bp_target_cache_address_hit = bp_target_rdata[53:31] == if_pc[31:9];

    wire if_branch_taken = bp_counter_rdata[1] 
        && bp_target_valid_rdata 
        && bp_target_cache_address_hit;

    wire [30:0] if_branch_target = if_branch_taken ? bp_target_rdata[30:0] : {if_pc[31:2] + 1, 1'b0};
    assign icache_branch_target_in = if_branch_target;

    assign bp_history_raddr        = if_pc[9:2];
    assign bp_counter_raddr        = bp_history_rdata;
    assign bp_target_raddr         = if_pc[8:2];

    assign if_ready_go             = 1;

    parameter PC_INIT = 32'h0010_0000;

    always @(posedge clk_i) begin
        if (rst_i) if_pc <= PC_INIT;
        else if (wb_if_pc_wen) if_pc <= wb_if_pc_wdata;
        else if (ex_if_pc_wen) if_pc <= ex_if_pc_wdata;
        else if (icache_ready) begin  // Increase PC only when Cache is ready
            if_pc <= {if_branch_target, 1'b0};
        end
    end

    // Detect Instruction Address Misalign
    wire pc_misalign = if_pc[1:0] != 2'b00;
    assign icache_trapno_in = pc_misalign ? `INT_INSTR_MISALIGN : 0;
    assign icache_have_trap_in = pc_misalign;

    //========== CACHE-OUTPUT-DECODE ==========*/

    wire `ALU_SECTION_SIGWIDTH cache_inst_alu_section;
    wire `ALU_OP_SIGWIDTH cache_inst_alu_op;
    wire `ALU_NUM_SEL_SIGWIDTH cache_inst_alu_num1_sel, cache_inst_alu_num2_sel;

    wire `WB_SRC_SIGWIDTH cache_inst_wb_sel;
    wire [4:0] cache_inst_wb_reg;
    wire [31:1] cache_inst_wb_reg_onfly;

    wire cache_inst_rs1_req, cache_inst_rs2_req;

    wire `PC_SRC_SIGWIDTH cache_inst_pc_sel;

    wire `CMP_OP_SIGWIDTH cache_inst_cmp_op;
    wire `CMP_FUNCT_SIGWIDTH cache_inst_cmp_funct;

    wire `MEM_OP_SIGWIDTH cache_inst_mem_op;
    wire `MEM_FUNCT_SIGWIDTH cache_inst_mem_funct;

    wire cache_inst_bp_enabled;
    wire cache_inst_fencei;

    wire `CSR_WRITE_SIGWIDTH cache_inst_csr_write;
    wire cache_inst_csr_do_read;

    wire `SYS_SIGWIDTH cache_inst_sys_op;

    inst_decode_v2_stage1 inst_decode_stage1 (
        .inst_i(icache_inst_out),
        .pc_i  (icache_pc_out),

        .alu_section_o(cache_inst_alu_section),
        .alu_op_o(cache_inst_alu_op),
        .alu_num1_sel_o(cache_inst_alu_num1_sel),
        .alu_num2_sel_o(cache_inst_alu_num2_sel),

        .wb_sel_o(cache_inst_wb_sel),
        .wb_reg_o(cache_inst_wb_reg),
        .wb_reg_onehot_o(cache_inst_wb_reg_onfly),

        .rs1_req_o(cache_inst_rs1_req),
        .rs2_req_o(cache_inst_rs2_req),

        .pc_sel_o(cache_inst_pc_sel),
        .cmp_op_o(cache_inst_cmp_op),
        .cmp_funct_o(cache_inst_cmp_funct),

        .mem_op_o(cache_inst_mem_op),
        .mem_funct_o(cache_inst_mem_funct),

        .bp_enabled_o(cache_inst_bp_enabled),
        .fencei_o(cache_inst_fencei),

        .csr_write_mode_o(cache_inst_csr_write),
        .csr_do_read_o(cache_inst_csr_do_read),

        .sys_op_o(cache_inst_sys_op)
    );

    //========== ID ==========*/

    reg [31:0] cache_id_inst, cache_id_pc;

    reg `ALU_SECTION_SIGWIDTH cache_id_alu_section;
    reg `ALU_OP_SIGWIDTH cache_id_alu_op;
    reg `ALU_NUM_SEL_SIGWIDTH cache_id_alu_num1_sel, cache_id_alu_num2_sel;

    reg `WB_SRC_SIGWIDTH cache_id_wb_sel;
    reg [ 4:0] cache_id_wb_reg;
    reg [31:1] cache_id_wb_reg_onfly;

    reg cache_id_rs1_req, cache_id_rs2_req;

    reg `PC_SRC_SIGWIDTH cache_id_pc_sel;

    reg `CMP_OP_SIGWIDTH cache_id_cmp_op;
    reg `CMP_FUNCT_SIGWIDTH cache_id_cmp_funct;

    reg `MEM_OP_SIGWIDTH cache_id_mem_op;
    reg `MEM_FUNCT_SIGWIDTH cache_id_mem_funct;

    reg `CSR_WRITE_SIGWIDTH cache_id_csr_write;
    reg cache_id_csr_do_read;

    reg `INT_SIGWIDTH cache_id_trapno;
    reg cache_id_have_trap;

    reg `SYS_SIGWIDTH cache_id_sys_op;

    reg cache_id_bp_enabled;
    reg [30:0] cache_id_bp_target;
    reg cache_id_fencei;

    always @(posedge clk_i) begin
        if (rst_i) begin
            cache_id_valid <= 0;

            cache_id_inst         <= 0;
            cache_id_pc           <= 0;
            cache_id_alu_op       <= 0;
            cache_id_alu_section  <= 0;
            cache_id_alu_num1_sel <= 0;
            cache_id_alu_num2_sel <= 0;
            cache_id_wb_sel       <= 0;
            cache_id_wb_reg       <= 0;
            cache_id_wb_reg_onfly <= 0;
            cache_id_rs1_req      <= 0;
            cache_id_rs2_req      <= 0;
            cache_id_pc_sel       <= 0;
            cache_id_cmp_op       <= 0;
            cache_id_cmp_funct    <= 0;
            cache_id_mem_op       <= 0;
            cache_id_mem_funct    <= 0;
            cache_id_csr_write    <= 0;
            cache_id_csr_do_read  <= 0;
            cache_id_trapno       <= 0;
            cache_id_have_trap    <= 0;
            cache_id_sys_op       <= 0;
            cache_id_bp_enabled   <= 0;
            cache_id_bp_target    <= 0;
            cache_id_fencei       <= 0;
        end else if (ex_flush || wb_flush) begin
            cache_id_valid <= 0;
        end else if (cache_id_accept_ready) begin
            cache_id_valid <= icache_valid;
            if (icache_valid) begin
                cache_id_inst         <= icache_inst_out;
                cache_id_pc           <= icache_pc_out;
                cache_id_alu_op       <= cache_inst_alu_op;
                cache_id_alu_section  <= cache_inst_alu_section;
                cache_id_alu_num1_sel <= cache_inst_alu_num1_sel;
                cache_id_alu_num2_sel <= cache_inst_alu_num2_sel;
                cache_id_wb_sel       <= cache_inst_wb_sel;
                cache_id_wb_reg       <= cache_inst_wb_reg;
                cache_id_wb_reg_onfly <= cache_inst_wb_reg_onfly;
                cache_id_rs1_req      <= cache_inst_rs1_req;
                cache_id_rs2_req      <= cache_inst_rs2_req;
                cache_id_pc_sel       <= cache_inst_pc_sel;
                cache_id_cmp_op       <= cache_inst_cmp_op;
                cache_id_cmp_funct    <= cache_inst_cmp_funct;
                cache_id_mem_op       <= cache_inst_mem_op;
                cache_id_mem_funct    <= cache_inst_mem_funct;
                cache_id_csr_write    <= cache_inst_csr_write;
                cache_id_csr_do_read  <= cache_inst_csr_do_read;
                cache_id_trapno       <= icache_trapno_out;
                cache_id_have_trap    <= icache_have_trap_out;
                cache_id_sys_op       <= cache_inst_sys_op;
                cache_id_bp_enabled   <= cache_inst_bp_enabled;
                cache_id_bp_target    <= icache_branch_target_out;
                cache_id_fencei       <= cache_inst_fencei;
            end
        end
    end

    wire [31:0] id_alu_num1, id_alu_num2;
    wire [31:0] id_cmp_num1, id_cmp_num2;
    wire [31:0] id_mem_wdata;

    wire [31:1] wb_reg_onfly;

    wire [11:0] id_csr_addr;

    wire id_unavailable;

    // Bypass Pipe

    reg [31:0] ex_modify_data, mem1_modify_data, mem2_modify_data;
    wire [4:0] ex_modify_reg_feedback, mem1_modify_reg_feedback, mem2_modify_reg_feedback;

    wire ex_modify_data_valid, mem1_modify_data_valid, mem2_modify_data_valid;

    inst_decode_v2_stage2 u_inst_decode_v2_stage2 (
        .inst_i                  (cache_id_inst),
        .pc_i                    (cache_id_pc),
        .reg_raddr1              (reg_file_raddr1),
        .reg_raddr2              (reg_file_raddr2),
        .reg_rdata1              (reg_file_rdata1),
        .reg_rdata2              (reg_file_rdata2),
        .rs1_req_i               (cache_id_rs1_req),
        .rs2_req_i               (cache_id_rs2_req),
        .alu_num1_sel_i          (cache_id_alu_num1_sel),
        .alu_num2_sel_i          (cache_id_alu_num2_sel),
        .wb_reg_onfly_i          (wb_reg_onfly),
        .ex_modify_reg_i         (ex_modify_reg_feedback),
        .ex_modify_data_i        (ex_modify_data),
        .ex_modify_data_valid_i  (ex_modify_data_valid),
        .mem1_modify_reg_i       (mem1_modify_reg_feedback),
        .mem1_modify_data_i      (mem1_modify_data),
        .mem1_modify_data_valid_i(mem1_modify_data_valid),
        .mem2_modify_reg_i       (mem2_modify_reg_feedback),
        .mem2_modify_data_i      (mem2_modify_data),
        .mem2_modify_data_valid_i(mem2_modify_data_valid),
        .alu_num1_o              (id_alu_num1),
        .alu_num2_o              (id_alu_num2),
        .cmp_num1_o              (id_cmp_num1),
        .cmp_num2_o              (id_cmp_num2),
        .mem_wdata_o             (id_mem_wdata),
        .stall_o                 (id_unavailable),
        .csr_addr_o              (id_csr_addr)
    );


    assign id_ready_go = !id_unavailable;

    //========== EX ==========*/

    // ALU
    reg `ALU_SECTION_SIGWIDTH id_ex_alu_section;
    reg `ALU_OP_SIGWIDTH id_ex_alu_op;
    reg [31:0] id_ex_alu_num1, id_ex_alu_num2;

    // Bypass
    reg `WB_SRC_SIGWIDTH id_ex_wb_sel;
    reg [4:0] id_ex_wb_reg;
    reg [31:1] id_ex_wb_reg_onfly;

    // PC, COMP, MEM
    reg `PC_SRC_SIGWIDTH id_ex_pc_sel;
    reg `CMP_OP_SIGWIDTH id_ex_cmp_op;
    reg `CMP_FUNCT_SIGWIDTH id_ex_cmp_funct;
    reg `MEM_OP_SIGWIDTH id_ex_mem_op;
    reg `MEM_FUNCT_SIGWIDTH id_ex_mem_funct;

    // CSR
    reg `CSR_WRITE_SIGWIDTH id_ex_csr_write;
    reg id_ex_csr_do_read;
    reg [11:0] id_ex_csr_addr;

    reg `SYS_SIGWIDTH id_ex_sys_op;

    // Full-width data
    reg [31:0] id_ex_cmp_num1, id_ex_cmp_num2;
    reg [31:0] id_ex_mem_wdata;

    reg [31:0] id_ex_inst;  

    reg id_ex_bp_enabled;
    reg id_ex_fencei;

    reg [31:0] id_ex_pc, id_ex_pc4;
    reg [30:0] id_ex_bp_target;

    reg `INT_SIGWIDTH id_ex_trapno;
    reg id_ex_have_trap;

    always @(posedge clk_i) begin
        if (rst_i ) begin
            id_ex_valid        <= 0;
            id_ex_bp_target    <= 0;
            id_ex_inst         <= 0;
            id_ex_alu_op       <= 0;
            id_ex_alu_section  <= 0;
            id_ex_alu_num1     <= 0;
            id_ex_alu_num2     <= 0;
            id_ex_wb_sel       <= 0;
            id_ex_wb_reg       <= 0;
            id_ex_wb_reg_onfly <= 0;
            id_ex_pc_sel       <= 0;
            id_ex_cmp_op       <= 0;
            id_ex_cmp_funct    <= 0;
            id_ex_mem_op       <= 0;
            id_ex_mem_funct    <= 0;
            id_ex_cmp_num1     <= 0;
            id_ex_cmp_num2     <= 0;
            id_ex_mem_wdata    <= 0;
            id_ex_bp_enabled   <= 0;
            id_ex_pc           <= 0;
            id_ex_pc4          <= 0;
            id_ex_fencei       <= 0;
            id_ex_csr_addr     <= 0;
            id_ex_csr_write    <= 0;
            id_ex_csr_do_read  <= 0;
            id_ex_trapno       <= 0;
            id_ex_have_trap    <= 0;
            id_ex_sys_op       <= 0;
        end
        else if(ex_flush || wb_flush) begin
            id_ex_valid <= 0;
        end else if (id_ex_accept_ready) begin
            id_ex_valid <= id_product_ready;
            if (id_product_ready) begin
                id_ex_bp_target    <= cache_id_bp_target;
                id_ex_inst         <= cache_id_inst;

                id_ex_alu_op       <= cache_id_alu_op;
                id_ex_alu_section  <= cache_id_alu_section;
                id_ex_alu_num1     <= id_alu_num1;
                id_ex_alu_num2     <= id_alu_num2;
                id_ex_wb_sel       <= cache_id_wb_sel;
                id_ex_wb_reg       <= cache_id_wb_reg;
                id_ex_wb_reg_onfly <= cache_id_wb_reg_onfly;
                id_ex_pc_sel       <= cache_id_pc_sel;
                id_ex_cmp_op       <= cache_id_cmp_op;
                id_ex_cmp_funct    <= cache_id_cmp_funct;
                id_ex_mem_op       <= cache_id_mem_op;
                id_ex_mem_funct    <= cache_id_mem_funct;
                id_ex_cmp_num1     <= id_cmp_num1;
                id_ex_cmp_num2     <= id_cmp_num2;
                id_ex_mem_wdata    <= id_mem_wdata;
                id_ex_bp_enabled   <= cache_id_bp_enabled;
                id_ex_pc           <= cache_id_pc;
                id_ex_pc4          <= cache_id_pc + 4;
                id_ex_fencei       <= cache_id_fencei;
                id_ex_csr_addr     <= id_csr_addr;
                id_ex_csr_write    <= cache_id_csr_write;
                id_ex_csr_do_read  <= cache_id_csr_do_read;
                id_ex_trapno       <= cache_id_trapno;
                id_ex_have_trap    <= cache_id_have_trap;
                id_ex_sys_op       <= cache_id_sys_op;
            end
        end
    end

    wire ex_no_trap = !cache_id_have_trap;

    // ALU

    wire [31:0] ex_alu_result, ex_alu_add_result;
    wire alu_busy;

    alu alu_module (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .alu_op_i(id_ex_alu_op),
        .alu_section_i(id_ex_alu_section),
        .alu_num1_i(id_ex_alu_num1),
        .alu_num2_i(id_ex_alu_num2),
        .alu_result_o(ex_alu_result),
        .alu_add_result_o(ex_alu_add_result),
        .alu_valid_i(id_ex_valid && ex_no_trap),
        .alu_busy_o(alu_busy)
    );

    // Memory

    wire ex_ram_misaligned;
    wire [29:0] ex_ram_addr;
    wire [31:0] ex_ram_wdata;
    wire [3:0] ex_ram_wr_byte;
    wire ex_ram_rd_ready;

    memory_stage1 memory_module1 (
        // Input
        .mem_op_i   (id_ex_mem_op),
        .mem_funct_i(id_ex_mem_funct),
        .mem_addr_i (ex_alu_add_result),
        .mem_wdata_i(id_ex_mem_wdata),

        // Output
        .ram_addr_o      (ex_ram_addr),
        .ram_wdata_o     (ex_ram_wdata),
        .ram_wen_o       (ex_ram_wr_byte),
        .ram_ren_o       (ex_ram_rd_ready),
        .ram_misaligned_o(ex_ram_misaligned)
    );

    assign dcache_addr  = ex_ram_addr;
    assign dcache_din   = ex_ram_wdata;
    assign dcache_wmask = ex_ram_wr_byte;

    assign dcache_wen   = id_ex_valid && ex_no_trap && id_ex_mem_op == `MEM_OP_ST && ex_ram_wr_byte != 0;
    assign dcache_ren   = id_ex_valid && ex_no_trap && id_ex_mem_op == `MEM_OP_LD;

    reg  ex_fencei_inprogress;
    wire ex_fencei = ex_fencei_inprogress && !dcache_busy && !dcache_flush_done;

    assign clean_dcache      = ex_fencei;
    assign invalidate_icache = ex_fencei;

    always @(posedge clk_i) begin
        if (rst_i) ex_fencei_inprogress <= 0;
        else if (dcache_flush_done) ex_fencei_inprogress <= 0;
        else if (id_ex_valid && ex_no_trap && id_ex_fencei) ex_fencei_inprogress <= 1;
    end

    // CSR

    // [INFO] No CSR-read side-effects are considered yet
    wire csr_write_denied = id_ex_csr_write != `CSR_WRITE_NONE && id_ex_csr_addr[11:10] == 2'b11;
    assign csr_addr = id_ex_csr_addr;

    reg [31:0] ex_csr_write_mask;
    reg [31:0] ex_csr_write_data;

    assign csr_ex_wdata = ex_csr_write_data;
    assign csr_ex_wmask = ex_csr_write_mask;
    assign csr_ex_wen = id_ex_csr_write != `CSR_WRITE_NONE && id_ex_valid && ex_no_trap && !csr_write_denied;
    
    always @(*) begin
        case(id_ex_csr_write)
            `CSR_WRITE_NONE: begin
                ex_csr_write_data = 0;
                ex_csr_write_mask = 0;
            end
            `CSR_WRITE_SETBITS: begin 
                ex_csr_write_data = 32'hFFFFFFFF;
                ex_csr_write_mask = id_ex_alu_num1; 
            end
            `CSR_WRITE_OVERWRITE: begin
                ex_csr_write_data = id_ex_alu_num1;
                ex_csr_write_mask = 32'hFFFFFFFF;
            end
            `CSR_WRITE_CLEARBITS: begin
                ex_csr_write_data = 0;
                ex_csr_write_mask = id_ex_alu_num1;
            end
            default: begin
                ex_csr_write_data = 0;
                ex_csr_write_mask = 0;
            end
        endcase
    end

    // Branch

    wire ex_do_branch;

    branch branch_module (
        .cmp_op_i(id_ex_cmp_op),
        .cmp_funct_i(id_ex_cmp_funct),
        .cmp_num1_i(id_ex_cmp_num1),
        .cmp_num2_i(id_ex_cmp_num2),
        .do_branch_o(ex_do_branch)
    );

    wire ex_branch_direction = id_ex_pc_sel && ex_do_branch && !dcache_flush_done;
    assign ex_if_pc_wdata = ex_branch_direction ? ex_alu_add_result : id_ex_pc4;
    wire ex_branch_address_correct = ex_branch_direction 
        ? id_ex_bp_target == ex_alu_add_result[31:1] 
        : id_ex_bp_target == id_ex_pc4[31:1];

    // [INFO] Branch if: 
    // 1. Branch misprediction / Branch address incorrect
    // 2. ex_flush dcache has done
    assign ex_if_pc_wen = ex_product_ready && ex_mem1_accept_ready 
        && (id_ex_pc_sel && !ex_branch_address_correct || dcache_flush_done);

    assign ex_flush = ex_if_pc_wen;

    reg bp_wen;
    reg bp_do_branch;
    reg [31:0] bp_wb_pc, bp_add_result;

    always @(posedge clk_i) begin
        if (rst_i) begin
            bp_wen        <= 0;
            bp_do_branch  <= 0;
            bp_wb_pc      <= 0;
            bp_add_result <= 0;
        end else begin
            bp_wen        <= id_ex_valid && ex_no_trap && id_ex_pc_sel && id_ex_bp_enabled;
            bp_do_branch  <= ex_do_branch;
            bp_wb_pc      <= id_ex_pc;
            bp_add_result <= ex_alu_add_result;
        end
    end

    assign bp_counter_wen   = bp_wen;
    assign bp_target_wen    = bp_wen;
    assign bp_history_wen   = bp_wen;

    assign bp_history_waddr = bp_wb_pc[9:2];
    assign bp_counter_waddr = bp_history_rwdata;
    assign bp_target_waddr  = bp_wb_pc[8:2];

    assign bp_target_wdata  = {bp_wb_pc[31:9], bp_add_result[31:1]};

    assign bp_history_wdata = {bp_history_rwdata[8:0], bp_do_branch};

    always @(*) begin
        case (bp_counter_rwdata)
            `BP_STRONG_NOT_TAKEN:
            bp_counter_wdata = bp_do_branch ? `BP_WEAK_NOT_TAKEN : `BP_STRONG_NOT_TAKEN;
            `BP_WEAK_NOT_TAKEN:
            bp_counter_wdata = bp_do_branch ? `BP_WEAK_TAKEN : `BP_STRONG_NOT_TAKEN;
            `BP_WEAK_TAKEN: bp_counter_wdata = bp_do_branch ? `BP_STRONG_TAKEN : `BP_WEAK_NOT_TAKEN;
            `BP_STRONG_TAKEN: bp_counter_wdata = bp_do_branch ? `BP_STRONG_TAKEN : `BP_WEAK_TAKEN;
        endcase
    end

    // Bypass

    always @(*) begin
        case (id_ex_wb_sel)
            `WB_ALU: ex_modify_data = ex_alu_result;
            `WB_PC_NEXT: ex_modify_data = id_ex_pc + 4;
            `WB_MEM, `WB_NONE, `WB_CSR: ex_modify_data = 0;
            default: ex_modify_data = 0;
        endcase
    end

    assign ex_modify_data_valid   = id_ex_valid && (id_ex_wb_sel == `WB_ALU || id_ex_wb_sel == `WB_PC_NEXT);
    assign ex_modify_reg_feedback = id_ex_valid && id_ex_mem_op != `MEM_OP_ST ? id_ex_wb_reg : 0;

    // Pipeline Control

    assign ex_ready_go = !ex_no_trap
        || (id_ex_mem_op == `MEM_OP_NONE
            ? !alu_busy && (ex_fencei_inprogress ? dcache_flush_done : !id_ex_fencei) 
            : ((id_ex_mem_op == `MEM_OP_LD || id_ex_mem_op == `MEM_OP_ST) 
                ? !dcache_busy && id_ex_valid
                : 1));

    // Interrupt
    wire `INT_SIGWIDTH ex_mem_trapno = id_ex_mem_op == `MEM_OP_LD ? `INT_LOAD_MISALIGN :`INT_STORE_MISALIGN;
    wire `INT_SIGWIDTH ex_trapno = 
        (csr_write_denied || (id_ex_csr_do_read && csr_read_failed)) ? `INT_ILLEGAL_INSTR :
        ex_ram_misaligned ? ex_mem_trapno : 
        id_ex_sys_op == `SYS_ECALL ? `INT_ECALL_M : 0;

    wire ex_have_trap = !id_ex_have_trap && (csr_write_denied || (id_ex_csr_do_read && csr_read_failed) || ex_ram_misaligned || id_ex_sys_op == `SYS_ECALL);

    //========== MEM1 ==========*/

    reg `WB_SRC_SIGWIDTH ex_mem1_wb_sel;
    reg [31:0] ex_mem1_alu_result, ex_mem1_pc4, ex_mem1_pc, ex_mem1_csr_read_result;
    reg [31:0] ex_mem1_inst;
    reg `MEM_OP_SIGWIDTH ex_mem1_mem_op;
    reg `MEM_FUNCT_SIGWIDTH ex_mem1_mem_funct;
    reg [ 4:0] ex_mem1_wb_reg;
    reg [31:1] ex_mem1_wb_reg_onfly;
    reg `INT_SIGWIDTH ex_mem1_trapno;
    reg ex_mem1_have_trap;
    reg `SYS_SIGWIDTH ex_mem1_sys_op;

    always @(posedge clk_i) begin
        if (rst_i) begin
            ex_mem1_valid           <= 0;
            ex_mem1_alu_result      <= 0;
            ex_mem1_pc4             <= 0;
            ex_mem1_pc              <= 0;
            ex_mem1_csr_read_result <= 0;
            ex_mem1_mem_op          <= 0;
            ex_mem1_mem_funct       <= 0;
            ex_mem1_wb_reg          <= 0;
            ex_mem1_wb_sel          <= 0;
            ex_mem1_wb_reg_onfly    <= 0;
            ex_mem1_trapno          <= 0;
            ex_mem1_have_trap       <= 0;
            ex_mem1_sys_op          <= 0;
            ex_mem1_inst            <= 0;
        end
        else if (wb_flush) begin
            ex_mem1_valid <= 0;
        end else if (ex_mem1_accept_ready) begin
            ex_mem1_valid <= ex_product_ready;
            if (ex_product_ready) begin
                ex_mem1_alu_result      <= ex_alu_result;
                ex_mem1_pc4             <= id_ex_pc + 4;
                ex_mem1_pc              <= id_ex_pc;
                ex_mem1_csr_read_result <= csr_read_result;
                ex_mem1_mem_op          <= id_ex_mem_op;
                ex_mem1_mem_funct       <= id_ex_mem_funct;
                ex_mem1_wb_reg          <= id_ex_wb_reg;
                ex_mem1_wb_sel          <= id_ex_wb_sel;
                ex_mem1_wb_reg_onfly    <= id_ex_wb_reg_onfly;
                ex_mem1_trapno          <= ex_have_trap ? ex_trapno : id_ex_trapno;
                ex_mem1_have_trap       <= ex_have_trap ? ex_have_trap : id_ex_have_trap;
                ex_mem1_sys_op          <= id_ex_sys_op;
                ex_mem1_inst            <= id_ex_inst;
            end
        end
    end

    assign mem1_ready_go = 1;

    always @(*) begin
        case (ex_mem1_wb_sel)
            `WB_ALU: mem1_modify_data = ex_mem1_alu_result;
            `WB_PC_NEXT: mem1_modify_data = ex_mem1_pc4;
            `WB_CSR: mem1_modify_data = ex_mem1_csr_read_result;
            `WB_MEM, `WB_NONE: mem1_modify_data = 0;
            default: mem1_modify_data = 0;
        endcase
    end

    assign mem1_modify_data_valid = ex_mem1_valid && ex_mem1_mem_op == `MEM_OP_NONE;
    assign mem1_modify_reg_feedback = ex_mem1_valid && ex_mem1_mem_op != `MEM_OP_ST ? ex_mem1_wb_reg : 0;

    // Interrupt handling

    wire [15:0] mem1_pending_interrupt = mie_mem_data[15:0] & mip_mem_data[15:0];
    wire mem1_trap_interrupt_pending = mstatus_mem_data[3] && (|mem1_pending_interrupt);

    wire `INT_SIGWIDTH mem1_trap_interrupt_no = 
        mem1_pending_interrupt[7] ? `INT_MTIMER :
        mem1_pending_interrupt[11] ? `INT_MEXT :
        0;

    wire [31:0] mem1_vectored_trap_target = {mtvec_mem_data[31:2] + mem1_trap_interrupt_no, 2'b00};
    wire [31:0] mem1_direct_trap_target = {mtvec_mem_data[31:2], 2'b00};
    wire [31:0] mem1_trap_target = 
        (ex_mem1_have_trap || mem1_pending_interrupt && mtvec_mem_data[1:0] == 2'b00) 
        ? mem1_direct_trap_target 
        : mem1_vectored_trap_target;

    //========== MEM2/WB ==========*/

    reg [ 4:0] mem1_mem2_wb_reg;
    reg `MEM_OP_SIGWIDTH mem1_mem2_mem_op;
    reg `MEM_FUNCT_SIGWIDTH mem1_mem2_mem_funct;
    reg [31:0] mem1_mem2_alu_result;
    reg [31:0] mem1_mem2_pc4;
    reg [31:0] mem1_mem2_pc;
    reg [31:0] mem1_mem2_csr_read_result;
    reg [31:0] mem1_mem2_inst;
    reg [31:0] mem1_mem2_trap_target;
    reg `WB_SRC_SIGWIDTH mem1_mem2_wb_sel;
    reg [31:1] mem1_mem2_wb_reg_onfly;
    reg `INT_SIGWIDTH mem1_mem2_trapno;
    reg mem1_mem2_trap_is_interrupt;
    reg mem1_mem2_have_trap;
    reg `SYS_SIGWIDTH mem1_mem2_sys_op;

    always @(posedge clk_i) begin
        if (rst_i) begin
            mem1_mem2_valid             <= 0;
            mem1_mem2_wb_reg            <= 0;
            mem1_mem2_mem_op            <= 0;
            mem1_mem2_mem_funct         <= 0;
            mem1_mem2_alu_result        <= 0;
            mem1_mem2_pc4               <= 0;
            mem1_mem2_pc                <= 0;
            mem1_mem2_csr_read_result   <= 0;
            mem1_mem2_wb_sel            <= 0;
            mem1_mem2_wb_reg_onfly      <= 0;
            mem1_mem2_trapno            <= 0;
            mem1_mem2_have_trap         <= 0;
            mem1_mem2_sys_op            <= 0;
            mem1_mem2_inst              <= 0;
            mem1_mem2_trap_is_interrupt <= 0;
            mem1_mem2_trap_target       <= 0;
        end
        else if (wb_flush) begin
            mem1_mem2_valid        <= 0;
        end else if (mem1_mem2_accept_ready) begin
            mem1_mem2_valid <= mem1_product_ready;
            if (mem1_product_ready) begin
                mem1_mem2_wb_reg            <= ex_mem1_wb_reg;
                mem1_mem2_mem_op            <= ex_mem1_mem_op;
                mem1_mem2_mem_funct         <= ex_mem1_mem_funct;
                mem1_mem2_alu_result        <= ex_mem1_alu_result;
                mem1_mem2_pc4               <= ex_mem1_pc4;
                mem1_mem2_pc                <= ex_mem1_pc;
                mem1_mem2_csr_read_result   <= ex_mem1_csr_read_result;
                mem1_mem2_wb_sel            <= ex_mem1_wb_sel;
                mem1_mem2_wb_reg_onfly      <= ex_mem1_wb_reg_onfly;
                mem1_mem2_trapno            <= ex_mem1_have_trap ? ex_mem1_trapno : mem1_trap_interrupt_no;
                mem1_mem2_have_trap         <= ex_mem1_have_trap || mem1_trap_interrupt_pending;
                mem1_mem2_trap_is_interrupt <= ex_mem1_have_trap ? 0 : mem1_trap_interrupt_pending;
                mem1_mem2_sys_op            <= ex_mem1_sys_op;
                mem1_mem2_inst              <= ex_mem1_inst;
                mem1_mem2_trap_target       <= mem1_trap_target;
            end
        end
    end

    // Memory

    wire [31:0] mem2_ram_rdata;
    reg [31:0] mem2_reg_wdata;
    reg [4:0] mem2_reg_waddr;
    reg mem2_reg_wen;

    memory_stage2 memory_module2 (
        // Input
        .mem_op_i(mem1_mem2_mem_op),
        .mem_funct_i(mem1_mem2_mem_funct),
        .mem_addr_i(mem1_mem2_alu_result),
        .ram_data_i(dcache_dout),

        // Output
        .mem_rdata_o(mem2_ram_rdata)
    );

    wire mem2_fetch_error = mem1_mem2_mem_op != `MEM_OP_NONE && dcache_fetch_error;

    // Trap handling

    wire [31:0] wb_pc = mem1_mem2_pc;
    reg `INT_SIGWIDTH wb_trapno;

    always @(*) begin
        if (mem1_mem2_have_trap) wb_trapno = mem1_mem2_trapno; // Already have trap
        // New trap: fetch error
        else if (mem2_fetch_error) wb_trapno = mem1_mem2_mem_op == `MEM_OP_LD ? `INT_LOAD_ACCESS_FAULT : `INT_STORE_ACCESS_FAULT;
        else wb_trapno = 0;  
    end

    wire wb_have_trap = mem2_product_ready && (mem1_mem2_have_trap || mem2_fetch_error);
    wire wb_is_mret = mem2_product_ready && mem1_mem2_sys_op == `SYS_MRET;

    assign dcache_have_trap_in = wb_have_trap || ex_mem1_valid && ex_mem1_have_trap;

    assign wb_flush = wb_have_trap || wb_is_mret;
    assign wb_if_pc_wdata = wb_is_mret ? mepc_wb_data : mem1_mem2_trap_target;
    assign wb_if_pc_wen = wb_have_trap || wb_is_mret;

    assign mepc_wb_wdata = wb_pc;
    assign mepc_wb_wen = wb_have_trap;

    wire [31:0] zero32 = 32'b0;
    assign mcause_wb_wdata = {mem1_mem2_trap_is_interrupt, zero32[30 - `INT_SIGWIDTH_NUM : 0], wb_trapno};
    assign mcause_wb_wen = wb_have_trap;

    assign mstatus_wb_wdata = 
    {
        mstatus_wb_data[63:8], 
        wb_is_mret ? 1'b0 : mstatus_wb_data[3], 
        mstatus_wb_data[6:4], 
        wb_is_mret ? mstatus_wb_data[7] : 1'b0, 
        mstatus_wb_data[2:0]
    };

    assign mstatus_wb_wen = wb_have_trap || wb_is_mret;

    reg [31:0] wb_mtval;

    always @(*) begin
        if(1) begin // [TODO] Interrupt
            case (wb_trapno)
                `INT_ILLEGAL_INSTR: wb_mtval = mem1_mem2_inst;

                `INT_INSTR_MISALIGN,
                `INT_INSTR_ACCESS_FAULT,
                `INT_LOAD_MISALIGN,
                `INT_LOAD_ACCESS_FAULT,
                `INT_STORE_MISALIGN,
                `INT_STORE_ACCESS_FAULT:
                    wb_mtval = mem1_mem2_alu_result;

                default: wb_mtval = 0;
            endcase
        end
    end

    assign mtval_wb_wdata = wb_mtval;
    assign mtval_wb_wen = wb_have_trap;

    // Writeback

    always @(*) begin
        case (mem1_mem2_wb_sel)
            `WB_ALU: mem2_reg_wdata = mem1_mem2_alu_result;
            `WB_PC_NEXT: mem2_reg_wdata = mem1_mem2_pc4;
            `WB_MEM: mem2_reg_wdata = mem2_ram_rdata;
            `WB_CSR: mem2_reg_wdata = mem1_mem2_csr_read_result;
            `WB_NONE: mem2_reg_wdata = 0;
            default: mem2_reg_wdata = 0;
        endcase

        mem2_reg_wen   = mem2_product_ready && mem1_mem2_wb_sel != `WB_NONE && !(wb_have_trap || wb_is_mret);
        mem2_reg_waddr = mem1_mem2_wb_reg;
    end

    assign reg_file_wen   = mem2_reg_wen;
    assign reg_file_waddr = mem2_reg_waddr;
    assign reg_file_wdata = mem2_reg_wdata;

    // Pipelining and bypass
 
    assign mem2_ready_go = mem1_mem2_mem_op != `MEM_OP_NONE ? dcache_resp && mem1_mem2_valid : 1;

    assign wb_reg_onfly = (id_ex_valid ? id_ex_wb_reg_onfly : 0) 
        | (ex_mem1_valid ? ex_mem1_wb_reg_onfly : 0) 
        | (mem1_mem2_valid ? mem1_mem2_wb_reg_onfly : 0);

    assign mem2_modify_data_valid = mem2_product_ready ? mem1_mem2_mem_op != `MEM_OP_ST : 0;
    assign mem2_modify_reg_feedback = mem1_mem2_valid && mem1_mem2_mem_op != `MEM_OP_ST ? mem1_mem2_wb_reg : 0;
    
    always @(*) begin
        mem2_modify_data = mem2_reg_wdata;
    end

endmodule
