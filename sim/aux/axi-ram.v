module axi_ram #(
    parameter ADDR_WIDTH    = 32,             // Address width
    parameter STORAGE_WIDTH = 31,             // Storage width
    parameter DATA_WIDTH    = 32,             // Fixed data width
    parameter STRB_WIDTH    = DATA_WIDTH / 8
) (
    input wire clk,
    input wire rstn,

    // Write Address Channel
    input  wire [ADDR_WIDTH-1:0] awaddr,
    input  wire [           7:0] awlen,
    input  wire [           2:0] awsize,
    input  wire [           1:0] awburst,
    input  wire                  awvalid,
    output wire                  awready,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire [STRB_WIDTH-1:0] wstrb,
    input  wire                  wlast,
    input  wire                  wvalid,
    output wire                  wready,

    // Write Response Channel
    output wire [1:0] bresp,
    output reg        bvalid,
    input  wire       bready,

    // Read Address Channel
    input  wire [ADDR_WIDTH-1:0] araddr,
    input  wire [           7:0] arlen,
    input  wire [           2:0] arsize,
    input  wire [           1:0] arburst,
    input  wire                  arvalid,
    output wire                  arready,

    // Read Data Channel
    output wire [DATA_WIDTH-1:0] rdata,
    output wire [           1:0] rresp,
    output wire                  rlast,
    output wire                  rvalid,
    input  wire                  rready,

    // ...existing code...
    input  wire [2:0] awid,  // 3-bit Write ID
    output reg  [2:0] bid,   // 3-bit Write Response ID
    input  wire [2:0] arid,  // 3-bit Read ID
    output reg  [2:0] rid    // 3-bit Read Response ID
);

    localparam MEM_SIZE = 1 << (STORAGE_WIDTH - 2);

    // Memory initialized to zero
    reg [31:0] mem[0:MEM_SIZE-1];

    integer i;
    initial begin
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            mem[i] = 32'd0;
        end
    end

    // Store IDs

    // Internal registers
    reg [STORAGE_WIDTH-1:0] wr_addr;
    reg [STORAGE_WIDTH-1:0] rd_addr;
    reg [              7:0] rd_len;

    localparam IDLE = 2'b00, WRITE = 2'b01, WRITE_RESP = 2'b11, READ = 2'b10;
    reg [1:0] state;

    initial begin
        state = IDLE;
    end

    assign bresp   = 2'b00;
    assign rresp   = 2'b00;
    assign awready = (state == IDLE);
    assign wready  = (state == WRITE);
    assign arready = (state == IDLE);
    assign rvalid  = (state == READ);
    assign rlast   = (rd_len == 0);
    assign rdata   = mem[rd_addr>>2];

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                if (awvalid) begin
                    wr_addr <= awaddr;
                    bid     <= awid;
                    state   <= WRITE;
                end else if (arvalid) begin
                    rd_addr <= araddr;
                    rd_len  <= arlen;
                    rid     <= arid;
                    state   <= READ;
                end
            end

            WRITE: begin
                if (wvalid) begin
                    mem[wr_addr >> 2] <= 
                        wdata & ({{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}}) 
                        | mem[wr_addr >> 2] & ~({{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}});
                    wr_addr <= wr_addr + 4;
                    if (wlast) begin
                        bvalid <= 1;
                        state  <= WRITE_RESP;
                    end
                end
            end

            WRITE_RESP: begin
                if (bready) begin
                    bvalid <= 0;
                    state  <= IDLE;
                end
            end

            READ: begin
                if (rready) begin
                    rd_addr <= rd_addr + 4;
                    rd_len  <= rd_len - 1;
                    if (rd_len == 0) begin
                        state <= IDLE;
                    end
                end
            end

        endcase
    end

endmodule
