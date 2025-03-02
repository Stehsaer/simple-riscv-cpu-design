module cpu_core (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF data:icache, ASSOCIATED_RESET rst_i" *)
    input wire clk_i,
    input wire rst_i,

    /* L1i Cache */

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

    `include "./control-signals.vh"

    /*========== Register File ==========*/

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

    /*========== Pipeline Signals ==========*/

    wire flush;
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


    /*========== BP ==========*/

    localparam BP_STRONG_NOT_TAKEN = 2'b00;
    localparam BP_WEAK_NOT_TAKEN = 2'b01;
    localparam BP_WEAK_TAKEN = 2'b10;
    localparam BP_STRONG_TAKEN = 2'b11;

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

    /*========== ICACHE ==========*/

    wire [31:0] icache_pc_out;
    wire [31:0] icache_inst_out;
    wire [30:0] icache_branch_target_out;

    wire [31:0] icache_pc_in;
    wire [30:0] icache_branch_target_in;

    wire icache_valid;
    wire icache_ready;

    Inst_cache_w32_addr32 inst_cache (
        .clk(clk_i),
        .rst(rst_i),

        .input_valid    (1'b1),
        .cache_ready    (icache_ready),
        .pc_i           (icache_pc_in),
        .branch_target_i(icache_branch_target_in),

        .output_ready   (cache_id_accept_ready),
        .cache_valid    (icache_valid),
        .pc_o           (icache_pc_out),
        .branch_target_o(icache_branch_target_out),
        .inst_o         (icache_inst_out),

        .fence_i(invalidate_icache),
        .flush_i(flush),

        // // Output control signal
        // output wire address_misaligned,
        // output reg  fetch_error,
        // // input wire clear_fetch_error,

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

    /*========== DCACHE ==========*/

    wire [29:0] dcache_addr;

    wire dcache_wen;
    wire [31:0] dcache_din;
    wire [3:0] dcache_wmask;
    wire dcache_ren;
    wire dcache_rresp;
    wire [31:0] dcache_dout;
    wire dcache_busy;
    wire dcache_flush_en;
    wire dcache_flush_done;

    assign dcache_flush_en   = clean_dcache;
    assign clean_dcache_done = dcache_flush_done;

    Data_cache_w32_addr32 data_cache (
        .clk(clk_i),
        .rst(rst_i),

        .addr(dcache_addr),

        .wen  (dcache_wen),
        .din  (dcache_din),
        .wmask(dcache_wmask),

        .ren  (dcache_ren),
        .rresp(dcache_rresp),
        .dout (dcache_dout),

        .busy(dcache_busy),

        .flush_en  (dcache_flush_en),
        .flush_done(dcache_flush_done),

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

    /*========== IF ==========*/

    reg [31:0] if_pc;  // 系统总PC，按字节编址
    assign icache_pc_in = if_pc;

    wire [31:0] if_pc_wdata;  // PC写入数值
    wire if_pc_wen;  // PC写入使能

    // Counter == Strong Taken && Target Cache Hit

    wire bp_target_cache_address_hit = bp_target_rdata[60:31] == if_pc[31:2];

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
        else if (if_pc_wen) if_pc <= if_pc_wdata;
        else if (icache_ready) begin  // Increase PC only when Cache is ready
            if_pc <= {if_branch_target, 1'b0};
        end
    end

    /*========== CACHE-OUTPUT-DECODE ==========*/

    wire [3:0] cache_inst_alu_op;
    wire [1:0] cache_inst_alu_section;
    wire [3:0] cache_inst_alu_num1_sel, cache_inst_alu_num2_sel;
    wire [ 1:0] cache_inst_wb_sel;
    wire [ 4:0] cache_inst_wb_reg;
    wire [31:1] cache_inst_wb_reg_onfly;
    wire cache_inst_rs1_req, cache_inst_rs2_req;
    wire cache_inst_pc_sel;
    wire [4:0] cache_inst_cmp_op;
    wire [4:0] cache_inst_mem_op;
    wire cache_inst_bp_enabled;
    wire cache_inst_fencei;

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
        .mem_op_o(cache_inst_mem_op),
        .bp_enabled_o(cache_inst_bp_enabled),
        .fencei_o(cache_inst_fencei)
    );

    /*========== ID ==========*/

    reg [31:0] cache_id_inst, cache_id_pc;
    reg [3:0] cache_id_alu_op;
    reg [1:0] cache_id_alu_section;
    reg [3:0] cache_id_alu_num1_sel, cache_id_alu_num2_sel;
    reg [ 1:0] cache_id_wb_sel;
    reg [ 4:0] cache_id_wb_reg;
    reg [31:1] cache_id_wb_reg_onfly;
    reg cache_id_rs1_req, cache_id_rs2_req;
    reg cache_id_pc_sel;
    reg [4:0] cache_id_cmp_op;
    reg [4:0] cache_id_mem_op;
    reg cache_id_bp_enabled;
    reg [30:0] cache_id_bp_target;
    reg cache_id_fencei;

    always @(posedge clk_i) begin
        if (rst_i) begin
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
            cache_id_mem_op       <= 0;
            cache_id_bp_enabled   <= 0;
            cache_id_bp_target    <= 0;
            cache_id_fencei       <= 0;

            cache_id_valid        <= 0;
        end else if (flush) begin
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
                cache_id_mem_op       <= cache_inst_mem_op;
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

    wire id_unavailable;

    // Bypass Pipe

    reg [31:0] ex_id_result_feedback, mem1_id_result_feedback, mem2_id_result_feedback;
    wire [4:0] ex_id_wb_reg_feedback, mem1_id_wb_reg_feedback, mem2_id_wb_reg_feedback;

    wire ex_id_wb_valid, mem1_id_wb_valid, mem2_id_wb_valid;

    inst_decode_v2_stage2 u_inst_decode_v2_stage2 (
        .inst_i            (cache_id_inst),
        .pc_i              (cache_id_pc),
        .reg_raddr1        (reg_file_raddr1),
        .reg_raddr2        (reg_file_raddr2),
        .reg_rdata1        (reg_file_rdata1),
        .reg_rdata2        (reg_file_rdata2),
        .rs1_req_i         (cache_id_rs1_req),
        .rs2_req_i         (cache_id_rs2_req),
        .alu_num1_sel_i    (cache_id_alu_num1_sel),
        .alu_num2_sel_i    (cache_id_alu_num2_sel),
        .wb_reg_onfly_i    (wb_reg_onfly),
        .ex_id_wb_reg_i    (ex_id_wb_reg_feedback),
        .ex_id_wb_data_i   (ex_id_result_feedback),
        .ex_id_wb_valid_i  (ex_id_wb_valid),
        .mem1_id_wb_reg_i  (mem1_id_wb_reg_feedback),
        .mem1_id_wb_data_i (mem1_id_result_feedback),
        .mem1_id_wb_valid_i(mem1_id_wb_valid),
        .mem2_id_wb_reg_i  (mem2_id_wb_reg_feedback),
        .mem2_id_wb_data_i (mem2_id_result_feedback),
        .mem2_id_wb_valid_i(mem2_id_wb_valid),
        .alu_num1_o        (id_alu_num1),
        .alu_num2_o        (id_alu_num2),
        .cmp_num1_o        (id_cmp_num1),
        .cmp_num2_o        (id_cmp_num2),
        .mem_wdata_o       (id_mem_wdata),
        .stall_o           (id_unavailable)
    );


    assign id_ready_go = !id_unavailable;

    /*========== EX ==========*/

    reg [30:0] id_ex_bp_target;

    reg [ 3:0] id_ex_alu_op;
    reg [ 1:0] id_ex_alu_section;
    reg [31:0] id_ex_alu_num1, id_ex_alu_num2;

    reg [1:0] id_ex_wb_sel;
    reg [4:0] id_ex_wb_reg;
    reg [31:1] id_ex_wb_reg_onfly;

    reg id_ex_pc_sel;
    reg [4:0] id_ex_cmp_op;
    reg [4:0] id_ex_mem_op;

    reg [31:0] id_ex_cmp_num1, id_ex_cmp_num2;
    reg [31:0] id_ex_mem_wdata;

    reg [31:0] id_ex_inst;  // for debug

    reg id_ex_bp_enabled;

    reg id_ex_fencei;

    reg [31:0] id_ex_pc;

    always @(posedge clk_i) begin
        if (rst_i) begin
            id_ex_bp_target    <= 0;
            id_ex_alu_op       <= 0;
            id_ex_alu_section  <= 0;
            id_ex_alu_num1     <= 0;
            id_ex_alu_num2     <= 0;
            id_ex_wb_sel       <= 0;
            id_ex_wb_reg       <= 0;
            id_ex_wb_reg_onfly <= 0;
            id_ex_pc_sel       <= 0;
            id_ex_cmp_op       <= 0;
            id_ex_mem_op       <= 0;
            id_ex_cmp_num1     <= 0;
            id_ex_cmp_num2     <= 0;
            id_ex_mem_wdata    <= 0;
            id_ex_pc           <= 0;
            id_ex_fencei       <= 0;

            id_ex_inst         <= 0;

            id_ex_valid        <= 0;
        end else if (flush) begin
            id_ex_valid <= 0;
        end else if (id_ex_accept_ready) begin
            id_ex_valid <= id_product_ready;
            if (id_product_ready) begin
                id_ex_bp_target    <= cache_id_bp_target;
                id_ex_alu_op       <= cache_id_alu_op;
                id_ex_alu_section  <= cache_id_alu_section;
                id_ex_alu_num1     <= id_alu_num1;
                id_ex_alu_num2     <= id_alu_num2;
                id_ex_wb_sel       <= cache_id_wb_sel;
                id_ex_wb_reg       <= cache_id_wb_reg;
                id_ex_wb_reg_onfly <= cache_id_wb_reg_onfly;
                id_ex_pc_sel       <= cache_id_pc_sel;
                id_ex_cmp_op       <= cache_id_cmp_op;
                id_ex_mem_op       <= cache_id_mem_op;
                id_ex_cmp_num1     <= id_cmp_num1;
                id_ex_cmp_num2     <= id_cmp_num2;
                id_ex_mem_wdata    <= id_mem_wdata;
                id_ex_bp_enabled   <= cache_id_bp_enabled;
                id_ex_pc           <= cache_id_pc;
                id_ex_fencei       <= cache_id_fencei;

                id_ex_inst         <= cache_id_inst;
            end
        end
    end

    // ALU

    wire [31:0] ex_alu_result, ex_alu_add_result;
    wire ex_do_branch;

    always @(*) begin
        case (id_ex_wb_sel)
            0: ex_id_result_feedback = ex_alu_result;
            1: ex_id_result_feedback = id_ex_pc + 4;
            2: ex_id_result_feedback = 0;
            3: ex_id_result_feedback = 0;
        endcase
    end

    assign ex_id_wb_valid = id_ex_valid && id_ex_mem_op == MEM_OP_NONE;
    assign ex_id_wb_reg_feedback = id_ex_valid && id_ex_mem_op[4:3] != MEM_OP_ST ? id_ex_wb_reg : 0;

    reg  ex_fencei_inprogress;

    wire ex_fencei = ex_fencei_inprogress && !dcache_busy && !dcache_flush_done;

    assign clean_dcache      = ex_fencei;
    assign invalidate_icache = ex_fencei;

    always @(posedge clk_i) begin
        if (rst_i) ex_fencei_inprogress <= 0;
        else if (dcache_flush_done) ex_fencei_inprogress <= 0;
        else if (id_ex_valid && id_ex_fencei) ex_fencei_inprogress <= 1;
    end

    wire alu_busy;

    assign ex_ready_go = 
		id_ex_mem_op[4:3] == MEM_OP_NONE 
		? !alu_busy && (ex_fencei_inprogress ? dcache_flush_done : !id_ex_fencei)
		: ((id_ex_mem_op[4:3] == MEM_OP_LD || id_ex_mem_op[4:3] == MEM_OP_ST) ? !dcache_busy && id_ex_valid : 1);

    alu alu_module (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .alu_op_i(id_ex_alu_op),
        .alu_section_i(id_ex_alu_section),
        .alu_num1_i(id_ex_alu_num1),
        .alu_num2_i(id_ex_alu_num2),
        .alu_result_o(ex_alu_result),
        .alu_add_result_o(ex_alu_add_result),
        .alu_valid_i(id_ex_valid),
        .alu_busy_o(alu_busy)
    );

    // Memory

    wire [29:0] ex_ram_addr;
    wire [31:0] ex_ram_wdata;
    wire [3:0] ex_ram_wr_byte;
    wire ex_ram_rd_ready;

    memory_stage1 memory_module1 (
        .mem_op_i(id_ex_mem_op),
        .mem_addr_i(ex_alu_add_result),
        .mem_wdata_i(id_ex_mem_wdata),

        .ram_addr_o (ex_ram_addr),
        .ram_wdata_o(ex_ram_wdata),
        .ram_wen_o  (ex_ram_wr_byte),
        .ram_ren_o  (ex_ram_rd_ready)
    );

    assign dcache_addr  = ex_ram_addr;
    assign dcache_din   = ex_ram_wdata;
    assign dcache_wmask = ex_ram_wr_byte;

    assign dcache_wen   = id_ex_valid && id_ex_mem_op[4:3] == 2'b10 && ex_ram_wr_byte != 0;
    assign dcache_ren   = id_ex_valid && id_ex_mem_op[4:3] == 2'b01;

    // Branch

    branch branch_module (
        .cmp_op_i(id_ex_cmp_op),
        .cmp_num1_i(id_ex_cmp_num1),
        .cmp_num2_i(id_ex_cmp_num2),
        .do_branch_o(ex_do_branch)
    );

    assign if_pc_wdata = id_ex_pc_sel && ex_do_branch && !dcache_flush_done ? ex_alu_add_result : id_ex_pc + 4;
    wire ex_branch_address_correct = id_ex_bp_target == if_pc_wdata[31:1];

    assign if_pc_wen = ex_product_ready && ex_mem1_accept_ready && (id_ex_pc_sel
        // Branch if: 
        // 1. Branch misprediction / Branch address incorrect
        // 2. Flush dcache has done
        && !ex_branch_address_correct || dcache_flush_done);

    assign flush = if_pc_wen;

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
            bp_wen        <= id_ex_valid && id_ex_pc_sel && id_ex_bp_enabled;
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

    assign bp_target_wdata  = {bp_wb_pc[31:2], bp_add_result[31:1]};

    assign bp_history_wdata = {bp_history_rwdata[8:0], bp_do_branch};

    always @(*) begin
        case (bp_counter_rwdata)
            BP_STRONG_NOT_TAKEN:
            bp_counter_wdata = bp_do_branch ? BP_WEAK_NOT_TAKEN : BP_STRONG_NOT_TAKEN;
            BP_WEAK_NOT_TAKEN:
            bp_counter_wdata = bp_do_branch ? BP_WEAK_TAKEN : BP_STRONG_NOT_TAKEN;
            BP_WEAK_TAKEN: bp_counter_wdata = bp_do_branch ? BP_STRONG_TAKEN : BP_WEAK_NOT_TAKEN;
            BP_STRONG_TAKEN: bp_counter_wdata = bp_do_branch ? BP_STRONG_TAKEN : BP_WEAK_TAKEN;
        endcase
    end

    /*========== MEM1 ==========*/

    reg [1:0] ex_mem1_wb_sel;
    reg [31:0] ex_mem1_alu_result, ex_mem1_pc4;
    reg [ 4:0] ex_mem1_mem_op;
    reg [ 4:0] ex_mem1_wb_reg;
    reg [31:1] ex_mem1_wb_reg_onfly;

    always @(posedge clk_i) begin
        if (rst_i) begin
            ex_mem1_alu_result   <= 0;
            ex_mem1_pc4          <= 0;
            ex_mem1_mem_op       <= 0;
            ex_mem1_wb_reg       <= 0;
            ex_mem1_wb_sel       <= 0;
            ex_mem1_wb_reg_onfly <= 0;
            ex_mem1_valid        <= 0;
        end else if (ex_mem1_accept_ready) begin
            ex_mem1_valid <= ex_product_ready;
            if (ex_product_ready) begin
                ex_mem1_alu_result   <= ex_alu_result;
                ex_mem1_pc4          <= id_ex_pc + 4;
                ex_mem1_mem_op       <= id_ex_mem_op;
                ex_mem1_wb_reg       <= id_ex_wb_reg;
                ex_mem1_wb_sel       <= id_ex_wb_sel;
                ex_mem1_wb_reg_onfly <= id_ex_wb_reg_onfly;
            end
        end
    end

    assign mem1_ready_go = 1;


    always @(*) begin
        case (ex_mem1_wb_sel)
            0: mem1_id_result_feedback <= ex_mem1_alu_result;
            1: mem1_id_result_feedback <= ex_mem1_pc4;
            default: mem1_id_result_feedback <= 0;
        endcase
    end

    assign mem1_id_wb_valid = ex_mem1_valid && ex_mem1_mem_op == MEM_OP_NONE;
    assign mem1_id_wb_reg_feedback = ex_mem1_valid && ex_mem1_mem_op[4:3] != MEM_OP_ST ? ex_mem1_wb_reg : 0;

    /*========== MEM2 ==========*/

    reg [ 4:0] mem1_mem2_wb_reg;
    reg [ 4:0] mem1_mem2_mem_op;
    reg [31:0] mem1_mem2_alu_result;
    reg [31:0] mem1_mem2_pc4;
    reg [ 1:0] mem1_mem2_wb_sel;
    reg [31:1] mem1_mem2_wb_reg_onfly;

    always @(posedge clk_i) begin
        if (rst_i) begin
            mem1_mem2_wb_reg       <= 0;
            mem1_mem2_mem_op       <= 0;
            mem1_mem2_alu_result   <= 0;
            mem1_mem2_pc4          <= 0;
            mem1_mem2_wb_sel       <= 0;
            mem1_mem2_wb_reg_onfly <= 0;
            mem1_mem2_valid        <= 0;
        end else if (mem1_mem2_accept_ready) begin
            mem1_mem2_valid <= mem1_product_ready;
            if (mem1_product_ready) begin
                mem1_mem2_wb_reg       <= ex_mem1_wb_reg;
                mem1_mem2_mem_op       <= ex_mem1_mem_op;
                mem1_mem2_alu_result   <= ex_mem1_alu_result;
                mem1_mem2_pc4          <= ex_mem1_pc4;
                mem1_mem2_wb_sel       <= ex_mem1_wb_sel;
                mem1_mem2_wb_reg_onfly <= ex_mem1_wb_reg_onfly;
            end
        end
    end

    assign mem2_ready_go = mem1_mem2_mem_op[4:3] == MEM_OP_LD ? dcache_rresp && mem1_mem2_valid : 1;

    wire [31:0] mem2_ram_rdata;
    reg [31:0] mem2_reg_wdata;
    reg [4:0] mem2_reg_waddr;
    reg mem2_reg_wen;

    always @(*) begin
        case (mem1_mem2_wb_sel)
            0: mem2_reg_wdata = mem1_mem2_alu_result;
            1: mem2_reg_wdata = mem1_mem2_pc4;
            2: mem2_reg_wdata = mem2_ram_rdata;
            3: mem2_reg_wdata = 0;
        endcase

        mem2_reg_wen   = mem2_product_ready && mem1_mem2_wb_sel != WB_NONE;
        mem2_reg_waddr = mem1_mem2_wb_reg;
    end

    assign reg_file_wen   = mem2_reg_wen;
    assign reg_file_waddr = mem2_reg_waddr;
    assign reg_file_wdata = mem2_reg_wdata;

    memory_stage2 memory_module2 (
        .mem_op_i  (mem1_mem2_mem_op),
        .mem_addr_i(mem1_mem2_alu_result),
        .ram_data_i(dcache_dout),

        .mem_rdata_o(mem2_ram_rdata)
    );

    assign wb_reg_onfly = (id_ex_valid ? id_ex_wb_reg_onfly : 0) 
        | (ex_mem1_valid ? ex_mem1_wb_reg_onfly : 0) 
        | (mem1_mem2_valid ? mem1_mem2_wb_reg_onfly : 0);

    always @(*) begin
        mem2_id_result_feedback = mem2_reg_wdata;
    end

    wire [31:0] debug_pc = mem1_mem2_pc4 - 4;
    wire debug_rst = rst_i;

    assign mem2_id_wb_valid = mem2_product_ready ? mem1_mem2_mem_op[4:3] != MEM_OP_ST : 0;
    assign mem2_id_wb_reg_feedback = mem2_product_ready && mem1_mem2_mem_op[4:3] != MEM_OP_ST ? mem1_mem2_wb_reg : 0;

endmodule
