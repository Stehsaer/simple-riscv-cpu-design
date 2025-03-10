// |====================|
// | SPI AXI PERIPHERAL |
// |====================|
//
// | Address        | Access | Name
// |----------------|--------|-------------
// | 0x00           | R/W    | FREQ
// | 0x04           | R/W    | CS
// | 0x08           | R/W    | LEN
// | 0x400~0x7FF    | W      | TX BUFFER
// | 0x800~0xBFF    | R      | RX BUFFER
//
// ## FREQ
//     16-bit frequency divider for SPI clock, calculated by:
//         SPI clock = AXI clock / Data rate
//     Example: AXI clock = 200MHz, Data rate = 1Mbps, FREQ = 200
// ## CS
//     1-bit chip select, write 1 to make PHY CS low, selecting the device, write 0 does the opposite
// ## LEN
//     Counter for bytes to be sent, maximum being 1024
//     Write positive value to start sending data, write 0 to stop sending
//     Read the value to check how many bytes left to be sent
//     SPI communication logic automatically decrements the counter after sending each byte, and stops when counter reaches 0
// ## TX BUFFER
//     1024 bytes buffer for data to be sent. Communication logic sends data from LOW address to HIGH.
//     Example: Write 0x12345678 to 0x400, 0x12 will be sent, and the corresponding received data will be stored in 0x800.
// ## RX BUFFER
//     1024 bytes buffer for received data. Communication logic stores data from LOW address to HIGH.
//     See TX BUFFER for example.
//
// ===== IP CORES =====
//
// ## bram_w32_r8_1KiB `tx_buffer`
//     Simple dual port BRAM, 32-bit write, 8-bit read, 1KiB in size. Has byte-write mask feature.
//     Returns read data in the second cycle after read request.
// ## bram_w8_r32_1KiB `rx_buffer`
//     Simple dual port BRAM, 8-bit write, 32-bit read, 1KiB in size.
//     Returns read data in the second cycle after read request.

module spi_axi (
    /* AXI INTERFACE */
    input wire aclk,
    input wire aresetn,

    // AW
    input wire [11:0] awaddr,
    input wire [3:0] awprot,
    input wire awvalid,
    output wire awready,

    // W
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire wvalid,
    output wire wready,

    // B
    output wire [1:0] bresp,
    output wire bvalid,
    input wire bready,

    // AR
    input wire [11:0] araddr,
    input wire [3:0] arprot,
    input wire arvalid,
    output wire arready,

    // R
    output wire [31:0] rdata,
    output wire [1:0] rresp,
    output wire rvalid,
    input wire rready,

    /* SPI PHY */

    output wire sclk,
    output wire mosi,
    input  wire miso,
    output wire cs
);

    /* Send Buffer */

    wire tx_buf_wen;
    wire [7:0] tx_buf_waddr;
    wire [3:0] tx_buf_wmask;
    wire [31:0] tx_buf_wdata;

    wire tx_buf_ren;
    wire [9:0] tx_buf_raddr;
    wire [7:0] tx_buf_rdata;

    bram_w32_r8_1KiB tx_buffer (
        .clka(aclk),  // input wire clka
        .clkb(aclk),  // input wire clkb

        .ena  (tx_buf_wen),    // input wire ena
        .wea  (tx_buf_wmask),  // input wire [3 : 0] wea
        .addra(tx_buf_waddr),  // input wire [7 : 0] addra
        .dina (tx_buf_wdata),  // input wire [31 : 0] dina

        .enb  (tx_buf_ren),    // input wire enb
        .addrb(tx_buf_raddr),  // input wire [9 : 0] addrb
        .doutb(tx_buf_rdata)   // output wire [7 : 0] doutb
    );

    /* Receive Buffer */

    wire rx_buf_wen;
    wire [9:0] rx_buf_waddr;
    wire [7:0] rx_buf_wdata;

    wire rx_buf_ren;
    wire [7:0] rx_buf_raddr;
    wire [31:0] rx_buf_rdata;

    bram_w8_r32_1KiB rx_buffer (
        .clka(aclk),  // input wire clka
        .clkb(aclk),  // input wire clkb

        .ena  (rx_buf_wen),    // input wire ena
        .addra(rx_buf_waddr),  // input wire [9 : 0] addra
        .dina (rx_buf_wdata),  // input wire [7 : 0] dina
        .wea  (rx_buf_wen),    // input wire [0 : 0] wea

        .enb  (rx_buf_ren),    // input wire enb
        .addrb(rx_buf_raddr),  // input wire [7 : 0] addrb
        .doutb(rx_buf_rdata)   // output wire [31 : 0] doutb
    );

    /* SPI State Machine */

    localparam SPI_IDLE = 0;  // No work
    localparam SPI_ACQUIRE = 1;  // Acquire data from TX buffer
    localparam SPI_ACQUIRE_WAIT = 2;  // Wait for TX buffer to return data
    localparam SPI_ACQUIRE_SET = 3;  // Set data to be sent
    localparam SPI_COMM = 4;  // Communicate 
    localparam SPI_STORE = 5;  // Store received data to RX buffer, and counter decrement

    reg [2:0] spi_state;  // SPI state machine
    reg [15:0] spi_clock_counter;  // Clock generate counter
    reg [2:0] spi_bit_counter;  // Counter for bits sent/received in a byte
    reg [7:0] spi_tx_data;  // Data to be sent, still stored in little endian
    reg [7:0] spi_rx_data;  // Data received, stored in little endian
    reg [9:0] spi_storage_addr;  // Address for storing received data / fetching data to be sent

    reg [10:0] spi_len_counter;  // Bytes left to be sent, max 1024
    reg spi_cs_reg;  // Chip select
    reg [15:0] spi_clock_divider;  // Clock divider

    assign cs   = ~spi_cs_reg;
    assign sclk = spi_clock_counter > (spi_clock_divider >> 1);
    assign mosi = spi_tx_data[7];

    wire spi_sample = spi_clock_counter == spi_clock_divider >> 1;
    wire spi_step = spi_clock_counter == 0;


    always @(posedge aclk) begin
        if (!aresetn) begin
            spi_state         <= SPI_IDLE;
            spi_clock_counter <= 0;
            spi_bit_counter   <= 0;
            spi_tx_data       <= 0;
            spi_rx_data       <= 0;
        end else begin
            case (spi_state)

                SPI_IDLE: begin
                    if (spi_len_counter > 0) begin
                        spi_state <= SPI_ACQUIRE;
                    end
                end

                SPI_ACQUIRE: begin
                    spi_clock_counter <= 1;
                    spi_bit_counter   <= 0;
                    spi_state         <= SPI_ACQUIRE_WAIT;
                end

                SPI_ACQUIRE_WAIT: spi_state <= SPI_ACQUIRE_SET;

                SPI_ACQUIRE_SET: begin
                    spi_tx_data <= tx_buf_rdata;
                    spi_state   <= SPI_COMM;
                end

                SPI_COMM: begin

                    // RX
                    if (spi_sample) spi_rx_data <= {spi_rx_data[6:0], miso};

                    // TX

                    if (spi_step) begin  // Trigger on falling edge
                        if (spi_bit_counter == 7)  // Byte send done, switch to next state
                            spi_state <= SPI_STORE;
                        else begin  // Not done, increase bit counter and shift tx register 
                            spi_bit_counter <= spi_bit_counter + 1;
                            spi_tx_data     <= {spi_tx_data[6:0], 1'b0};
                        end
                    end

                    spi_clock_counter <= spi_clock_counter == spi_clock_divider ? 0 : spi_clock_counter + 1;

                end

                SPI_STORE: begin
                    if (spi_len_counter == 1) spi_state <= SPI_IDLE;
                    else spi_state <= SPI_ACQUIRE;
                end

                default: spi_state <= SPI_IDLE;

            endcase
        end
    end

    /* AXI INTERFACE */

    localparam AXI_IDLE = 0;  // Idle state
    localparam AXI_WRITE_GET = 1;  // Get write data
    localparam AXI_WRITE_EXEC = 2;  // Execute write command
    localparam AXI_WRITE_RESP = 3;  // Respond to write command
    localparam AXI_READ_SPLIT = 4;  // Split read command: read registers or read synchronous memory
    localparam AXI_READ_REG = 5;  // Read registers
    localparam AXI_READ_MEM0 = 6;  // Issue read to synchronous memory
    localparam AXI_READ_MEM1 = 7;  // Wait for synchronous memory to respond
    localparam AXI_READ_MEM2 = 8;  // Acquire data from synchronous memory
    localparam AXI_READ_RESP = 9;  // Respond to read command
    localparam AXI_WRITE_FAIL = 10;  // Write fail
    localparam AXI_READ_FAIL = 11;  // Read fail

    localparam AXI_SECTION_REG = 0;
    localparam AXI_SECTION_TXBUF = 1;
    localparam AXI_SECTION_RXBUF = 2;

    localparam AXI_ADDR_FREQ = 6'd0;
    localparam AXI_ADDR_CS = 6'd1;
    localparam AXI_ADDR_LEN = 6'd2;

    reg [ 3:0] axi_state;
    reg [11:0] axi_address;
    reg [31:0] axi_write_data, axi_read_data;
    reg [3:0] axi_write_mask;

    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_state      <= AXI_IDLE;
            axi_address    <= 0;
            axi_read_data  <= 0;
            axi_write_data <= 0;
            axi_write_mask <= 0;
        end else
            case (axi_state)
                AXI_IDLE: begin
                    if (awvalid) begin
                        axi_state   <= AXI_WRITE_GET;
                        axi_address <= awaddr;
                    end else if (arvalid) begin
                        axi_state   <= AXI_READ_SPLIT;
                        axi_address <= araddr;
                    end
                end

                AXI_WRITE_GET: begin
                    if (wvalid) begin
                        axi_write_data <= wdata;
                        axi_write_mask <= wstrb;

                        case (axi_address[11:10])
                            AXI_SECTION_REG, AXI_SECTION_TXBUF: axi_state <= AXI_WRITE_EXEC;
                            default: axi_state <= AXI_WRITE_FAIL;
                        endcase
                    end
                end

                AXI_WRITE_EXEC: axi_state <= AXI_WRITE_RESP;

                AXI_WRITE_RESP, AXI_WRITE_FAIL: begin
                    if (bready) axi_state <= AXI_IDLE;
                end

                AXI_READ_SPLIT: begin
                    case (axi_address[11:10])
                        AXI_SECTION_REG: axi_state <= AXI_READ_REG;
                        AXI_SECTION_RXBUF: axi_state <= AXI_READ_MEM0;
                        default: axi_state <= AXI_READ_FAIL;
                    endcase
                end

                AXI_READ_MEM0: axi_state <= AXI_READ_MEM1;
                AXI_READ_MEM1: axi_state <= AXI_READ_MEM2;

                AXI_READ_MEM2: begin
                    axi_state     <= AXI_READ_RESP;
                    axi_read_data <= rx_buf_rdata;
                end

                AXI_READ_REG: begin
                    case (axi_address[7:2])
                        AXI_ADDR_FREQ: axi_read_data <= spi_clock_divider;
                        AXI_ADDR_CS: axi_read_data <= spi_cs_reg;
                        AXI_ADDR_LEN: axi_read_data <= spi_len_counter;
                        default: axi_read_data <= 0;
                    endcase

                    case (axi_address[7:2])
                        AXI_ADDR_FREQ: axi_state <= AXI_READ_RESP;
                        AXI_ADDR_CS: axi_state <= AXI_READ_RESP;
                        AXI_ADDR_LEN: axi_state <= AXI_READ_RESP;
                        default: axi_state <= AXI_READ_FAIL;
                    endcase
                end

                AXI_READ_RESP, AXI_READ_FAIL: begin
                    if (rready) begin
                        axi_state <= AXI_IDLE;
                    end
                end

            endcase
    end

    wire [31:0] axi_wstrb_perbit = {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};

    assign awready = axi_state == AXI_IDLE;
    assign wready = axi_state == AXI_WRITE_GET;
    assign bvalid = axi_state == AXI_WRITE_RESP || axi_state == AXI_WRITE_FAIL;
    assign arready = axi_state == AXI_IDLE;
    assign rvalid = axi_state == AXI_READ_RESP || axi_state == AXI_READ_FAIL;

    assign rdata = axi_read_data;
    assign rresp = axi_state == AXI_READ_FAIL ? 2 : 0;

    assign bresp = axi_state == AXI_WRITE_FAIL ? 2 : 0;

    assign tx_buf_waddr = axi_address[9:2];
    assign tx_buf_wmask = axi_write_mask;
    assign tx_buf_wdata = axi_write_data;
    assign tx_buf_wen = axi_state == AXI_WRITE_EXEC && axi_address[11:10] == AXI_SECTION_TXBUF;

    assign tx_buf_ren = spi_state == SPI_ACQUIRE || spi_state == SPI_ACQUIRE_WAIT;
    assign tx_buf_raddr = spi_storage_addr;

    assign rx_buf_waddr = spi_storage_addr;
    assign rx_buf_wdata = spi_rx_data;
    assign rx_buf_wen = spi_state == SPI_STORE;

    assign rx_buf_raddr = axi_address[9:2];
    assign rx_buf_ren   = (axi_state == AXI_READ_MEM0 || axi_state == AXI_READ_MEM1) && axi_address[11:10] == AXI_SECTION_RXBUF;

    wire [10:0] spi_len_counter_mod = axi_write_data[10:0] & axi_wstrb_perbit[10:0] | spi_len_counter & ~axi_wstrb_perbit[10:0];

    always @(posedge aclk) begin
        if (!aresetn) begin
            spi_clock_divider <= 0;
            spi_cs_reg        <= 0;
            spi_len_counter   <= 0;
            spi_storage_addr  <= 0;
        end else begin
            if (axi_state == AXI_WRITE_EXEC && axi_address[11:10] == AXI_SECTION_REG)
                case (axi_address[7:2])
                    AXI_ADDR_FREQ:
                    spi_clock_divider <= axi_write_data & axi_wstrb_perbit | spi_clock_divider & ~axi_wstrb_perbit;
                    AXI_ADDR_CS:
                    spi_cs_reg <= axi_write_data[0] & axi_wstrb_perbit[0] | spi_cs_reg & ~axi_wstrb_perbit[0];
                    AXI_ADDR_LEN: begin
                        spi_len_counter  <= spi_len_counter_mod > 1024 ? 1024 : spi_len_counter_mod;
                        spi_storage_addr <= 0;
                    end
                endcase
            else begin
                if (spi_state == SPI_STORE) begin
                    spi_len_counter  <= spi_len_counter - 1;
                    spi_storage_addr <= spi_storage_addr + 1;
                end
            end
        end
    end

endmodule
