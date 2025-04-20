
module Inst_cache_w32_addr32 (
    input wire clk,
    input wire rst,

    /* Internal Bus Signals: CPU CORE <=> Cache */

    // Input pipeline
    input wire input_valid,
    output wire cache_ready,
    input wire [31:0] pc_i,
    input wire [30:0] branch_target_i,  // Offset by 1 bit

    // Output pipeline
    input wire output_ready,
    output wire cache_valid,
    output wire [31:0] pc_o,
    output wire [30:0] branch_target_o,
    output wire [31:0] inst_o,

    // Input control signal
    input wire fence_i,  // zifencei support
    input wire flush_i,  // Pipeline flush request

    // Output control signal
    output wire address_misaligned,
    output reg  fetch_error,
    // input wire clear_fetch_error,

    /* External AXI Signals: Cache <=> External AXI Device */

    output wire m_axi_arvalid,
    input wire m_axi_arready,
    output wire [31:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,  // FIXED
    output wire [3:0] m_axi_arcache,  // FIXED
    output wire [2:0] m_axi_arburst,  // FIXED
    output wire [0:0] m_axi_arid,  // FIXED
    output wire [2:0] m_axi_arsize,  // FIXED
    output wire m_axi_arlock,  // FIXED

    input wire m_axi_rvalid,
    output wire m_axi_rready,
    input wire [127:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire [0:0] m_axi_rid,
    input wire [1:0] m_axi_rresp
);

    // Note: 1 Fetch Group = 16 Bytes = 4 Instructions

    /*===== DESIGN PARAMETERS =====*/
    // -- Total Data Size: 16KB
    // -- Block Size: 8 Fetch Group, 128 Bytes
    // -- Associativity: 4
    // -- Internal Data Storage Width: 1 Fetch Group = 128 bits
    // -- Internal Tag Storage Width: 20*4 bits (Tag) + 1*4 bits (Dirty) + 16 Bits (LRU Matrix) = 100 bits
    // -- Internal Data Storage Depth: 1024
    // -- Internal Tag Storage Depth: 32

    /*===== PHYSICAL ADDRESS =====*/
    // -- [1:0]: Should always be 0, otherwise address misalign error occurs
    // -- [3:2]: Offset inside a fetch group
    // -- [6:4]: Offset inside cache line
    // -- [11:7]: Index of cache line
    // -- [31:12]: Tag


    /*===== TAG STORAGE BITS =====*/
    // -- [19:0]: Tag from set 0
    // -- [39:20]: Tag from set 1
    // -- [59:40]: Tag from set 2
    // -- [79:60]: Tag from set 3
    // -- [83:80]: Unused
    // -- [99:84]: LRU Matrix for 4 sets

    /* PIPELINE SIGNALS */

    wire pipeline_flush = flush_i || fence_i;
    wire process_working;

    // Data in interstage register is valid?
    reg query_process_valid, process_output_valid;
    wire input_query_valid = input_valid;

    // Stage has done processing?
    wire query_ready_go = 1;
    wire process_ready_go;

    // Stage produces valid data: input data is valid && stage successfully processes data
    wire query_product_ready = query_ready_go && input_query_valid;
    wire process_product_ready = process_ready_go && query_process_valid;

    // Interstage register accepts new data?
    wire output_external_accept_ready = output_ready;
    wire process_output_accept_ready = !process_output_valid || output_external_accept_ready;
    wire query_process_accept_ready = !query_process_valid && !process_working || process_product_ready && process_output_accept_ready;

    assign cache_ready = query_process_accept_ready && query_product_ready;
    assign cache_valid = process_output_valid;

    /* STORAGE BLOCKS */

    // -- Valid LUTRAM

    reg [3:0] valid_storage_lutram[0:31];
    reg [3:0] valid_storage_dout;

    wire valid_storage_wen, valid_storage_ren;
    wire [4:0] valid_storage_waddr, valid_storage_raddr;
    wire [3:0] valid_storage_din;

    integer valid_lutram_i;
    always @(posedge clk) begin
        if (rst || fence_i) begin

            for (valid_lutram_i = 0; valid_lutram_i < 32; valid_lutram_i = valid_lutram_i + 1)
            valid_storage_lutram[valid_lutram_i] <= 4'h0;

            valid_storage_dout <= 4'h0;

        end else begin
            if (valid_storage_wen) valid_storage_lutram[valid_storage_waddr] <= valid_storage_din;
            if (valid_storage_ren) valid_storage_dout <= valid_storage_lutram[valid_storage_raddr];
        end
    end

    // -- Data BRAM

    wire [9:0] data_storage_waddr, data_storage_raddr;
    wire [127:0] data_storage_wdata;
    wire [127:0] data_storage_rdata;
    wire data_storage_wen, data_storage_ren;
    wire [15:0] data_storage_wmask;

    bram_w128_d1024_sdp data_storage (
        .clka (clk),                 // input wire clka
        .ena  (data_storage_wen),    // input wire ena
        .wea  (data_storage_wmask),  // input wire [15 : 0] wea
        .addra(data_storage_waddr),  // input wire [9 : 0] addra
        .dina (data_storage_wdata),  // input wire [127 : 0] dina
        .clkb (clk),                 // input wire clkb
        .enb  (data_storage_ren),    // input wire enb
        .addrb(data_storage_raddr),  // input wire [9 : 0] addrb
        .doutb(data_storage_rdata)   // output wire [127 : 0] doutb
    );

    // -- Tag BRAM

    wire [4:0] tag_storage_waddr, tag_storage_raddr;
    wire [99:0] tag_storage_wdata;
    wire [99:0] tag_storage_rdata;
    wire tag_storage_wen, tag_storage_ren;

    reg [99:0] tag_storage_lutram[0:31];
    reg [99:0] tag_storage_dout;

    integer tag_lutram_i;
    always @(posedge clk) begin
        if (rst) begin

            for (tag_lutram_i = 0; tag_lutram_i < 32; tag_lutram_i = tag_lutram_i + 1)
            tag_storage_lutram[tag_lutram_i] <= 100'b0;

            tag_storage_dout <= 100'b0;

        end else begin
            if (tag_storage_wen) tag_storage_lutram[tag_storage_waddr] <= tag_storage_wdata;
            if (tag_storage_ren)
                tag_storage_dout <= tag_storage_wen && tag_storage_waddr == tag_storage_raddr ? tag_storage_wdata : tag_storage_lutram[tag_storage_raddr];
        end
    end

    assign tag_storage_rdata = tag_storage_dout;

    /* INPUT-QUERY */

    wire [31:0] input_query_addr = pc_i;
    wire [30:0] input_query_branch_target = branch_target_i;

    /* QUERY */
    // Reads tag from tag storage, reads valid flag from valid storage

    wire query_execute = query_process_accept_ready && query_product_ready;

    assign tag_storage_raddr   = input_query_addr[11:7];
    assign tag_storage_ren     = query_execute;

    assign valid_storage_raddr = input_query_addr[11:7];
    assign valid_storage_ren   = tag_storage_ren;

    /* QUERY-PROCESS */

    reg [31:0] query_process_addr;
    reg [30:0] query_process_branch_target;

    always @(posedge clk) begin
        if (rst) begin
            query_process_valid         <= 0;
            query_process_addr          <= 0;
            query_process_branch_target <= 0;
        end else if (pipeline_flush) begin

            query_process_valid <= 0;

        end else if (query_process_accept_ready) begin
            query_process_valid <= input_query_valid;
            if (query_product_ready) begin
                query_process_addr          <= input_query_addr;
                query_process_branch_target <= input_query_branch_target;
            end
        end
    end

    /* PROCESS */

    wire [ 2:0] process_block_offset = query_process_addr[6:4];
    wire [ 4:0] process_index = query_process_addr[11:7];
    wire [19:0] process_tag = query_process_addr[31:12];

    wire [19:0] process_queried_tag_set0 = tag_storage_rdata[19:0];
    wire [19:0] process_queried_tag_set1 = tag_storage_rdata[39:20];
    wire [19:0] process_queried_tag_set2 = tag_storage_rdata[59:40];
    wire [19:0] process_queried_tag_set3 = tag_storage_rdata[79:60];

    wire [15:0] process_queried_lru_matrix = tag_storage_rdata[99:84];
    wire [ 3:0] process_queried_valid = valid_storage_dout;

    wire [ 1:0] process_lru_selected_set;

    Lru_find_set lru_matrix_parser (
        .lru_matrix(process_queried_lru_matrix),
        .set(process_lru_selected_set)
    );

    wire process_hit_set0 = process_queried_tag_set0 == process_tag && process_queried_valid[0];
    wire process_hit_set1 = process_queried_tag_set1 == process_tag && process_queried_valid[1];
    wire process_hit_set2 = process_queried_tag_set2 == process_tag && process_queried_valid[2];
    wire process_hit_set3 = process_queried_tag_set3 == process_tag && process_queried_valid[3];

    wire process_cache_hit = |{process_hit_set0, process_hit_set1, process_hit_set2, process_hit_set3};

    reg [1:0] process_hit_set;

    always @(*)
        case ({
            process_hit_set3, process_hit_set2, process_hit_set1, process_hit_set0
        })
            4'b0001: process_hit_set = 2'b00;
            4'b0010: process_hit_set = 2'b01;
            4'b0100: process_hit_set = 2'b10;
            4'b1000: process_hit_set = 2'b11;
            default: process_hit_set = 2'b00;
        endcase

    wire [15:0] process_cache_hit_updated_lru_matrix;
    wire [15:0] process_cache_not_hit_updated_lru_matrix;

    Lru_update process_cache_hit_lru_matrix_update (
        .original(process_queried_lru_matrix),
        .set(process_hit_set),
        .updated(process_cache_hit_updated_lru_matrix)
    );

    Lru_update process_cache_not_hit_lru_matrix_update (
        .original(process_queried_lru_matrix),
        .set(process_lru_selected_set),
        .updated(process_cache_not_hit_updated_lru_matrix)
    );

    wire [15:0] process_updated_lru_matrix = process_cache_hit ? process_cache_hit_updated_lru_matrix : process_cache_not_hit_updated_lru_matrix;
    wire [1:0] process_final_set = process_cache_hit ? process_hit_set : process_lru_selected_set;

    // State

    reg [2:0] process_state;
    reg [2:0] process_readin_counter;

    `define STATE_NORMAL 0

    // Send readin address
    `define STATE_REPLACE_READIN_SEND_ADDRESS 4  
    // Receive readin data & Write received word to storage
    `define STATE_REPLACE_READIN_RECEIVE_DATA 5 
    // Finalize readin: wait for the last word to write in storage
    `define STATE_REPLACE_READIN_FINALIZE 6  
    // Execute the original request (Read or Write)
    `define STATE_REPLACE_EXECUTE 7  

    // -- Normal: Reads a block from data storage; Updates tag and LRU matrix in tag matrix

    assign data_storage_raddr = {process_final_set, process_index, process_block_offset};
    assign data_storage_ren = process_product_ready && process_output_accept_ready;

    assign tag_storage_wen = process_product_ready || process_state == `STATE_REPLACE_READIN_FINALIZE;
    assign tag_storage_waddr = process_index;
    assign tag_storage_wdata = {
        process_updated_lru_matrix,
        4'b0,  // Dirty bit not used in ICache
        process_final_set == 3 ? process_tag : process_queried_tag_set3,
        process_final_set == 2 ? process_tag : process_queried_tag_set2,
        process_final_set == 1 ? process_tag : process_queried_tag_set1,
        process_final_set == 0 ? process_tag : process_queried_tag_set0
    };

    // -- Replace: Writes block to data storage, updates valid tag

    assign data_storage_wen = process_state == `STATE_REPLACE_READIN_RECEIVE_DATA && m_axi_rvalid;
    assign data_storage_wdata = m_axi_rdata;
    assign data_storage_waddr = {process_final_set, process_index, process_readin_counter};
    assign data_storage_wmask = 16'hFFFF;

    assign valid_storage_waddr = process_index;
    assign valid_storage_wen = process_state == `STATE_REPLACE_READIN_FINALIZE;
    assign valid_storage_din = valid_storage_dout | (4'b0001 << process_final_set);

    /* AXI FIXED VALUE */

    assign m_axi_arcache = 4'b1111;
    assign m_axi_arlen = 7;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arsize = 3'b100;
    assign m_axi_arid = 0;
    assign m_axi_arlock = 1'b0;

    assign m_axi_arvalid = process_state == `STATE_REPLACE_READIN_SEND_ADDRESS;
    assign m_axi_araddr = {process_tag, process_index, 7'd0};
    assign m_axi_rready = process_state == `STATE_REPLACE_READIN_RECEIVE_DATA;

    // When implementing fetch-error handling, remove this signal and use the one from the input
    wire clear_fetch_error = 0;

    always @(posedge clk) begin
        if (rst || clear_fetch_error) fetch_error <= 0;
        else if (m_axi_rvalid && m_axi_rlast && m_axi_rresp != 2'b00) fetch_error <= 1;
    end

    // State machine

    always @(posedge clk)
        if (rst) begin
            process_state          <= `STATE_NORMAL;
            process_readin_counter <= 0;
        end else
            case (process_state)
                `STATE_NORMAL: begin
                    if (query_process_valid && !process_cache_hit) begin
                        process_state          <= `STATE_REPLACE_READIN_SEND_ADDRESS;
                        process_readin_counter <= 0;
                    end
                end

                `STATE_REPLACE_READIN_SEND_ADDRESS:
                if (m_axi_arready) process_state <= `STATE_REPLACE_READIN_RECEIVE_DATA;

                `STATE_REPLACE_READIN_RECEIVE_DATA: begin
                    if (m_axi_rvalid) begin
                        if (process_readin_counter == 7)
                            process_state <= `STATE_REPLACE_READIN_FINALIZE;
                        else process_readin_counter <= process_readin_counter + 1;
                    end
                end

                `STATE_REPLACE_READIN_FINALIZE: process_state <= `STATE_REPLACE_EXECUTE;

                `STATE_REPLACE_EXECUTE: process_state <= `STATE_NORMAL;

                default: process_state <= `STATE_NORMAL;
            endcase

    assign process_ready_go = process_state == `STATE_NORMAL && process_cache_hit || process_state == `STATE_REPLACE_EXECUTE;
    assign process_working = process_state != `STATE_NORMAL && process_state != `STATE_REPLACE_EXECUTE;

    /* PROCESS-OUTPUT */

    reg [30:0] process_output_branch_target;
    reg [31:0] process_output_addr;
    reg [31:0] process_output_inst;

    assign pc_o            = process_output_addr;
    assign branch_target_o = process_output_branch_target;
    assign inst_o          = process_output_inst;

    // Convert fetch group to inst, if superscalar, output the entire fetch group
    always @(*)
        case (process_output_addr[3:2])
            2'b00: process_output_inst = data_storage_rdata[31:0];
            2'b01: process_output_inst = data_storage_rdata[63:32];
            2'b10: process_output_inst = data_storage_rdata[95:64];
            2'b11: process_output_inst = data_storage_rdata[127:96];
        endcase

    always @(posedge clk)
        if (rst) begin
            process_output_valid         <= 0;
            process_output_addr          <= 0;
            process_output_branch_target <= 0;
        end else if (pipeline_flush) process_output_valid <= 0;
        else if (process_output_accept_ready) begin
            process_output_valid <= process_product_ready;
            if (process_product_ready) begin
                process_output_addr          <= query_process_addr;
                process_output_branch_target <= query_process_branch_target;
            end
        end

endmodule
