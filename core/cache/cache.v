module Data_cache_pipeline (
    input wire m_axi_aclk,
    input wire m_axi_aresetn,

    /* Internal Bus Signals: CPU CORE <=> Cache */

    input wire [29:0] addr_i,  // Address Input

    input wire wreq_i,  // Write Request
    input wire [31:0] wdata_i,  // Write Data Input
    input wire [3:0] wmask_i,  // Byte Write Mask Input

    input wire rreq_i,  // Read Request
    output wire rresp_o,  // Read Response: High when read data is ready
    output wire [31:0] rdata_o,  // Read Data Output

    output wire busy_o,  // Busy Output: When Cache Miss Happens

    input  wire flush_en_i,   // Flush enabled
    output wire flush_done_o, // Flush Done

    /* External AXI Signals: Cache <=> External AXI Device */

    output reg m_axi_awvalid,
    input wire m_axi_awready,
    output reg [31:0] m_axi_awaddr,
    output reg [7:0] m_axi_awlen,
    output wire [1:0] m_axi_awburst,  // FIXED
    output wire [2:0] m_axi_awsize,  // FIXED
    output wire [0:0] m_axi_awid,  // FIXED
    output wire [3:0] m_axi_awcache,  // FIXED
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
    output wire [2:0] m_axi_arburst,  // FIXED
    output wire [0:0] m_axi_arid,  // FIXED
    output wire [2:0] m_axi_arsize,  // FIXED
    output wire [3:0] m_axi_arcache,  // FIXED
    output wire m_axi_arlock,  // FIXED

    input wire m_axi_rvalid,
    output reg m_axi_rready,
    input wire [31:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire [0:0] m_axi_rid,
    input wire [1:0] m_axi_rresp
);

    //*===== Fixed AXI Value =====//

    assign m_axi_awburst = 2'b01;
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awid    = 0;
    assign m_axi_awcache = 4'b1111;
    assign m_axi_awlock  = 1'b0;

    assign m_axi_arburst = 2'b01;
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arid    = 0;
    assign m_axi_arcache = 4'b1111;
    assign m_axi_arlock  = 1'b0;

    //*===== Finite State Machine =====//

    localparam S_NORMAL = 5'd0;  // Normal State

    localparam S_WRITE_REQ = 5'd1;
    localparam S_WRITE_WORD1 = 5'd2;
    localparam S_WRITE_WORD2 = 5'd3;
    localparam S_WRITE_WORD3 = 5'd4;
    localparam S_WRITE_WORD4 = 5'd5;
    localparam S_WRITE_RESP = 5'd6;

    localparam S_READ_REQ = 5'd7;
    localparam S_READ_WORD1 = 5'd8;
    localparam S_READ_WORD2 = 5'd9;
    localparam S_READ_WORD3 = 5'd10;
    localparam S_READ_WORD4 = 5'd11;

    localparam S_CACHE_WRITEBACK = 5'd12;

    localparam S_PERIPH_WRITE_REQ = 5'd13;
    localparam S_PERIPH_WRITE_WORD = 5'd14;
    localparam S_PERIPH_WRITE_RESP = 5'd15;

    localparam S_PERIPH_READ_REQ = 5'd16;
    localparam S_PERIPH_READ_WORD = 5'd17;

    localparam S_FLUSH_PREPARE = 5'd19;  // Forces storage to read
    localparam S_FLUSH_WRITE_REQ = 5'd20;
    localparam S_FLUSH_WRITE_WORD1 = 5'd21;
    localparam S_FLUSH_WRITE_WORD2 = 5'd22;
    localparam S_FLUSH_WRITE_WORD3 = 5'd23;
    localparam S_FLUSH_WRITE_WORD4 = 5'd24;
    localparam S_FLUSH_WRITE_RESP = 5'd25;

    localparam S_READIN_SYNC = 5'd26;
    localparam S_PERIPH_SYNC = 5'd27;
    localparam S_FLUSH_SYNC = 5'd28;

    reg [7:0] flush_counter;
    reg [4:0] state;

    //*===== Pipeline Control Signals =====//

    // Data in interstage register is valid?
    reg query_process_valid, process_output_valid;
    wire input_query_valid = wreq_i || rreq_i || flush_en_i;

    // Stage has done processing?
    wire query_ready_go = 1;
    wire process_ready_go;

    // Interstage register accepts new data?
    wire query_process_accept_ready, process_output_accept_ready;
    wire output_external_accept_ready = 1;

    // Stage produces valid data: input data is valid && stage successfully processes data
    wire query_product_ready = query_ready_go && input_query_valid;
    wire process_product_ready = process_ready_go && query_process_valid;

    assign process_output_accept_ready = !process_output_valid || output_external_accept_ready;
    assign query_process_accept_ready = !query_process_valid || process_product_ready && process_output_accept_ready;

    assign busy_o = !query_process_accept_ready;

    //*===== Pipeline Data Storage =====//

    reg [31:0] query_process_addr, query_process_wdata;
    reg [3:0] query_process_wmask;
    reg query_process_rreq, query_process_wreq, query_process_flushreq;

    reg [31:0] process_output_data;
    reg process_output_rreq;

    assign rresp_o = process_output_valid && process_output_rreq;

    wire [31:0] input_query_addr = {addr_i, 2'b00}, input_query_wdata = wdata_i;
    wire input_query_rreq = rreq_i, input_query_wreq = wreq_i, input_query_flushreq = flush_en_i;
    wire [3:0] input_query_wmask = wmask_i;

    //*===== Query Stage =====//

    wire [7:0] storage_waddr;
    reg [7:0] storage_raddr;
    wire storage_ren;

    wire [21:0] tag_rdata;  // Tag read data, fused, valid+dirty+tag
    wire [23:0] tag_mem_rdata;  // Data acquired from TAG-MEM port
    reg [21:0] tag_wdata;  // Tag write data, fused, valid+dirty+tag
    reg tag_wen;

    wire [127:0] data_rdata;
    reg [127:0] data_wdata;
    reg [15:0] data_wen;

    reg force_storage_read;  // Force storage to read
    assign storage_ren = query_process_accept_ready && query_product_ready || force_storage_read;

    /* Tag & Valid */

    cache_tag_256entry_en tag_mem (
        .clka(m_axi_aclk),
        .clkb(m_axi_aclk),

        .addra(storage_waddr),
        .dina (tag_wdata[20:0]),
        .wea  (tag_wen),

        .addrb(storage_raddr),
        .doutb(tag_mem_rdata),
        .enb  (storage_ren)
    );

    reg [255:0] valid_mem;
    reg valid_mem_latch;

    always @(posedge m_axi_aclk) begin
        if (!m_axi_aresetn) valid_mem_latch <= 0;
        else if (storage_ren) valid_mem_latch <= valid_mem[storage_raddr];
    end

    assign tag_rdata = {valid_mem_latch, tag_mem_rdata[20:0]};

    always @(posedge m_axi_aclk) begin
        if (!m_axi_aresetn) valid_mem <= 256'b0;
        else if (tag_wen) valid_mem[storage_waddr] <= tag_wdata[21];
    end

    /* Data */

    cache_data_256entry_en data_mem (
        .clka(m_axi_aclk),
        .clkb(m_axi_aclk),

        .addra(storage_waddr),
        .addrb(storage_raddr),

        .dina(data_wdata),
        .wea (data_wen),

        .doutb(data_rdata),
        .enb  (storage_ren)
    );

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

    //*===== Process Stage =====//

    /* Documentation */

    //*|  Write/Read  |  Peripheral?  |  Hit?  |           Operation
    // |     Write    |     True      |   -    |  Enter Peripheral Write Loop
    // |     Read     |     True      |   -    |  Enter Peripheral Read Loop
    // |     Write    |     False     |  Hit   |  Writes directly into tag&data
    // |     Write    |     False     |  Miss  |  Enters Writeback & Fetch Loop
    // |     Read     |     False     |  Hit   |  Writes directly into output stage
    // |     Read     |     False     |  Miss  |  Enters Writeback & Fetch Loop, then writes into output stage
    // |===============[ Flush ]===============|  Enters flush loop, mark all tags as clean

    //*[ Address ]
    //          +-----+-------+--------+------+
    // Bits     |31~12|11~~~~4|3~~~~~~2|1~~~~0|
    // Function | Tag | Index | Offset | Byte |
    //          +-----+-------+--------+------+
    //*[ Tag Storage ]
    //          +--------+-------+-------+-----+
    // Bits     |23~~~~22|   21  |   20  |19~~0|
    // Function | Unused | Valid | Dirty | Tag |
    // Storage  |  None  |  Reg  |     BRAM    |
    //          +--------+-------+-------+-----+
    //*[ Data Storage ]
    //          +--------+--------+--------+--------+
    // Bits     |127~~~96|95~~~~64|63~~~~32|31~~~~~0|
    // Function | Word 4 | Word 3 | Word 2 | Word 1 |
    //          +--------+--------+--------+--------+

    /* Address Extraction */

    // Input Address

    parameter PERIPH_BITS = 16;  // 64KB Peripheral Space
    parameter PERIPH_MASK = 32'h0001_0000;

    wire [19:0] query_process_addr_tag = query_process_addr[31:12];
    wire [7:0] query_process_addr_index = query_process_addr[11:4];
    wire [1:0] query_process_addr_word_offset = query_process_addr[3:2];

    wire query_process_addr_periph = query_process_addr[31:PERIPH_BITS] == PERIPH_MASK[31:PERIPH_BITS];

    // Acquired Tag Address

    wire tag_rd_valid = tag_rdata[21], tag_rd_dirty = tag_rdata[20];
    wire [19:0] tag_rd_tag = tag_rdata[19:0];

    /* Judgement */

    wire equal = tag_rd_tag == query_process_addr_tag;
    wire cache_hit = equal && tag_rd_valid;

    assign process_ready_go = 
    state == S_NORMAL && (
        query_process_addr_periph ? 0 : cache_hit
    ) 
    || state == S_READIN_SYNC 
    || state == S_PERIPH_SYNC
    || state == S_FLUSH_SYNC;

    /* AXI Interaction */

    reg [127:0] readin_buffer;

    localparam CHANNEL_NORMAL = 2'd0;
    localparam CHANNEL_CACHE = 2'd1;
    localparam CHANNEL_PERIPH = 2'd2;
    localparam CHANNEL_FLUSH = 2'd3;

    reg [1:0] channel;

    always @(*)
        case (state)

            S_NORMAL: channel = CHANNEL_NORMAL;

            S_WRITE_REQ, S_WRITE_WORD1, S_WRITE_WORD2, S_WRITE_WORD3, S_WRITE_WORD4, S_WRITE_RESP, S_READ_REQ, S_READ_WORD1, S_READ_WORD2, S_READ_WORD3, S_READ_WORD4, S_CACHE_WRITEBACK:
            channel = CHANNEL_CACHE;

            S_PERIPH_WRITE_REQ, S_PERIPH_WRITE_WORD, S_PERIPH_WRITE_RESP, S_PERIPH_READ_REQ, S_PERIPH_READ_WORD:
            channel = CHANNEL_PERIPH;

            S_FLUSH_PREPARE, S_FLUSH_WRITE_REQ, S_FLUSH_WRITE_WORD1, S_FLUSH_WRITE_WORD2, S_FLUSH_WRITE_WORD3, S_FLUSH_WRITE_WORD4, S_FLUSH_WRITE_RESP:
            channel = CHANNEL_FLUSH;

            default: channel = CHANNEL_NORMAL;

        endcase

    // CHANNEL 1: Cache Writeback / Readin

    wire cache_awvalid = state == S_WRITE_REQ;
    wire [31:0] cache_awaddr = {tag_rd_tag, query_process_addr_index, 4'b0};
    wire [7:0] cache_awlen = 8'd3;  // 4 Words

    reg cache_wvalid;
    wire cache_wlast = state == S_WRITE_WORD4;
    reg [31:0] cache_wdata;
    wire [3:0] cache_wstrb = 4'b1111;

    wire cache_bready = state == S_WRITE_RESP;

    wire cache_arvalid = state == S_READ_REQ;
    wire [31:0] cache_araddr = {query_process_addr_tag, query_process_addr_index, 4'b0};
    wire [7:0] cache_arlen = 8'd3;  // 4 Words

    reg cache_rready;

    // cache_wvalid
    always @(*)
        case (state)
            S_WRITE_WORD1, S_WRITE_WORD2, S_WRITE_WORD3, S_WRITE_WORD4: cache_wvalid = 1;
            default: cache_wvalid = 0;
        endcase

    // cache_wdata
    always @(*)
        case (state)
            S_WRITE_WORD1: cache_wdata = data_rdata[31:0];
            S_WRITE_WORD2: cache_wdata = data_rdata[63:32];
            S_WRITE_WORD3: cache_wdata = data_rdata[95:64];
            S_WRITE_WORD4: cache_wdata = data_rdata[127:96];
            default: cache_wdata = 0;
        endcase

    // cache_rready
    always @(*)
        case (state)
            S_READ_REQ, S_READ_WORD1, S_READ_WORD2, S_READ_WORD3, S_READ_WORD4: cache_rready = 1;
            default: cache_rready = 0;
        endcase

    // CHANNEL 2: Periph Read/Write

    wire periph_awvalid = state == S_PERIPH_WRITE_REQ;
    wire [31:0] periph_awaddr = {query_process_addr[31:2], 2'b0};
    wire [7:0] periph_awlen = 8'd0;  // 1 Word

    wire periph_wvalid = state == S_PERIPH_WRITE_WORD;
    wire periph_wlast = periph_wvalid;
    wire [31:0] periph_wdata = query_process_wdata;
    wire [3:0] periph_wstrb = query_process_wmask;

    wire periph_bready = state == S_PERIPH_WRITE_RESP;

    wire periph_arvalid = state == S_PERIPH_READ_REQ;
    wire [31:0] periph_araddr = periph_awaddr;
    wire [7:0] periph_arlen = 8'd0;

    wire periph_rready = state == S_PERIPH_READ_WORD;

    // CHANNEL 3: Flush Operation

    wire flush_awvalid = state == S_FLUSH_WRITE_REQ && tag_rd_valid && tag_rd_dirty;
    wire [31:0] flush_awaddr = {tag_rd_tag, flush_counter, 4'b0};
    wire [7:0] flush_awlen = 8'd3;

    reg flush_wvalid;
    wire flush_wlast = state == S_FLUSH_WRITE_WORD4;
    reg [31:0] flush_wdata;
    wire [3:0] flush_wstrb = 4'b1111;

    wire flush_bready = state == S_FLUSH_WRITE_RESP;

    wire flush_arvalid = 0;
    wire [31:0] flush_araddr = 0;
    wire [7:0] flush_arlen = 0;

    wire flush_rready = 0;

    // Channel Selection

    always @(*)
        case (channel)
            CHANNEL_NORMAL: begin
                m_axi_awvalid = 0;
                m_axi_awaddr  = 0;
                m_axi_awlen   = 0;
                m_axi_wvalid  = 0;
                m_axi_wlast   = 0;
                m_axi_wdata   = 0;
                m_axi_bready  = 0;
                m_axi_arvalid = 0;
                m_axi_araddr  = 0;
                m_axi_arlen   = 0;
                m_axi_rready  = 0;
            end
            CHANNEL_CACHE: begin
                m_axi_awvalid = cache_awvalid;
                m_axi_awaddr  = cache_awaddr;
                m_axi_awlen   = cache_awlen;
                m_axi_wvalid  = cache_wvalid;
                m_axi_wlast   = cache_wlast;
                m_axi_wdata   = cache_wdata;
                m_axi_bready  = cache_bready;
                m_axi_arvalid = cache_arvalid;
                m_axi_araddr  = cache_araddr;
                m_axi_arlen   = cache_arlen;
                m_axi_rready  = cache_rready;
                m_axi_wstrb   = cache_wstrb;
            end
            CHANNEL_PERIPH: begin
                m_axi_awvalid = periph_awvalid;
                m_axi_awaddr  = periph_awaddr;
                m_axi_awlen   = periph_awlen;
                m_axi_wvalid  = periph_wvalid;
                m_axi_wlast   = periph_wlast;
                m_axi_wdata   = periph_wdata;
                m_axi_bready  = periph_bready;
                m_axi_arvalid = periph_arvalid;
                m_axi_araddr  = periph_araddr;
                m_axi_arlen   = periph_arlen;
                m_axi_rready  = periph_rready;
                m_axi_wstrb   = periph_wstrb;
            end
            CHANNEL_FLUSH: begin
                m_axi_awvalid = flush_awvalid;
                m_axi_awaddr  = flush_awaddr;
                m_axi_awlen   = flush_awlen;
                m_axi_wvalid  = flush_wvalid;
                m_axi_wlast   = flush_wlast;
                m_axi_wdata   = flush_wdata;
                m_axi_bready  = flush_bready;
                m_axi_arvalid = flush_arvalid;
                m_axi_araddr  = flush_araddr;
                m_axi_arlen   = flush_arlen;
                m_axi_rready  = flush_rready;
                m_axi_wstrb   = flush_wstrb;
            end
        endcase

    // flush_wvalid
    always @(*)
        case (state)
            S_FLUSH_WRITE_WORD1, S_FLUSH_WRITE_WORD2, S_FLUSH_WRITE_WORD3, S_FLUSH_WRITE_WORD4:
            flush_wvalid = 1;
            default: flush_wvalid = 0;
        endcase

    // flush_wdata
    always @(*)
        case (state)
            S_FLUSH_WRITE_WORD1: flush_wdata = data_rdata[31:0];
            S_FLUSH_WRITE_WORD2: flush_wdata = data_rdata[63:32];
            S_FLUSH_WRITE_WORD3: flush_wdata = data_rdata[95:64];
            S_FLUSH_WRITE_WORD4: flush_wdata = data_rdata[127:96];
            default: flush_wdata = 0;
        endcase

    /* Storage Interaction */

    assign storage_waddr = state == S_FLUSH_WRITE_RESP ? flush_counter : query_process_addr_index;

    // storage_raddr
    always @(*)
        case (state)
            // Normal
            S_NORMAL: storage_raddr = input_query_addr[11:4];

            // Flush Routine
            S_FLUSH_PREPARE: begin
                storage_raddr = flush_counter;
            end

            // Writeback
            S_WRITE_REQ, S_WRITE_WORD1, S_WRITE_WORD2, S_WRITE_WORD3, S_WRITE_WORD4, S_WRITE_RESP: begin
                storage_raddr = query_process_addr_tag;
            end

            S_READIN_SYNC, S_PERIPH_SYNC, S_FLUSH_SYNC: storage_raddr = input_query_addr[11:4];

            default: storage_raddr = 0;
        endcase

    // tag_wen
    always @(*)
        case (state)
            // Normal
            S_NORMAL: tag_wen = query_process_valid && cache_hit && query_process_wreq;

            S_READIN_SYNC: tag_wen = query_process_wreq;

            // Set new tag during a swap OR clear dirty bit during a flush routine
            S_CACHE_WRITEBACK, S_FLUSH_WRITE_RESP: tag_wen = 1;

            default: tag_wen = 0;
        endcase

    // data_wen
    always @(*)
        case (state)
            S_NORMAL: begin
                if (query_process_valid && cache_hit && query_process_wreq)
                    case (query_process_addr_word_offset)  // Normal masked write-in op
                        0: data_wen = {12'b0, query_process_wmask};
                        1: data_wen = {8'b0, query_process_wmask, 4'b0};
                        2: data_wen = {4'b0, query_process_wmask, 8'b0};
                        3: data_wen = {query_process_wmask, 12'b0};
                    endcase
                else data_wen = 0;
            end

            S_READIN_SYNC: begin
                if (query_process_wreq)
                    case (query_process_addr_word_offset)  // Normal masked write-in op
                        0: data_wen = {12'b0, query_process_wmask};
                        1: data_wen = {8'b0, query_process_wmask, 4'b0};
                        2: data_wen = {4'b0, query_process_wmask, 8'b0};
                        3: data_wen = {query_process_wmask, 12'b0};
                    endcase
                else data_wen = 0;
            end

            S_CACHE_WRITEBACK: data_wen = 16'hFFFF;  // Writes back acquired data
            default: data_wen = 0;
        endcase

    // force_storage_read
    always @(*)
        case (state)
            // Force reading out during flush writebacks
            S_FLUSH_PREPARE, S_READIN_SYNC, S_PERIPH_SYNC, S_FLUSH_SYNC: force_storage_read = 1;

            default: force_storage_read = 0;
        endcase

    // data_wdata
    always @(*)
        case (state)
            S_CACHE_WRITEBACK: data_wdata = readin_buffer;

            default:
            data_wdata = {
                query_process_wdata, query_process_wdata, query_process_wdata, query_process_wdata
            };
        endcase

    // tag_wdata
    always @(*)
        case (state)
            S_FLUSH_WRITE_RESP: tag_wdata = {2'b10, tag_rdata[19:0]};
            default: tag_wdata = {2'b11, query_process_addr_tag};
        endcase

    /* FSM Transfer */

    localparam SRC_NORMAL = 1'd0;
    localparam SRC_READIN = 1'd1;

    wire [0:0] output_src = (state == S_PERIPH_SYNC || state == S_READIN_SYNC) ? SRC_READIN : SRC_NORMAL;
    always @(posedge m_axi_aclk) begin
        if (!m_axi_aresetn) begin
            state         <= S_NORMAL;
            readin_buffer <= 0;
            flush_counter <= 0;
        end else
            case (state)

                S_NORMAL: begin
                    flush_counter <= 0;

                    if (query_process_valid) begin
                        if (query_process_flushreq) state <= S_FLUSH_PREPARE;
                        else if (query_process_addr_periph) begin
                            if (query_process_wreq) state <= S_PERIPH_WRITE_REQ;
                            if (query_process_rreq) state <= S_PERIPH_READ_REQ;
                        end else if (!cache_hit) begin
                            if (tag_rd_valid && tag_rd_dirty)
                                state <= S_WRITE_REQ;  // Needs writeback
                            else state <= S_READ_REQ;  // Overwrite existing data
                        end
                    end
                end

                // Writeback

                S_WRITE_REQ: if (m_axi_awready) state <= S_WRITE_WORD1;
                S_WRITE_WORD1: if (m_axi_wready) state <= S_WRITE_WORD2;
                S_WRITE_WORD2: if (m_axi_wready) state <= S_WRITE_WORD3;
                S_WRITE_WORD3: if (m_axi_wready) state <= S_WRITE_WORD4;
                S_WRITE_WORD4: if (m_axi_wready) state <= S_WRITE_RESP;
                S_WRITE_RESP:
                if (m_axi_bvalid) state <= S_READ_REQ;  // TODO: Handle writeback error

                // Readin

                S_READ_REQ: if (m_axi_arready) state <= S_READ_WORD1;

                S_READ_WORD1:
                if (m_axi_rvalid) begin
                    state               <= S_READ_WORD2;
                    readin_buffer[31:0] <= m_axi_rdata;
                end
                S_READ_WORD2:
                if (m_axi_rvalid) begin
                    state                <= S_READ_WORD3;
                    readin_buffer[63:32] <= m_axi_rdata;
                end
                S_READ_WORD3:
                if (m_axi_rvalid) begin
                    state                <= S_READ_WORD4;
                    readin_buffer[95:64] <= m_axi_rdata;
                end
                S_READ_WORD4:
                if (m_axi_rvalid) begin
                    state                 <= S_CACHE_WRITEBACK;
                    readin_buffer[127:96] <= m_axi_rdata;
                end

                S_CACHE_WRITEBACK: begin
                    state <= S_READIN_SYNC;
                end

                S_FLUSH_SYNC, S_READIN_SYNC, S_PERIPH_SYNC: begin
                    state <= S_NORMAL;
                end


                // Periph. Write

                S_PERIPH_WRITE_REQ:  if (m_axi_awready) state <= S_PERIPH_WRITE_WORD;
                S_PERIPH_WRITE_WORD: if (m_axi_wready) state <= S_PERIPH_WRITE_RESP;
                S_PERIPH_WRITE_RESP: if (m_axi_bvalid) state <= S_PERIPH_SYNC;

                // Periph. Read

                S_PERIPH_READ_REQ: if (m_axi_arready) state <= S_PERIPH_READ_WORD;
                S_PERIPH_READ_WORD:
                if (m_axi_rvalid) begin
                    state         <= S_PERIPH_SYNC;
                    readin_buffer <= {m_axi_rdata, m_axi_rdata, m_axi_rdata, m_axi_rdata};
                end

                S_FLUSH_PREPARE: begin
                    state <= S_FLUSH_WRITE_REQ;
                end

                S_FLUSH_WRITE_REQ: begin
                    if (tag_rd_valid && tag_rd_dirty) begin
                        if (m_axi_awready)
                            state <= S_FLUSH_WRITE_WORD1;  // Current line needs writeback
                    end else begin  // No writeback needed for current line
                        if (flush_counter == 255) state <= S_FLUSH_SYNC;  // Writeback done
                        else begin  // Writeback not done
                            state         <= S_FLUSH_PREPARE;
                            flush_counter <= flush_counter + 1;
                        end
                    end
                end

                S_FLUSH_WRITE_WORD1: if (m_axi_wready) state <= S_FLUSH_WRITE_WORD2;
                S_FLUSH_WRITE_WORD2: if (m_axi_wready) state <= S_FLUSH_WRITE_WORD3;
                S_FLUSH_WRITE_WORD3: if (m_axi_wready) state <= S_FLUSH_WRITE_WORD4;
                S_FLUSH_WRITE_WORD4: if (m_axi_wready) state <= S_FLUSH_WRITE_RESP;

                S_FLUSH_WRITE_RESP:
                if (m_axi_bvalid) begin
                    if (flush_counter == 255) state <= S_FLUSH_SYNC;
                    else begin
                        state         <= S_FLUSH_PREPARE;
                        flush_counter <= flush_counter + 1;
                    end
                end

                default: state <= S_NORMAL;
            endcase
    end

    reg [31:0] readin_buffer_output;
    reg [31:0] data_rdata_output;

    always @(*)
        case (query_process_addr_word_offset)
            0: readin_buffer_output = readin_buffer[31:0];
            1: readin_buffer_output = readin_buffer[63:32];
            2: readin_buffer_output = readin_buffer[95:64];
            3: readin_buffer_output = readin_buffer[127:96];
        endcase

    always @(*)
        case (query_process_addr_word_offset)
            0: data_rdata_output = data_rdata[31:0];
            1: data_rdata_output = data_rdata[63:32];
            2: data_rdata_output = data_rdata[95:64];
            3: data_rdata_output = data_rdata[127:96];
        endcase

    reg [31:0] process_product_data;

    always @(*)
        case (output_src)
            SRC_NORMAL: process_product_data = data_rdata_output;
            SRC_READIN: process_product_data = readin_buffer_output;
        endcase

    //*===== Output Stage =====//

    always @(posedge m_axi_aclk) begin
        if (!m_axi_aresetn) begin
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

    assign rresp_o      = process_output_valid && process_output_rreq;
    assign flush_done_o = state == S_NORMAL && flush_counter == 255;
    assign rdata_o      = process_output_data;

endmodule


module Inst_cache_pipeline (

    /* AXI Bus Interface */

    input wire m_axi_aclk,
    input wire m_axi_aresetn,

    output wire m_axi_arvalid,
    input wire m_axi_arready,
    output wire [31:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arburst,
    output wire [0:0] m_axi_arid,
    output wire [2:0] m_axi_arsize,  // 4-Byte Access
    output wire [3:0] m_axi_arcache,  // What xilinx suggests
    output wire m_axi_arlock,  // No Lock

    input wire m_axi_rvalid,
    output wire m_axi_rready,
    input wire [31:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire [0:0] m_axi_rid,
    input wire [1:0] m_axi_rresp,

    /* Connection with internal pipeline */

    // Signals from IF stage
    input  wire if_product_ready_i,
    output wire cache_accept_ready_o,

    // Signals to ID stage
    input  wire id_accept_ready_i,
    output wire cache_product_ready_o,

    input wire flush_i,

    input wire [31:0] if_pc_i,
    input wire if_branch_taken_i,
    input wire [30:0] if_branch_target_i,

    output wire [31:0] cache_pc_o,
    output wire [31:0] cache_inst_o,
    output wire cache_branch_taken_o,
    output wire [30:0] cache_branch_target_o,

    output wire address_misaligned_o  // Reserved for future use (Interrupt/Exception Handling)

    // [IF] --> [Cache] --> [ID] --> ...
);

    // Fixed AXI Value

    assign m_axi_arburst = 2'b01;
    assign m_axi_arsize  = 3'd2;
    assign m_axi_arid    = 0;
    assign m_axi_arcache = 4'b1111;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arlen   = 3'b011;  // Burst length = 4

    // Finite State Machine

    localparam S_NORMAL = 3'd0;
    localparam S_READ_ADDR = 3'd1;  // Send read address
    localparam S_READ_WORD1 = 3'd2;
    localparam S_READ_WORD2 = 3'd3;
    localparam S_READ_WORD3 = 3'd4;
    localparam S_READ_WORD4 = 3'd5;
    localparam S_WRITEIN = 3'd6;  // Write instruction to cache
    localparam S_SYNC = 3'd7;  // Additional state for synchronization


    // Pipeline Signals

    wire lock_pipeline;

    reg input_stage1_valid, stage1_stage2_valid, stage2_output_valid;
    wire stage1_ready_go, stage2_ready_go;

    wire stage1_product_ready = stage1_ready_go && input_stage1_valid;
    wire stage2_product_ready = stage2_ready_go && stage1_stage2_valid;

    assign cache_product_ready_o = stage2_output_valid;

    wire input_stage1_accept_ready, stage1_stage2_accept_ready, stage2_output_accept_ready;

    assign cache_accept_ready_o = input_stage1_accept_ready;
    assign input_stage1_accept_ready = !input_stage1_valid || stage1_product_ready && stage1_stage2_accept_ready;
    assign stage1_stage2_accept_ready = (!stage1_stage2_valid || stage2_product_ready && stage2_output_accept_ready) && !lock_pipeline;
    assign stage2_output_accept_ready = !stage2_output_valid || id_accept_ready_i;

    // Storage

    wire [7:0] storage_waddr;
    wire storage_wen;

    wire [7:0] storage_raddr;

    wire [19:0] tag_wdata;
    wire [127:0] data_wdata;
    wire valid_wdata = 1;

    wire [19:0] tag_rdata;
    wire [127:0] data_rdata;
    reg valid_rdata;

    cache_tag_256entry_en tag_mem (
        .clka(m_axi_aclk),
        .clkb(m_axi_aclk),

        .addra(storage_waddr),
        .dina (tag_wdata),
        .wea  (storage_wen),

        .addrb(storage_raddr),
        .doutb(tag_rdata),
        .enb  (stage1_stage2_accept_ready && stage1_product_ready)
    );

    cache_data_256entry_en data_mem (
        .clka(m_axi_aclk),
        .clkb(m_axi_aclk),

        .addra(storage_waddr),
        .addrb(storage_raddr),

        .dina(data_wdata),
        .wea (storage_wen ? 16'hFFFF : 16'd0),

        .doutb(data_rdata),
        .enb  (stage1_stage2_accept_ready && stage1_product_ready)
    );

    reg [255:0] valid_mem;

    always @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) valid_mem <= 256'b0;
        else if (storage_wen) valid_mem[storage_waddr] <= valid_wdata;
    end

    always @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) valid_rdata <= 0;
        else valid_rdata <= valid_mem[storage_raddr];
    end


    // Input-Stage1

    reg input_stage1_branch_taken;
    reg [30:0] input_stage1_branch_target;
    reg [31:0] input_stage1_pc;

    always @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) begin
            input_stage1_valid         <= 0;
            input_stage1_branch_taken  <= 0;
            input_stage1_branch_target <= 0;
            input_stage1_pc            <= 0;
        end else if (flush_i) begin
            input_stage1_valid <= 0;
        end else if (input_stage1_accept_ready) begin
            input_stage1_valid <= if_product_ready_i;
            if (if_product_ready_i) begin
                input_stage1_branch_taken  <= if_branch_taken_i;
                input_stage1_branch_target <= if_branch_target_i;
                input_stage1_pc            <= if_pc_i;
            end
        end
    end

    // Stage 1

    assign storage_raddr   = input_stage1_pc[11:4];
    assign stage1_ready_go = 1;

    // Stage1-Stage2

    reg stage1_stage2_branch_taken;
    reg [30:0] stage1_stage2_branch_target;
    reg [31:0] stage1_stage2_pc;

    always @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) begin
            stage1_stage2_valid         <= 0;
            stage1_stage2_branch_taken  <= 0;
            stage1_stage2_branch_target <= 0;
            stage1_stage2_pc            <= 0;
        end else if (flush_i) begin
            stage1_stage2_valid <= 0;
        end else if (stage1_stage2_accept_ready) begin
            stage1_stage2_valid <= stage1_product_ready;
            if (stage1_product_ready) begin
                stage1_stage2_branch_taken  <= input_stage1_branch_taken;
                stage1_stage2_branch_target <= input_stage1_branch_target;
                stage1_stage2_pc            <= input_stage1_pc;
            end
        end
    end

    // Stage 2

    reg [  2:0] state;
    reg [127:0] temporary_buffer;

    reg [ 31:0] axi_address;

    always @(posedge m_axi_aclk)
        if (m_axi_rvalid) begin
            case (state)
                S_READ_WORD1: temporary_buffer[31:0] <= m_axi_rdata;
                S_READ_WORD2: temporary_buffer[63:32] <= m_axi_rdata;
                S_READ_WORD3: temporary_buffer[95:64] <= m_axi_rdata;
                S_READ_WORD4: temporary_buffer[127:96] <= m_axi_rdata;
            endcase
        end

    assign m_axi_araddr = axi_address;
    assign m_axi_arvalid = (state == S_READ_ADDR);
    assign m_axi_rready = (state == S_READ_WORD1 || state == S_READ_WORD2 || state == S_READ_WORD3 || state == S_READ_WORD4);

    assign storage_waddr = stage1_stage2_pc[11:4];
    assign storage_wen = (state == S_WRITEIN);

    assign tag_wdata = stage1_stage2_pc[31:12];
    assign data_wdata = temporary_buffer;

    wire hit = valid_rdata && (tag_rdata[19:0] == stage1_stage2_pc[31:12]);

    assign stage2_ready_go = state == S_NORMAL && hit || state == S_SYNC;
    assign lock_pipeline   = state != S_NORMAL && state != S_SYNC;

    always @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) begin
            state       <= S_NORMAL;
            axi_address <= 0;
        end else
            case (state)
                S_NORMAL: begin
                    if (flush_i) state <= S_SYNC;
                    else if (!hit && stage1_stage2_valid) begin
                        state       <= S_READ_ADDR;
                        axi_address <= {stage1_stage2_pc[31:4], 4'b0};
                    end
                end
                S_READ_ADDR: if (m_axi_arready) state <= S_READ_WORD1;
                S_READ_WORD1: if (m_axi_rvalid) state <= S_READ_WORD2;
                S_READ_WORD2: if (m_axi_rvalid) state <= S_READ_WORD3;
                S_READ_WORD3: if (m_axi_rvalid) state <= S_READ_WORD4;
                S_READ_WORD4: if (m_axi_rvalid) state <= S_WRITEIN;
                S_WRITEIN: state <= S_SYNC;
                S_SYNC: state <= S_NORMAL;
            endcase
    end

    reg [31:0] temp_buffer_sel;

    always @(*)
        case (stage1_stage2_pc[3:2])
            0: temp_buffer_sel = temporary_buffer[31:0];
            1: temp_buffer_sel = temporary_buffer[63:32];
            2: temp_buffer_sel = temporary_buffer[95:64];
            3: temp_buffer_sel = temporary_buffer[127:96];
        endcase

    reg [31:0] data_rdata_sel;

    always @(*)
        case (stage1_stage2_pc[3:2])
            0: data_rdata_sel = data_rdata[31:0];
            1: data_rdata_sel = data_rdata[63:32];
            2: data_rdata_sel = data_rdata[95:64];
            3: data_rdata_sel = data_rdata[127:96];
        endcase

    // Stage2 - Output

    reg [31:0] stage2_output_pc, stage2_output_inst;
    reg stage2_output_branch_taken;
    reg [30:0] stage2_output_branch_target;

    always @(posedge m_axi_aclk or negedge m_axi_aresetn) begin
        if (!m_axi_aresetn) begin
            stage2_output_valid         <= 0;
            stage2_output_pc            <= 0;
            stage2_output_inst          <= 0;
            stage2_output_branch_taken  <= 0;
            stage2_output_branch_target <= 0;
        end else if (flush_i) begin
            stage2_output_valid <= 0;
        end else if (stage2_output_accept_ready) begin
            stage2_output_valid <= stage2_product_ready;
            if (stage2_product_ready) begin
                stage2_output_pc            <= stage1_stage2_pc;
                stage2_output_inst          <= state == S_SYNC ? temp_buffer_sel : data_rdata_sel;
                stage2_output_branch_taken  <= stage1_stage2_branch_taken;
                stage2_output_branch_target <= stage1_stage2_branch_target;
            end
        end
    end

    assign cache_pc_o            = stage2_output_pc;
    assign cache_inst_o          = stage2_output_inst;
    assign cache_branch_taken_o  = stage2_output_branch_taken;
    assign cache_branch_target_o = stage2_output_branch_target;

endmodule
