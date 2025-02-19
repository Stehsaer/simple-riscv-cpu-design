// New data cache design draft

module Count_population_4bits (
    input  wire [3:0] data,
    output reg  [1:0] population
);

    (* parallel_case *) always @(*)
        case (data)
            4'b0000: population = 2'b00;
            4'b0001: population = 2'b01;
            4'b0010: population = 2'b01;
            4'b0011: population = 2'b10;
            4'b0100: population = 2'b01;
            4'b0101: population = 2'b10;
            4'b0110: population = 2'b10;
            4'b0111: population = 2'b11;
            4'b1000: population = 2'b01;
            4'b1001: population = 2'b10;
            4'b1010: population = 2'b10;
            4'b1011: population = 2'b11;
            4'b1100: population = 2'b10;
            4'b1101: population = 2'b11;
            4'b1110: population = 2'b11;
            4'b1111: population = 2'b11;
        endcase

endmodule

module find_min (
    input  wire [1:0] i0,
    input  wire [1:0] i1,
    input  wire [1:0] i2,
    input  wire [1:0] i3,
    output wire [1:0] o
);

    wire [1:0] grp0_val, grp0_idx;
    wire [1:0] grp1_val, grp1_idx;

    assign {grp0_val, grp0_idx} = (i0 <= i1) ? {i0, 2'd0} : {i1, 2'd1};
    assign {grp1_val, grp1_idx} = (i2 <= i3) ? {i2, 2'd2} : {i3, 2'd3};

    assign o                    = (grp0_val <= grp1_val) ? grp0_idx : grp1_idx;

endmodule


module Lru_find_set (
    input  wire [15:0] lru_matrix,
    output wire [ 1:0] set
);

    wire [1:0] population0, population1, population2, population3;

    Count_population_4bits count0 (
        .data(lru_matrix[3:0]),
        .population(population0)
    );

    Count_population_4bits count1 (
        .data(lru_matrix[7:4]),
        .population(population1)
    );

    Count_population_4bits count2 (
        .data(lru_matrix[11:8]),
        .population(population2)
    );

    Count_population_4bits count3 (
        .data(lru_matrix[15:12]),
        .population(population3)
    );

    find_min find (
        .i0(population0),
        .i1(population1),
        .i2(population2),
        .i3(population3),
        .o (set)
    );

endmodule

module Lru_update (
    input  wire [15:0] original,
    input  wire [ 1:0] set,
    output reg  [15:0] updated
);

    wire [15:0] updated0 = original & 16'b1110_1110_1110_1110 | 16'b0000_0000_0000_1110; // LRU Matrix when set 0 is accessed
    wire [15:0] updated1 = original & 16'b1101_1101_1101_1101 | 16'b0000_0000_1101_0000; // LRU Matrix when set 1 is accessed
    wire [15:0] updated2 = original & 16'b1011_1011_1011_1011 | 16'b0000_1011_0000_0000; // LRU Matrix when set 2 is accessed
    wire [15:0] updated3 = original & 16'b0111_0111_0111_0111 | 16'b0111_0000_0000_0000; // LRU Matrix when set 3 is accessed

    always @(*)
        case (set)
            2'b00: updated = updated0;
            2'b01: updated = updated1;
            2'b10: updated = updated2;
            2'b11: updated = updated3;
        endcase

endmodule


module Data_cache_w32_addr32 (
    input wire m_axi_aclk,
    input wire m_axi_aresetn,

    /* Internal Bus Signals: CPU CORE <=> Cache */

    input wire [29:0] addr,  // Address in WORDS

    input wire wen,
    input wire [31:0] din,
    input wire [3:0] wmask,

    input wire ren,
    output wire rresp,
    output wire [31:0] dout,

    output wire busy,

    input  wire flush_en,
    output wire flush_done,

    /* External AXI Signals: Cache <=> External AXI Device */

    output reg m_axi_awvalid,
    input wire m_axi_awready,
    output reg [31:0] m_axi_awaddr,
    output reg [7:0] m_axi_awlen,
    output reg [3:0] m_axi_awcache,
    output wire [1:0] m_axi_awburst,  // FIXED
    output wire [2:0] m_axi_awsize,  // FIXED
    output wire [0:0] m_axi_awid,  // FIXED
    output wire m_axi_awlock,  // FIXED

    output reg m_axi_wvalid,
    input wire m_axi_wready,
    output reg m_axi_wlast,
    output reg [31:0] m_axi_wdata,
    output reg [3:0] m_axi_wstrb,

    input wire m_axi_bvalid,
    input wire [1:0] m_axi_bresp,
    output reg m_axi_bready,

    output reg m_axi_arvalid,
    input wire m_axi_arready,
    output reg [31:0] m_axi_araddr,
    output reg [7:0] m_axi_arlen,
    output reg [3:0] m_axi_arcache,
    output wire [2:0] m_axi_arburst,  // FIXED
    output wire [0:0] m_axi_arid,  // FIXED
    output wire [2:0] m_axi_arsize,  // FIXED
    output wire m_axi_arlock,  // FIXED

    input wire m_axi_rvalid,
    output reg m_axi_rready,
    input wire [31:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire [0:0] m_axi_rid,
    input wire [1:0] m_axi_rresp
);
    /*===== DESIGN PARAMETERS =====*/
    // -- Total Data Size: 16KB
    // -- Block Size: 32 Words, 128 Bytes
    // -- Associativity: 4
    // -- Internal Data Storage Width: 32 Bits * 4 Sets = 128 bits
    // -- Internal Tag Storage Width: 20*4 bits (Tag) + 1*4 bits (Dirty) + 16 Bits (LRU Matrix) = 100 bits
    // -- Internal Data Storage Depth: 1024
    // -- Internal Tag Storage Depth: 32

    /*===== PHYSICAL ADDRESS =====*/
    // -- [6:0]: Offset inside cache line
    // -- [11:7]: Index of cache line
    // -- [31:12]: Tag

    /*===== DATA STORAGE BITS =====*/
    // -- [31:0]: Data from set 0
    // -- [63:32]: Data from set 1
    // -- [95:64]: Data from set 2
    // -- [127:96]: Data from set 3

    /*===== TAG STORAGE BITS =====*/
    // -- [19:0]: Tag from set 0
    // -- [39:20]: Tag from set 1
    // -- [59:40]: Tag from set 2
    // -- [79:60]: Tag from set 3
    // -- [83:80]: Dirty bits for 4 sets
    // -- [99:84]: LRU Matrix for 4 sets

    /* PARAMETERS */

    parameter PERIPHERAL_BASE_ADDRESS = 32'h0001_0000; // Default: Peripheral Address Starts at 0x1_0000
    parameter PERIPHERAL_ADDRESS_BITS = 16;  // Default: 64KB Peripheral Address Space

    /* AXI FIXED LINES */

    assign m_axi_awburst = 2'b01;
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awid    = 0;
    assign m_axi_awlock  = 1'b0;

    assign m_axi_arburst = 2'b01;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arid    = 0;
    assign m_axi_arlock  = 1'b0;

    /* PIPELINE SIGNALS */

    wire clk = m_axi_aclk;
    wire rstn = m_axi_aresetn;

    // Data in interstage register is valid?
    reg query_process_valid, process_output_valid;
    wire input_query_valid = wen || ren || flush_en;

    // Stage has done processing?
    wire query_ready_go = 1;
    wire process_ready_go;

    // Interstage register accepts new data?
    wire query_process_accept_ready, process_output_accept_ready;
    wire output_external_accept_ready = 1;

    // Stage produces valid data: input data is valid && stage successfully processes data
    wire query_product_ready = query_ready_go && input_query_valid;
    wire process_product_ready = process_ready_go && query_process_valid;

    // Stages accepts new data: stage doesn't hold valid data, or, next stage is ready to accept data and current stage has valid product
    assign process_output_accept_ready = !process_output_valid || output_external_accept_ready;
    assign query_process_accept_ready = !query_process_valid || process_product_ready && process_output_accept_ready;

    assign busy = !query_process_accept_ready;

    /* FUNCTIONS */

    // Unused

    /* STORAGE BLOCKS */

    // -- Valid LUTRAM

    reg [3:0] valid_storage_lutram[0:31];
    reg [3:0] valid_storage_dout;

    reg valid_storage_wen, valid_storage_ren;
    reg [4:0] valid_storage_addr;
    reg [3:0] valid_storage_din;

    integer valid_lutram_i;
    always @(posedge clk) begin
        if (!rstn) begin

            for (valid_lutram_i = 0; valid_lutram_i < 32; valid_lutram_i = valid_lutram_i + 1)
            valid_storage_lutram[valid_lutram_i] <= 4'h0;

            valid_storage_dout <= 4'h0;

        end else begin
            if (valid_storage_wen) valid_storage_lutram[valid_storage_addr] <= valid_storage_din;
            if (valid_storage_ren) valid_storage_dout <= valid_storage_lutram[valid_storage_addr];
        end
    end

    // -- Data BRAM

    reg [9:0] data_storage_waddr, data_storage_raddr;
    reg  [127:0] data_storage_wdata;
    wire [127:0] data_storage_rdata;
    reg data_storage_wen, data_storage_ren;
    reg [15:0] data_storage_wmask;

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

    reg [4:0] tag_storage_waddr, tag_storage_raddr;
    reg  [101:0] tag_storage_wdata;
    wire [101:0] tag_storage_rdata;
    reg tag_storage_wen, tag_storage_ren;

    bram_w102_d32 tag_storage (
        .clka (clk),                // input wire clka
        .ena  (tag_storage_wen),    // input wire ena
        .wea  (tag_storage_wen),    // input wire [0 : 0] wea
        .addra(tag_storage_waddr),  // input wire [4 : 0] addra
        .dina (tag_storage_wdata),  // input wire [101: 0] dina
        .clkb (clk),                // input wire clkb
        .enb  (tag_storage_ren),    // input wire enb
        .addrb(tag_storage_raddr),  // input wire [4 : 0] addrb
        .doutb(tag_storage_rdata)   // output wire [99 : 0] doutb
    );

    /* CHANNELS */

    localparam CHANNEL_NORMAL = 2'b00;
    localparam CHANNEL_REPLACE = 2'b01;
    localparam CHANNEL_PERIPH = 2'b10;
    localparam CHANNEL_FLUSH = 2'b11;

    reg [1:0] axi_channel_state;
    reg [1:0] storage_read_channel_state;
    reg [1:0] storage_write_channel_state;

    // Normal Channel

    wire valid_storage_wen_channel_normal, valid_storage_ren_channel_normal;
    wire [4:0] valid_storage_addr_channel_normal;
    wire [3:0] valid_storage_din_channel_normal;

    wire [9:0] data_storage_waddr_channel_normal, data_storage_raddr_channel_normal;
    reg [127:0] data_storage_wdata_channel_normal;
    wire data_storage_wen_channel_normal, data_storage_ren_channel_normal;
    reg [15:0] data_storage_wmask_channel_normal;

    wire [4:0] tag_storage_waddr_channel_normal, tag_storage_raddr_channel_normal;
    wire [101:0] tag_storage_wdata_channel_normal;
    wire tag_storage_wen_channel_normal, tag_storage_ren_channel_normal;

    wire awvalid_channel_normal;
    wire [31:0] awaddr_channel_normal;
    wire [7:0] awlen_channel_normal;
    wire [3:0] awcache_channel_normal;

    wire wvalid_channel_normal;
    wire wlast_channel_normal;
    wire [31:0] wdata_channel_normal;
    wire [3:0] wstrb_channel_normal;

    wire bready_channel_normal;

    wire arvalid_channel_normal;
    wire [31:0] araddr_channel_normal;
    wire [7:0] arlen_channel_normal;
    wire [3:0] arcache_channel_normal;

    wire rready_channel_normal;

    // Replace Channel

    wire valid_storage_wen_channel_replace, valid_storage_ren_channel_replace;
    wire [4:0] valid_storage_addr_channel_replace;
    wire [3:0] valid_storage_din_channel_replace;

    wire [9:0] data_storage_waddr_channel_replace, data_storage_raddr_channel_replace;
    reg [127:0] data_storage_wdata_channel_replace;
    wire data_storage_wen_channel_replace, data_storage_ren_channel_replace;
    reg [15:0] data_storage_wmask_channel_replace;

    wire [4:0] tag_storage_waddr_channel_replace, tag_storage_raddr_channel_replace;
    wire [101:0] tag_storage_wdata_channel_replace;
    wire tag_storage_wen_channel_replace, tag_storage_ren_channel_replace;

    wire awvalid_channel_replace;
    reg [31:0] awaddr_channel_replace;
    wire [7:0] awlen_channel_replace;
    wire [3:0] awcache_channel_replace;

    wire wvalid_channel_replace;
    wire wlast_channel_replace;
    wire [31:0] wdata_channel_replace;
    wire [3:0] wstrb_channel_replace;

    wire bready_channel_replace;

    wire arvalid_channel_replace;
    wire [31:0] araddr_channel_replace;
    wire [7:0] arlen_channel_replace;
    wire [3:0] arcache_channel_replace;

    wire rready_channel_replace;

    // Peripheral Channel

    wire valid_storage_wen_channel_periph, valid_storage_ren_channel_periph;
    wire [4:0] valid_storage_addr_channel_periph;
    wire [3:0] valid_storage_din_channel_periph;

    wire [9:0] data_storage_waddr_channel_periph, data_storage_raddr_channel_periph;
    wire [127:0] data_storage_wdata_channel_periph;
    wire data_storage_wen_channel_periph, data_storage_ren_channel_periph;
    wire [15:0] data_storage_wmask_channel_periph;

    wire [4:0] tag_storage_waddr_channel_periph, tag_storage_raddr_channel_periph;
    wire [101:0] tag_storage_wdata_channel_periph;
    wire tag_storage_wen_channel_periph, tag_storage_ren_channel_periph;

    wire awvalid_channel_periph;
    wire [31:0] awaddr_channel_periph;
    wire [7:0] awlen_channel_periph;
    wire [3:0] awcache_channel_periph;

    wire wvalid_channel_periph;
    wire wlast_channel_periph;
    wire [31:0] wdata_channel_periph;
    wire [3:0] wstrb_channel_periph;

    wire bready_channel_periph;

    wire arvalid_channel_periph;
    wire [31:0] araddr_channel_periph;
    wire [7:0] arlen_channel_periph;
    wire [3:0] arcache_channel_periph;

    wire rready_channel_periph;

    // Flush Channel

    wire valid_storage_wen_channel_flush, valid_storage_ren_channel_flush;
    wire [4:0] valid_storage_addr_channel_flush;
    wire [3:0] valid_storage_din_channel_flush;

    wire [9:0] data_storage_waddr_channel_flush, data_storage_raddr_channel_flush;
    wire [127:0] data_storage_wdata_channel_flush;
    wire data_storage_wen_channel_flush, data_storage_ren_channel_flush;
    wire [15:0] data_storage_wmask_channel_flush;

    wire [4:0] tag_storage_waddr_channel_flush, tag_storage_raddr_channel_flush;
    wire [101:0] tag_storage_wdata_channel_flush;
    wire tag_storage_wen_channel_flush, tag_storage_ren_channel_flush;

    wire awvalid_channel_flush;
    wire [31:0] awaddr_channel_flush;
    wire [7:0] awlen_channel_flush;
    wire [3:0] awcache_channel_flush;

    wire wvalid_channel_flush;
    wire wlast_channel_flush;
    reg [31:0] wdata_channel_flush;
    wire [3:0] wstrb_channel_flush;

    wire bready_channel_flush;

    wire arvalid_channel_flush;
    wire [31:0] araddr_channel_flush;
    wire [7:0] arlen_channel_flush;
    wire [3:0] arcache_channel_flush;

    wire rready_channel_flush;

    always @(*) begin
        case (storage_read_channel_state)
            CHANNEL_NORMAL: begin
                valid_storage_ren  = valid_storage_ren_channel_normal;
                valid_storage_addr = valid_storage_addr_channel_normal;

                data_storage_raddr = data_storage_raddr_channel_normal;
                data_storage_ren   = data_storage_ren_channel_normal;

                tag_storage_raddr  = tag_storage_raddr_channel_normal;
                tag_storage_ren    = tag_storage_ren_channel_normal;
            end
            CHANNEL_REPLACE: begin
                valid_storage_ren  = valid_storage_ren_channel_replace;
                valid_storage_addr = valid_storage_addr_channel_replace;

                data_storage_raddr = data_storage_raddr_channel_replace;
                data_storage_ren   = data_storage_ren_channel_replace;

                tag_storage_raddr  = tag_storage_raddr_channel_replace;
                tag_storage_ren    = tag_storage_ren_channel_replace;
            end
            CHANNEL_PERIPH: begin
                valid_storage_ren  = valid_storage_ren_channel_periph;
                valid_storage_addr = valid_storage_addr_channel_periph;

                data_storage_raddr = data_storage_raddr_channel_periph;
                data_storage_ren   = data_storage_ren_channel_periph;

                tag_storage_raddr  = tag_storage_raddr_channel_periph;
                tag_storage_ren    = tag_storage_ren_channel_periph;
            end
            CHANNEL_FLUSH: begin
                valid_storage_ren  = valid_storage_ren_channel_flush;
                valid_storage_addr = valid_storage_addr_channel_flush;

                data_storage_raddr = data_storage_raddr_channel_flush;
                data_storage_ren   = data_storage_ren_channel_flush;

                tag_storage_raddr  = tag_storage_raddr_channel_flush;
                tag_storage_ren    = tag_storage_ren_channel_flush;
            end
        endcase

        case (storage_write_channel_state)
            CHANNEL_NORMAL: begin
                valid_storage_wen  = valid_storage_wen_channel_normal;
                valid_storage_din  = valid_storage_din_channel_normal;

                data_storage_waddr = data_storage_waddr_channel_normal;
                data_storage_wdata = data_storage_wdata_channel_normal;
                data_storage_wen   = data_storage_wen_channel_normal;
                data_storage_wmask = data_storage_wmask_channel_normal;

                tag_storage_waddr  = tag_storage_waddr_channel_normal;
                tag_storage_wdata  = tag_storage_wdata_channel_normal;
                tag_storage_wen    = tag_storage_wen_channel_normal;
            end
            CHANNEL_REPLACE: begin
                valid_storage_wen  = valid_storage_wen_channel_replace;
                valid_storage_din  = valid_storage_din_channel_replace;

                data_storage_waddr = data_storage_waddr_channel_replace;
                data_storage_wdata = data_storage_wdata_channel_replace;
                data_storage_wen   = data_storage_wen_channel_replace;
                data_storage_wmask = data_storage_wmask_channel_replace;

                tag_storage_waddr  = tag_storage_waddr_channel_replace;
                tag_storage_wdata  = tag_storage_wdata_channel_replace;
                tag_storage_wen    = tag_storage_wen_channel_replace;
            end
            CHANNEL_PERIPH: begin
                valid_storage_wen  = valid_storage_wen_channel_periph;
                valid_storage_din  = valid_storage_din_channel_periph;

                data_storage_waddr = data_storage_waddr_channel_periph;
                data_storage_wdata = data_storage_wdata_channel_periph;
                data_storage_wen   = data_storage_wen_channel_periph;
                data_storage_wmask = data_storage_wmask_channel_periph;

                tag_storage_waddr  = tag_storage_waddr_channel_periph;
                tag_storage_wdata  = tag_storage_wdata_channel_periph;
                tag_storage_wen    = tag_storage_wen_channel_periph;
            end
            CHANNEL_FLUSH: begin
                valid_storage_wen  = valid_storage_wen_channel_flush;
                valid_storage_din  = valid_storage_din_channel_flush;

                data_storage_waddr = data_storage_waddr_channel_flush;
                data_storage_wdata = data_storage_wdata_channel_flush;
                data_storage_wen   = data_storage_wen_channel_flush;
                data_storage_wmask = data_storage_wmask_channel_flush;

                tag_storage_waddr  = tag_storage_waddr_channel_flush;
                tag_storage_wdata  = tag_storage_wdata_channel_flush;
                tag_storage_wen    = tag_storage_wen_channel_flush;
            end
        endcase

        case (axi_channel_state)
            CHANNEL_NORMAL: begin

                m_axi_awvalid = awvalid_channel_normal;
                m_axi_awaddr  = awaddr_channel_normal;
                m_axi_awlen   = awlen_channel_normal;
                m_axi_awcache = awcache_channel_normal;

                m_axi_wvalid  = wvalid_channel_normal;
                m_axi_wlast   = wlast_channel_normal;
                m_axi_wdata   = wdata_channel_normal;
                m_axi_wstrb   = wstrb_channel_normal;

                m_axi_bready  = bready_channel_normal;

                m_axi_arvalid = arvalid_channel_normal;
                m_axi_araddr  = araddr_channel_normal;
                m_axi_arlen   = arlen_channel_normal;
                m_axi_arcache = arcache_channel_normal;

                m_axi_rready  = rready_channel_normal;
            end

            CHANNEL_REPLACE: begin

                m_axi_awvalid = awvalid_channel_replace;
                m_axi_awaddr  = awaddr_channel_replace;
                m_axi_awlen   = awlen_channel_replace;
                m_axi_awcache = awcache_channel_replace;

                m_axi_wvalid  = wvalid_channel_replace;
                m_axi_wlast   = wlast_channel_replace;
                m_axi_wdata   = wdata_channel_replace;
                m_axi_wstrb   = wstrb_channel_replace;

                m_axi_bready  = bready_channel_replace;

                m_axi_arvalid = arvalid_channel_replace;
                m_axi_araddr  = araddr_channel_replace;
                m_axi_arlen   = arlen_channel_replace;
                m_axi_arcache = arcache_channel_replace;

                m_axi_rready  = rready_channel_replace;
            end

            CHANNEL_PERIPH: begin
                m_axi_awvalid = awvalid_channel_periph;
                m_axi_awaddr  = awaddr_channel_periph;
                m_axi_awlen   = awlen_channel_periph;
                m_axi_awcache = awcache_channel_periph;

                m_axi_wvalid  = wvalid_channel_periph;
                m_axi_wlast   = wlast_channel_periph;
                m_axi_wdata   = wdata_channel_periph;
                m_axi_wstrb   = wstrb_channel_periph;

                m_axi_bready  = bready_channel_periph;

                m_axi_arvalid = arvalid_channel_periph;
                m_axi_araddr  = araddr_channel_periph;
                m_axi_arlen   = arlen_channel_periph;
                m_axi_arcache = arcache_channel_periph;

                m_axi_rready  = rready_channel_periph;
            end

            CHANNEL_FLUSH: begin

                m_axi_awvalid = awvalid_channel_flush;
                m_axi_awaddr  = awaddr_channel_flush;
                m_axi_awlen   = awlen_channel_flush;
                m_axi_awcache = awcache_channel_flush;

                m_axi_wvalid  = wvalid_channel_flush;
                m_axi_wlast   = wlast_channel_flush;
                m_axi_wdata   = wdata_channel_flush;
                m_axi_wstrb   = wstrb_channel_flush;

                m_axi_bready  = bready_channel_flush;

                m_axi_arvalid = arvalid_channel_flush;
                m_axi_araddr  = araddr_channel_flush;
                m_axi_arlen   = arlen_channel_flush;
                m_axi_arcache = arcache_channel_flush;

                m_axi_rready  = rready_channel_flush;
            end
        endcase
    end

    /* INPUT-QUERY */

    wire [31:0] input_query_addr = {addr, 2'b00}, input_query_wdata = din;
    wire input_query_rreq = ren, input_query_wreq = wen, input_query_flushreq = flush_en;
    wire [3:0] input_query_wmask = wmask;

    /* QUERY */

    wire [4:0] query_index = input_query_addr[11:7];
    wire [4:0] query_word_offset = input_query_addr[6:2];

    assign valid_storage_addr_channel_normal = query_index;
    assign data_storage_raddr_channel_normal = {query_index, query_word_offset};
    assign tag_storage_raddr_channel_normal  = query_index;

    wire query_storage_ren = query_process_accept_ready && query_product_ready;

    assign valid_storage_ren_channel_normal = query_storage_ren;
    assign data_storage_ren_channel_normal  = query_storage_ren;
    assign tag_storage_ren_channel_normal   = query_storage_ren;

    /* QUERY-PROCESS */

    reg [31:0] query_process_addr, query_process_wdata;
    reg [3:0] query_process_wmask;
    reg query_process_rreq, query_process_wreq, query_process_flushreq;

    always @(posedge m_axi_aclk) begin
        if (!m_axi_aresetn) begin
            query_process_valid    <= 0;
            query_process_addr     <= 0;
            query_process_rreq     <= 0;
            query_process_wreq     <= 0;
            query_process_wdata    <= 0;
            query_process_wmask    <= 0;
            query_process_flushreq <= 0;
        end else if (query_process_accept_ready) begin
            query_process_valid <= input_query_valid;
            if (query_product_ready) begin
                query_process_addr     <= input_query_addr;
                query_process_rreq     <= input_query_rreq;
                query_process_wreq     <= input_query_wreq;
                query_process_wdata    <= input_query_wdata;
                query_process_wmask    <= input_query_wmask;
                query_process_flushreq <= input_query_flushreq;
            end
        end
    end

    /* PROCESS */

    // Some combinational logic

    wire [4:0] process_index = query_process_addr[11:7];
    wire [4:0] process_word_offset = query_process_addr[6:2];
    wire [19:0] process_tag = query_process_addr[31:12];

    wire [19:0] process_queried_tag_set0 = tag_storage_rdata[19:0];
    wire [19:0] process_queried_tag_set1 = tag_storage_rdata[39:20];
    wire [19:0] process_queried_tag_set2 = tag_storage_rdata[59:40];
    wire [19:0] process_queried_tag_set3 = tag_storage_rdata[79:60];

    wire [3:0] process_queried_dirty = tag_storage_rdata[83:80];
    wire [15:0] process_queried_lru_matrix = tag_storage_rdata[99:84];
    wire [1:0] process_lru_selected_set = tag_storage_rdata[101:100];
    wire [3:0] process_queried_valid = valid_storage_dout;

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

    wire process_is_periph = query_process_addr[31:PERIPHERAL_ADDRESS_BITS] == PERIPHERAL_BASE_ADDRESS[31:PERIPHERAL_ADDRESS_BITS];

    wire process_cache_hit_not_periph;

    // LRU Computation

    wire [15:0] process_cache_hit_updated_lru_matrix_list[0:3];
    wire [15:0] process_cache_not_hit_updated_lru_matrix;

    wire [15:0] process_cache_hit_updated_lru_matrix = process_cache_hit_updated_lru_matrix_list[process_hit_set];

    wire [1:0] process_cache_hit_parsed_lru_set[0:3];
    wire [1:0] process_cache_not_hit_parsed_lru_set;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin
            Lru_update process_cache_hit_lru_matrix_update (
                .original(process_queried_lru_matrix),
                .set(i),
                .updated(process_cache_hit_updated_lru_matrix_list[i])
            );
            Lru_find_set lru_matrix_parser (
                .lru_matrix(process_cache_hit_updated_lru_matrix_list[i]),
                .set(process_cache_hit_parsed_lru_set[i])
            );
        end
    endgenerate

    Lru_update process_cache_not_hit_lru_matrix_update (
        .original(process_queried_lru_matrix),
        .set(process_lru_selected_set),
        .updated(process_cache_not_hit_updated_lru_matrix)
    );

    Lru_find_set lru_matrix_parser (
        .lru_matrix(process_cache_not_hit_updated_lru_matrix),
        .set(process_cache_not_hit_parsed_lru_set)
    );

    reg [1:0] process_next_lru_selected_set;

    always @(*) begin
        if (process_cache_hit)
            process_next_lru_selected_set = process_cache_hit_parsed_lru_set[process_hit_set];
        else process_next_lru_selected_set = process_cache_not_hit_parsed_lru_set;
    end

    // State machine

    localparam STATE_NORMAL = 0;

    localparam STATE_REPLACE_WRITEBACK_SEND_ADDRESS = 1;  // Send writeback address & Read word 0 from storage
    localparam STATE_REPLACE_WRITEBACK_SEND_DATA = 2; // Send writeback data & Read word (i+1) from storage
    localparam STATE_REPLACE_WRITEBACK_RECEIVE_RESPONSE = 3;  // Receive writeback response
    localparam STATE_REPLACE_READIN_SEND_ADDRESS = 4;  // Send readin address
    localparam STATE_REPLACE_READIN_RECEIVE_DATA = 5; // Receive readin data & Write last received word (i-1) to storage
    localparam STATE_REPLACE_READIN_FINALIZE = 6;  // Finalize readin: wait for last word to be written
    localparam STATE_REPLACE_EXECUTE = 7;  // Execute the original request (Read or Write)

    localparam STATE_PERIPH_WRITE_SEND_ADDRESS = 8;  // Send write address
    localparam STATE_PERIPH_WRITE_SEND_DATA = 9;  // Send write data
    localparam STATE_PERIPH_WRITE_RECEIVE_RESPONSE = 10;  // Receive write response
    localparam STATE_PERIPH_WRITE_FINALIZE = 11;  // Finalize write

    localparam STATE_PERIPH_READ_SEND_ADDRESS = 12;  // Send read address
    localparam STATE_PERIPH_READ_RECEIVE_DATA = 13;  // Receive read data
    localparam STATE_PERIPH_READ_FINALIZE = 14;  // Finalize read

    localparam STATE_FLUSH_READ_TAG = 15;  // Read tag
    localparam STATE_FLUSH_COMPARE_TAG = 16;  // Receive tag and compare (dirty and valid)
    localparam STATE_FLUSH_SEND_ADDRESS = 17;  // Send Address & Read word 0 from storage
    localparam STATE_FLUSH_SEND_DATA = 18;  // Send flush data & Read word (i+1) from storage
    localparam STATE_FLUSH_RECEIVE_RESPONSE = 19;  // Receive response
    localparam STATE_FLUSH_FINALIZE = 20;  // Finalize flush

    reg [ 4:0] replace_counter;  // Tracks the current progress of replacement (in words)

    reg [31:0] periph_buffer;  // Temporarily stores received data

    reg [ 4:0] flush_inner_counter;  // Tracks how many words have been flushed in current line
    reg [ 6:0] flush_outer_counter;  // Tracks how many cache lines have been flushed

    reg [ 4:0] process_state;

    always @(*)
        case (process_state)
            // Normal
            STATE_NORMAL: begin
                axi_channel_state           = CHANNEL_NORMAL;
                storage_read_channel_state  = CHANNEL_NORMAL;
                storage_write_channel_state = CHANNEL_NORMAL;
            end

            // Replace
            STATE_REPLACE_WRITEBACK_SEND_ADDRESS, 
            STATE_REPLACE_WRITEBACK_SEND_DATA, 
            STATE_REPLACE_WRITEBACK_RECEIVE_RESPONSE, 
            STATE_REPLACE_READIN_SEND_ADDRESS, 
            STATE_REPLACE_READIN_RECEIVE_DATA, 
            STATE_REPLACE_READIN_FINALIZE:
            begin
                axi_channel_state           = CHANNEL_REPLACE;
                storage_read_channel_state  = CHANNEL_REPLACE;
                storage_write_channel_state = CHANNEL_REPLACE;
            end

            // Execute stage: storage_write still belongs to replace, storage_read belongs to normal in order to resume the pipeline
            STATE_REPLACE_EXECUTE: begin
                axi_channel_state           = CHANNEL_NORMAL;
                storage_read_channel_state  = CHANNEL_NORMAL;
                storage_write_channel_state = CHANNEL_REPLACE;
            end

            // Periph
            STATE_PERIPH_WRITE_SEND_ADDRESS, 
            STATE_PERIPH_WRITE_SEND_DATA, 
            STATE_PERIPH_WRITE_RECEIVE_RESPONSE, 
            STATE_PERIPH_READ_SEND_ADDRESS, 
            STATE_PERIPH_READ_RECEIVE_DATA:
            begin
                axi_channel_state           = CHANNEL_PERIPH;
                storage_read_channel_state  = CHANNEL_PERIPH;
                storage_write_channel_state = CHANNEL_PERIPH;
            end

            STATE_PERIPH_READ_FINALIZE: begin
                axi_channel_state           = CHANNEL_NORMAL;
                storage_read_channel_state  = CHANNEL_NORMAL;
                storage_write_channel_state = CHANNEL_NORMAL;
            end

            // Flush
            STATE_FLUSH_READ_TAG, 
            STATE_FLUSH_COMPARE_TAG, 
            STATE_FLUSH_SEND_ADDRESS, 
            STATE_FLUSH_SEND_DATA, 
            STATE_FLUSH_RECEIVE_RESPONSE:
            begin
                axi_channel_state           = CHANNEL_FLUSH;
                storage_read_channel_state  = CHANNEL_FLUSH;
                storage_write_channel_state = CHANNEL_FLUSH;
            end

            STATE_FLUSH_FINALIZE: begin
                axi_channel_state           = CHANNEL_NORMAL;
                storage_read_channel_state  = CHANNEL_NORMAL;
                storage_write_channel_state = CHANNEL_NORMAL;
            end

            default: begin
                axi_channel_state           = CHANNEL_NORMAL;
                storage_read_channel_state  = CHANNEL_NORMAL;
                storage_write_channel_state = CHANNEL_NORMAL;
            end
        endcase

    always @(posedge clk) begin
        if (!rstn) begin
            process_state       <= STATE_NORMAL;

            // Other variables
            replace_counter     <= 0;
            flush_outer_counter <= 0;
            flush_inner_counter <= 0;
            periph_buffer       <= 0;
        end else
            case (process_state)

                STATE_NORMAL: begin
                    if (query_process_valid)
                        if (query_process_flushreq)
                            process_state <= STATE_FLUSH_READ_TAG;  // Goto flush state
                        else if (query_process_rreq | query_process_wreq) begin

                            if (process_is_periph) begin
                                if (query_process_wreq) begin
                                    process_state <= STATE_PERIPH_WRITE_SEND_ADDRESS;
                                end else begin
                                    process_state <= STATE_PERIPH_READ_SEND_ADDRESS;
                                end
                            end else if (!process_cache_hit) begin
                                replace_counter <= 0;

                                if (process_queried_dirty[process_lru_selected_set] && process_queried_valid[process_lru_selected_set]) begin // Nees writeback
                                    process_state <= STATE_REPLACE_WRITEBACK_SEND_ADDRESS;
                                end else begin
                                    process_state <= STATE_REPLACE_READIN_SEND_ADDRESS;
                                end
                            end
                        end
                end

                STATE_REPLACE_WRITEBACK_SEND_ADDRESS: begin
                    if (m_axi_awready) begin
                        process_state <= STATE_REPLACE_WRITEBACK_SEND_DATA;
                    end
                end

                STATE_REPLACE_WRITEBACK_SEND_DATA: begin
                    if (m_axi_wready) begin
                        if (replace_counter == 31) begin
                            process_state   <= STATE_REPLACE_WRITEBACK_RECEIVE_RESPONSE;
                            replace_counter <= 0;
                        end else begin
                            replace_counter <= replace_counter + 1;
                        end
                    end
                end

                STATE_REPLACE_WRITEBACK_RECEIVE_RESPONSE: begin
                    if (m_axi_bvalid) begin
                        process_state <= STATE_REPLACE_READIN_SEND_ADDRESS;
                    end
                end

                STATE_REPLACE_READIN_SEND_ADDRESS: begin
                    if (m_axi_arready) begin
                        process_state <= STATE_REPLACE_READIN_RECEIVE_DATA;
                    end
                end

                STATE_REPLACE_READIN_RECEIVE_DATA: begin
                    if (m_axi_rvalid) begin
                        if (replace_counter == 31) begin
                            process_state   <= STATE_REPLACE_READIN_FINALIZE;
                            replace_counter <= 0;
                        end else begin
                            replace_counter <= replace_counter + 1;
                        end
                    end
                end

                STATE_REPLACE_READIN_FINALIZE: begin
                    process_state <= STATE_REPLACE_EXECUTE;
                end

                STATE_REPLACE_EXECUTE: begin
                    process_state <= STATE_NORMAL;
                end

                STATE_PERIPH_WRITE_SEND_ADDRESS: begin
                    if (m_axi_awready) begin
                        process_state <= STATE_PERIPH_WRITE_SEND_DATA;
                    end
                end

                STATE_PERIPH_WRITE_SEND_DATA: begin
                    if (m_axi_wready) begin
                        process_state <= STATE_PERIPH_WRITE_RECEIVE_RESPONSE;
                    end
                end

                STATE_PERIPH_WRITE_RECEIVE_RESPONSE: begin
                    if (m_axi_bvalid) begin
                        process_state <= STATE_PERIPH_WRITE_FINALIZE;
                    end
                end

                STATE_PERIPH_READ_SEND_ADDRESS: begin
                    if (m_axi_arready) begin
                        process_state <= STATE_PERIPH_READ_RECEIVE_DATA;
                    end
                end

                STATE_PERIPH_READ_RECEIVE_DATA: begin
                    if (m_axi_rvalid) begin
                        process_state <= STATE_PERIPH_READ_FINALIZE;
                        periph_buffer <= m_axi_rdata;
                    end
                end

                STATE_PERIPH_WRITE_FINALIZE, STATE_PERIPH_READ_FINALIZE: begin
                    process_state <= STATE_NORMAL;
                end

                STATE_FLUSH_READ_TAG: begin
                    process_state <= STATE_FLUSH_COMPARE_TAG;
                end

                STATE_FLUSH_COMPARE_TAG: begin
                    if (flush_outer_counter == 127) begin
                        process_state <= STATE_FLUSH_FINALIZE;
                    end else if (process_queried_valid[flush_outer_counter[1:0]] && process_queried_dirty[flush_outer_counter[1:0]]) begin
                        flush_inner_counter <= 0;
                        process_state       <= STATE_FLUSH_SEND_ADDRESS;
                    end else begin
                        flush_outer_counter <= flush_outer_counter + 1;
                        process_state       <= STATE_FLUSH_READ_TAG;
                    end
                end

                STATE_FLUSH_SEND_ADDRESS: begin
                    if (m_axi_awready) begin
                        process_state <= STATE_FLUSH_SEND_DATA;
                    end
                end

                STATE_FLUSH_SEND_DATA: begin
                    if (m_axi_wready) begin
                        if (flush_inner_counter == 31) begin
                            process_state <= STATE_FLUSH_RECEIVE_RESPONSE;
                        end else begin
                            flush_inner_counter <= flush_inner_counter + 1;
                        end
                    end
                end

                STATE_FLUSH_RECEIVE_RESPONSE: begin
                    if (m_axi_bvalid) begin
                        if (flush_outer_counter == 127) begin
                            process_state <= STATE_FLUSH_FINALIZE;
                        end else begin
                            flush_outer_counter <= flush_outer_counter + 1;
                            process_state       <= STATE_FLUSH_READ_TAG;
                        end
                    end
                end

                STATE_FLUSH_FINALIZE: begin
                    process_state       <= STATE_NORMAL;
                    flush_outer_counter <= 0;
                    flush_inner_counter <= 0;
                end

                default: process_state <= STATE_NORMAL;

            endcase
    end

    // -- Normal channel

    assign process_cache_hit_not_periph = 
        process_state == STATE_NORMAL && 
        !query_process_flushreq && 
        (query_process_rreq | query_process_wreq) && 
        process_cache_hit && 
        !process_is_periph;

    assign valid_storage_wen_channel_normal = 0;  // Dont need to writein valid when hit
    assign data_storage_wen_channel_normal = process_cache_hit_not_periph && query_process_wreq; // Writein data when hit and write requested
    assign tag_storage_wen_channel_normal = process_cache_hit_not_periph && query_process_wreq;  // Writein tag when hit and write requested (modify dirty bit)

    assign data_storage_waddr_channel_normal = {process_index, process_word_offset};
    assign tag_storage_waddr_channel_normal = process_index;

    assign valid_storage_din_channel_normal = 0;

    assign tag_storage_wdata_channel_normal = {
        process_next_lru_selected_set,
        process_cache_hit_updated_lru_matrix,
        process_queried_dirty | ({3'b000, query_process_wreq} << process_hit_set),
        process_queried_tag_set3,
        process_queried_tag_set2,
        process_queried_tag_set1,
        process_queried_tag_set0
    };

    assign awvalid_channel_normal = 1'b0;
    assign awaddr_channel_normal = 32'b0;
    assign awlen_channel_normal = 8'b0;
    assign awcache_channel_normal = 4'b0;

    assign wvalid_channel_normal = 1'b0;
    assign wlast_channel_normal = 1'b0;
    assign wdata_channel_normal = 32'b0;
    assign wstrb_channel_normal = 4'b0;

    assign bready_channel_normal = 1'b0;

    assign arvalid_channel_normal = 1'b0;
    assign araddr_channel_normal = 32'b0;
    assign arlen_channel_normal = 8'b0;
    assign arcache_channel_normal = 4'b0;

    assign rready_channel_normal = 1'b0;

    reg [31:0] process_product_data_channel_normal;

    always @(*)
        case (process_hit_set)
            0: begin
                data_storage_wdata_channel_normal   = {96'b0, query_process_wdata};
                data_storage_wmask_channel_normal   = {12'b0, query_process_wmask};
                process_product_data_channel_normal = data_storage_rdata[31:0];
            end
            1: begin
                data_storage_wdata_channel_normal   = {64'b0, query_process_wdata, 32'b0};
                data_storage_wmask_channel_normal   = {8'b0, query_process_wmask, 4'b0};
                process_product_data_channel_normal = data_storage_rdata[63:32];
            end
            2: begin
                data_storage_wdata_channel_normal   = {32'b0, query_process_wdata, 64'b0};
                data_storage_wmask_channel_normal   = {4'b0, query_process_wmask, 8'b0};
                process_product_data_channel_normal = data_storage_rdata[95:64];
            end
            3: begin
                data_storage_wdata_channel_normal   = {query_process_wdata, 96'b0};
                data_storage_wmask_channel_normal   = {query_process_wmask, 12'b0};
                process_product_data_channel_normal = data_storage_rdata[127:96];
            end
        endcase

    // -- Replace channel

    assign valid_storage_wen_channel_replace = process_state == STATE_REPLACE_READIN_FINALIZE;
    assign valid_storage_ren_channel_replace = 0;
    assign valid_storage_din_channel_replace = valid_storage_dout | (4'b0001 << process_lru_selected_set); // Set corresponding valid bit to 1
    assign valid_storage_addr_channel_replace = process_index;

    assign data_storage_wen_channel_replace = m_axi_rvalid && process_state == STATE_REPLACE_READIN_RECEIVE_DATA || process_state == STATE_REPLACE_EXECUTE && query_process_wreq;
    assign data_storage_ren_channel_replace = 
        process_state == STATE_REPLACE_WRITEBACK_SEND_ADDRESS && m_axi_awready || 
        process_state == STATE_REPLACE_WRITEBACK_SEND_DATA && m_axi_wready || 
        process_state == STATE_REPLACE_READIN_FINALIZE;

    wire [4:0] replace_counter_next = replace_counter + 1;

    assign data_storage_waddr_channel_replace = 
        process_state == STATE_REPLACE_EXECUTE ? {process_index, process_word_offset} : {process_index, replace_counter};

    assign data_storage_raddr_channel_replace = 
        process_state == STATE_REPLACE_READIN_FINALIZE ? {process_index, process_word_offset} : 
        process_state == STATE_REPLACE_WRITEBACK_SEND_ADDRESS ? {process_index, 5'b0} : 
        {process_index, replace_counter_next};

    always @(*)
        if (process_state == STATE_REPLACE_EXECUTE) begin
            case (process_lru_selected_set)
                0: begin
                    data_storage_wdata_channel_replace = {96'b0, query_process_wdata};
                    data_storage_wmask_channel_replace = {12'b0, query_process_wmask};
                end
                1: begin
                    data_storage_wdata_channel_replace = {64'b0, query_process_wdata, 32'b0};
                    data_storage_wmask_channel_replace = {8'b0, query_process_wmask, 4'b0};
                end
                2: begin
                    data_storage_wdata_channel_replace = {32'b0, query_process_wdata, 64'b0};
                    data_storage_wmask_channel_replace = {4'b0, query_process_wmask, 8'b0};
                end
                3: begin
                    data_storage_wdata_channel_replace = {query_process_wdata, 96'b0};
                    data_storage_wmask_channel_replace = {query_process_wmask, 12'b0};
                end
            endcase
        end else
            case (process_lru_selected_set)
                0: begin
                    data_storage_wdata_channel_replace = {96'b0, m_axi_rdata};
                    data_storage_wmask_channel_replace = 16'h000F;
                end
                1: begin
                    data_storage_wdata_channel_replace = {64'b0, m_axi_rdata, 32'b0};
                    data_storage_wmask_channel_replace = 16'h00F0;
                end
                2: begin
                    data_storage_wdata_channel_replace = {32'b0, m_axi_rdata, 64'b0};
                    data_storage_wmask_channel_replace = 16'h0F00;
                end
                3: begin
                    data_storage_wdata_channel_replace = {m_axi_rdata, 96'b0};
                    data_storage_wmask_channel_replace = 16'hF000;
                end
            endcase

    assign tag_storage_wen_channel_replace = process_state == STATE_REPLACE_READIN_FINALIZE;
    assign tag_storage_ren_channel_replace = 0;
    assign tag_storage_wdata_channel_replace = {
        process_next_lru_selected_set,
        process_cache_not_hit_updated_lru_matrix,
        process_queried_dirty | ({3'b000, query_process_wreq} << process_lru_selected_set),
        process_lru_selected_set == 3 ? process_tag : process_queried_tag_set3,
        process_lru_selected_set == 2 ? process_tag : process_queried_tag_set2,
        process_lru_selected_set == 1 ? process_tag : process_queried_tag_set1,
        process_lru_selected_set == 0 ? process_tag : process_queried_tag_set0
    };
    assign tag_storage_waddr_channel_replace = process_index;
    assign tag_storage_raddr_channel_replace = 0;

    reg [31:0] process_product_data_channel_replace;

    always @(*)
        case (process_lru_selected_set)
            0: process_product_data_channel_replace = data_storage_rdata[31:0];
            1: process_product_data_channel_replace = data_storage_rdata[63:32];
            2: process_product_data_channel_replace = data_storage_rdata[95:64];
            3: process_product_data_channel_replace = data_storage_rdata[127:96];
        endcase

    assign awvalid_channel_replace = process_state == STATE_REPLACE_WRITEBACK_SEND_ADDRESS;

    always @(*)
        case (process_lru_selected_set)
            0: awaddr_channel_replace = {process_queried_tag_set0, process_index, 7'b0};
            1: awaddr_channel_replace = {process_queried_tag_set1, process_index, 7'b0};
            2: awaddr_channel_replace = {process_queried_tag_set2, process_index, 7'b0};
            3: awaddr_channel_replace = {process_queried_tag_set3, process_index, 7'b0};
        endcase

    assign awlen_channel_replace             = 31;  // 32 words
    assign awcache_channel_replace           = 4'b1111;  // Cache-style

    assign wvalid_channel_replace            = process_state == STATE_REPLACE_WRITEBACK_SEND_DATA;
    assign wlast_channel_replace             = replace_counter == 31;
    assign wdata_channel_replace             = process_product_data_channel_replace;
    assign wstrb_channel_replace             = 4'b1111;

    assign bready_channel_replace            = 1'b1;

    assign arvalid_channel_replace           = process_state == STATE_REPLACE_READIN_SEND_ADDRESS;
    assign araddr_channel_replace            = {process_tag, process_index, 7'b0};
    assign arlen_channel_replace             = 31;  // 32 words
    assign arcache_channel_replace           = 4'b1111;  // Cache-style

    assign rready_channel_replace            = 1'b1;

    // -- Peripheral channel

    // No interaction with storage
    assign valid_storage_wen_channel_periph  = 0;
    assign valid_storage_ren_channel_periph  = 0;
    assign valid_storage_din_channel_periph  = 0;
    assign valid_storage_addr_channel_periph = 0;
    assign data_storage_wen_channel_periph   = 0;
    assign data_storage_ren_channel_periph   = 0;
    assign data_storage_waddr_channel_periph = 0;
    assign data_storage_raddr_channel_periph = 0;
    assign tag_storage_wen_channel_periph    = 0;
    assign tag_storage_ren_channel_periph    = 0;
    assign tag_storage_wdata_channel_periph  = 0;
    assign tag_storage_waddr_channel_periph  = 0;

    assign awvalid_channel_periph            = process_state == STATE_PERIPH_WRITE_SEND_ADDRESS;
    assign awaddr_channel_periph             = query_process_addr;
    assign awlen_channel_periph              = 0;  // 1 word
    assign awcache_channel_periph            = 4'b0000;  // Cache
    assign wvalid_channel_periph             = process_state == STATE_PERIPH_WRITE_SEND_DATA;
    assign wlast_channel_periph              = 1'b1;
    assign wdata_channel_periph              = query_process_wdata;
    assign wstrb_channel_periph              = query_process_wmask;
    assign bready_channel_periph             = 1'b1;
    assign arvalid_channel_periph            = process_state == STATE_PERIPH_READ_SEND_ADDRESS;
    assign araddr_channel_periph             = query_process_addr;
    assign arlen_channel_periph              = 0;  // 1 word
    assign arcache_channel_periph            = 4'b0000;  // Peripheral
    assign rready_channel_periph             = 1'b1;

    // -- Flush channel
    assign valid_storage_wen_channel_flush   = 0;
    assign valid_storage_ren_channel_flush   = process_state == STATE_FLUSH_READ_TAG;
    assign valid_storage_din_channel_flush   = 0;
    assign valid_storage_addr_channel_flush  = flush_outer_counter[6:2];

    wire [4:0] flush_inner_counter_next = flush_inner_counter + 1;

    assign data_storage_wen_channel_flush = 0;
    assign data_storage_ren_channel_flush = 
        process_state == STATE_FLUSH_SEND_ADDRESS && m_axi_awready || 
        process_state == STATE_FLUSH_SEND_DATA && m_axi_wready;
    assign data_storage_waddr_channel_flush = 0;
    assign data_storage_raddr_channel_flush = 
        process_state == STATE_FLUSH_SEND_ADDRESS ? {flush_outer_counter[6:2], 5'b0} : 
        {flush_outer_counter[6:2], flush_inner_counter_next};
    assign data_storage_wdata_channel_flush = 0;
    assign data_storage_wmask_channel_flush = 0;

    assign tag_storage_wen_channel_flush = process_state == STATE_FLUSH_COMPARE_TAG;
    assign tag_storage_ren_channel_flush = process_state == STATE_FLUSH_READ_TAG;
    assign tag_storage_waddr_channel_flush = flush_outer_counter[6:2];
    assign tag_storage_raddr_channel_flush = flush_outer_counter[6:2];
    assign tag_storage_wdata_channel_flush = {
        tag_storage_rdata[101:100],  // LRU selection remain unchanged
        tag_storage_rdata[99:84],  // LRU matrix remain unchanged
        tag_storage_rdata[83:80] & (4'b1110 << flush_outer_counter[1:0]),  // Dirty bits set to 0
        tag_storage_rdata[79:0]  // Tags remain unchanged
    };

    reg [19:0] flush_tag;

    always @(*)
        case (flush_outer_counter[1:0])
            2'b00: flush_tag = tag_storage_rdata[19:0];
            2'b01: flush_tag = tag_storage_rdata[39:20];
            2'b10: flush_tag = tag_storage_rdata[59:40];
            2'b11: flush_tag = tag_storage_rdata[79:60];
        endcase

    assign awvalid_channel_flush = process_state == STATE_FLUSH_SEND_ADDRESS;
    assign awaddr_channel_flush  = {flush_tag, flush_outer_counter[6:2], 7'b0};
    assign awlen_channel_flush   = 31;  // 32 words
    assign awcache_channel_flush = 4'b1111;  // Cache-style

    assign wvalid_channel_flush  = process_state == STATE_FLUSH_SEND_DATA;
    assign wlast_channel_flush   = flush_inner_counter == 31;

    always @(*)
        case (flush_outer_counter[1:0])
            0: wdata_channel_flush = data_storage_rdata[31:0];
            1: wdata_channel_flush = data_storage_rdata[63:32];
            2: wdata_channel_flush = data_storage_rdata[95:64];
            3: wdata_channel_flush = data_storage_rdata[127:96];
        endcase

    assign wstrb_channel_flush = 4'b1111;

    assign bready_channel_flush = 1'b1;

    assign arvalid_channel_flush = 0;
    assign araddr_channel_flush = 0;
    assign arlen_channel_flush = 0;
    assign arcache_channel_flush = 0;

    assign rready_channel_flush = 0;

    // -- State
    assign process_ready_go = 
        process_cache_hit_not_periph || 
        process_state == STATE_FLUSH_FINALIZE || 
        process_state == STATE_PERIPH_READ_FINALIZE || 
        process_state == STATE_PERIPH_WRITE_FINALIZE ||
        process_state == STATE_REPLACE_EXECUTE;

    /* PROCESS-OUTPUT */

    reg [31:0] process_product_data;
    reg [31:0] process_output_data;
    reg process_output_rreq;

    assign rresp      = process_output_valid && process_output_rreq;
    assign dout       = process_output_data;
    assign flush_done = process_state == STATE_FLUSH_FINALIZE;

    always @(posedge clk) begin
        if (!rstn) begin
            process_output_valid <= 0;
            process_output_data  <= 0;
            process_output_rreq  <= 0;
        end else if (process_output_accept_ready) begin
            process_output_valid <= process_product_ready;
            if (process_product_ready) begin
                process_output_data <= process_product_data;
                process_output_rreq <= query_process_rreq;
            end
        end
    end

    always @(*)
        case (process_state)
            STATE_NORMAL: process_product_data = process_product_data_channel_normal;
            STATE_REPLACE_EXECUTE: process_product_data = process_product_data_channel_replace;
            STATE_PERIPH_READ_FINALIZE: process_product_data = periph_buffer;
            default: process_product_data = 0;
        endcase

endmodule

module Inst_cache_w32_addr32 (
    input wire m_axi_aclk,
    input wire m_axi_aresetn,

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
    input wire [31:0] m_axi_rdata,
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

    /*===== DATA STORAGE BITS =====*/
    // -- [31:0]: Data from set 0
    // -- [63:32]: Data from set 1
    // -- [95:64]: Data from set 2
    // -- [127:96]: Data from set 3

    /*===== TAG STORAGE BITS =====*/
    // -- [19:0]: Tag from set 0
    // -- [39:20]: Tag from set 1
    // -- [59:40]: Tag from set 2
    // -- [79:60]: Tag from set 3
    // -- [83:80]: Unused
    // -- [99:84]: LRU Matrix for 4 sets

    /* AXI FIXED VALUE */

    assign m_axi_arcache = 4'b1111;
    assign m_axi_arlen   = 31;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arid    = 0;
    assign m_axi_arlock  = 1'b0;

    /* PIPELINE SIGNALS */

    wire clk = m_axi_aclk;
    wire rstn = m_axi_aresetn;

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
        if (!rstn || fence_i) begin

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
    reg [15:0] data_storage_wmask;

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

    bram_w100_d32 tag_storage (
        .clka (clk),                // input wire clka
        .ena  (tag_storage_wen),    // input wire ena
        .wea  (tag_storage_wen),    // input wire [0 : 0] wea
        .addra(tag_storage_waddr),  // input wire [4 : 0] addra
        .dina (tag_storage_wdata),  // input wire [99 : 0] dina
        .clkb (clk),                // input wire clkb
        .enb  (tag_storage_ren),    // input wire enb
        .addrb(tag_storage_raddr),  // input wire [4 : 0] addrb
        .doutb(tag_storage_rdata)   // output wire [99 : 0] doutb
    );

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
        if (!rstn) begin
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
    reg [4:0] process_readin_counter;

    localparam STATE_NORMAL = 0;

    localparam STATE_REPLACE_READIN_SEND_ADDRESS = 4;  // Send readin address
    localparam STATE_REPLACE_READIN_RECEIVE_DATA = 5; // Receive readin data & Write received word to storage
    localparam STATE_REPLACE_READIN_FINALIZE = 6;  // Finalize readin: wait for the last word to write in storage
    localparam STATE_REPLACE_EXECUTE = 7;  // Execute the original request (Read or Write)

    // -- Normal: Reads a block from data storage; Updates tag and LRU matrix in tag matrix

    assign data_storage_raddr = {process_final_set, process_index, process_block_offset};
    assign data_storage_ren = process_product_ready && process_output_accept_ready;

    assign tag_storage_wen = process_product_ready || process_state == STATE_REPLACE_READIN_FINALIZE;
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

    assign data_storage_wen = process_state == STATE_REPLACE_READIN_RECEIVE_DATA && m_axi_rvalid;
    assign data_storage_wdata = {m_axi_rdata, m_axi_rdata, m_axi_rdata, m_axi_rdata};
    assign data_storage_waddr = {process_final_set, process_index, process_readin_counter[4:2]};

    always @(*)
        case (process_readin_counter[1:0])
            0: data_storage_wmask = 16'h000F;
            1: data_storage_wmask = 16'h00F0;
            2: data_storage_wmask = 16'h0F00;
            3: data_storage_wmask = 16'hF000;
        endcase

    assign valid_storage_waddr = process_index;
    assign valid_storage_wen   = process_state == STATE_REPLACE_READIN_FINALIZE;
    assign valid_storage_din   = valid_storage_dout | (4'b0001 << process_final_set);

    assign m_axi_arvalid       = process_state == STATE_REPLACE_READIN_SEND_ADDRESS;
    assign m_axi_araddr        = {process_tag, process_index, 7'd0};
    assign m_axi_rready        = process_state == STATE_REPLACE_READIN_RECEIVE_DATA;

    // When implementing fetch-error handling, remove this signal and use the one from the input
    wire clear_fetch_error = 0;

    always @(posedge clk) begin
        if (!rstn || clear_fetch_error) fetch_error <= 0;
        else if (m_axi_rvalid && m_axi_rlast && m_axi_rresp != 2'b00) fetch_error <= 1;
    end

    // State machine

    always @(posedge clk)
        if (!rstn) begin
            process_state          <= STATE_NORMAL;
            process_readin_counter <= 0;
        end else
            case (process_state)
                STATE_NORMAL: begin
                    if (query_process_valid && !process_cache_hit) begin
                        process_state          <= STATE_REPLACE_READIN_SEND_ADDRESS;
                        process_readin_counter <= 0;
                    end
                end

                STATE_REPLACE_READIN_SEND_ADDRESS:
                if (m_axi_arready) process_state <= STATE_REPLACE_READIN_RECEIVE_DATA;

                STATE_REPLACE_READIN_RECEIVE_DATA: begin
                    if (m_axi_rvalid) begin
                        if (process_readin_counter == 31)
                            process_state <= STATE_REPLACE_READIN_FINALIZE;
                        else process_readin_counter <= process_readin_counter + 1;
                    end
                end

                STATE_REPLACE_READIN_FINALIZE: process_state <= STATE_REPLACE_EXECUTE;

                STATE_REPLACE_EXECUTE: process_state <= STATE_NORMAL;

                default: process_state <= STATE_NORMAL;
            endcase

    assign process_ready_go = process_state == STATE_NORMAL && process_cache_hit || process_state == STATE_REPLACE_EXECUTE;
    assign process_working = process_state != STATE_NORMAL && process_state != STATE_REPLACE_EXECUTE;

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
        if (!rstn) begin
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
