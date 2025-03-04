// |=====================|
// | UART AXI Peripheral |
// |=====================|
//
// | Address | Access | Name
// |---------|--------|-------------
// | 0x00    | W      | TX
// | 0x04    | R      | RX
// | 0x08    | R/W    | CFG
// | 0x0C    | R/W    | STATUS
//
// ## TX
//     Writing to TX will put the char into transmitting FIFO, eventually gets transmitted
// ## RX
//     Reading from RX will extract one char from receiving FIFO
// ## CFG
//     Config Register
//     - [23: 0] Baudrate divider
//     - [26:24] Parity config, see ONFIG CONSTANTS in the code
//     - [27:27] Stopbits config, see ONFIG CONSTANTS in the code
// ## STATUS
//     Status Register
//     - [0] Receiving FIFO not empty
//     - [1] Transmitting FIFO not full
//     - [2] Parity error, write 0 to clear

module uart_axi (

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

    /* PHY */
    input  wire rx,
    output reg  tx
);
    wire clk = aclk;
    wire rstn = aresetn;

    /* CONFIG REGISTERS */

    reg [31:0] config_reg;

    wire [23:0] config_divisor = config_reg[23:0];
    wire [0:0] stop_bits = config_reg[27:27];
    wire [2:0] parity = config_reg[26:24];

    /* CONFIG CONSTANTS */

    localparam PARITY_OFF = 3'b000;
    localparam PARITY_ODD = 3'b001;
    localparam PARITY_EVEN = 3'b010;
    localparam PARITY_ZERO = 3'b100;
    localparam PARITY_ONE = 3'b101;

    localparam STOPBIT_1 = 1'b0;
    localparam STOPBIT_2 = 1'b1;

    /* STATE */
    wire tx_available;
    wire rx_available;

    reg  parity_error;
    reg  parity_clear;

    /* CLOCK GENERATOR */

    wire tx_clock_enable, rx_clock_enable;

    reg [23:0] tx_clock_counter, rx_clock_counter;

    // TX clock
    always @(posedge clk) begin
        if (!rstn || tx_clock_counter == config_divisor || tx_clock_counter == 0)
            tx_clock_counter <= 1;
        else if (tx_clock_enable) tx_clock_counter <= tx_clock_counter + 1;
        else tx_clock_counter <= 1;
    end

    wire tx_clock_actuate = tx_clock_counter == 1;

    // RX clock
    always @(posedge clk) begin
        if (!rstn || rx_clock_counter == config_divisor || rx_clock_counter == 0)
            rx_clock_counter <= 1;
        else if (rx_clock_enable) rx_clock_counter <= rx_clock_counter + 1;
        else rx_clock_counter <= 1;
    end

    wire rx_clock_actuate = rx_clock_counter == (config_divisor >> 1);  // trigger at half period

    /* FIFO */

    // Automatically fetch data from TX FIFO when:
    // - UART is ready to transmit
    // - TX FIFO not empty

    localparam TX_AUTOFETCH_EMPTY = 0;
    localparam TX_AUTOFETCH_READ = 1;
    localparam TX_AUTOFETCH_READBACK = 2;
    localparam TX_AUTOFETCH_VALID = 3;

    reg [7:0] tx_autofetch_data;
    reg [1:0] tx_autofetch_state;
    wire tx_data_sent;

    wire [7:0] tx_fifo_dout, tx_fifo_din;
    wire tx_fifo_empty, tx_fifo_full, tx_fifo_rd_en, tx_fifo_wr_en;

    fifo_8x256 tx_fifo (
        .clk  (clk),
        .srst (!rstn),
        .din  (tx_fifo_din),
        .wr_en(tx_fifo_wr_en),
        .rd_en(tx_fifo_rd_en),
        .dout (tx_fifo_dout),
        .empty(tx_fifo_empty),
        .full (tx_fifo_full)
    );

    always @(posedge clk) begin
        if (!rstn) begin
            tx_autofetch_data  <= 8'h00;
            tx_autofetch_state <= TX_AUTOFETCH_EMPTY;
        end else
            case (tx_autofetch_state)
                TX_AUTOFETCH_EMPTY:
                if (!tx_fifo_empty && !tx_data_sent) tx_autofetch_state <= TX_AUTOFETCH_READ;

                TX_AUTOFETCH_READ: tx_autofetch_state <= TX_AUTOFETCH_READBACK;

                TX_AUTOFETCH_READBACK: begin
                    tx_autofetch_state <= TX_AUTOFETCH_VALID;
                    tx_autofetch_data  <= tx_fifo_dout;
                end

                TX_AUTOFETCH_VALID: if (tx_data_sent) tx_autofetch_state <= TX_AUTOFETCH_EMPTY;
            endcase
    end

    assign tx_fifo_rd_en = tx_autofetch_state == TX_AUTOFETCH_READ;
    assign tx_available  = !tx_fifo_full;

    // RX FIFO

    wire [7:0] rx_fifo_dout, rx_fifo_din;
    wire rx_fifo_empty, rx_fifo_full, rx_fifo_rd_en, rx_fifo_wr_en;

    fifo_8x256 rx_fifo (
        .clk  (clk),
        .srst (!rstn),
        .din  (rx_fifo_din),
        .wr_en(rx_fifo_wr_en),
        .rd_en(rx_fifo_rd_en),
        .dout (rx_fifo_dout),
        .empty(rx_fifo_empty),
        .full (rx_fifo_full)
    );

    assign rx_available = !rx_fifo_empty;

    /* UART STATE CONTROL */

    reg [3:0] tx_state, rx_state;

    localparam UART_IDLE = 0;
    localparam UART_START = 1;  // Start bit
    localparam UART_DATA_0 = 2;  // Data bit 0
    localparam UART_DATA_1 = 3;
    localparam UART_DATA_2 = 4;
    localparam UART_DATA_3 = 5;
    localparam UART_DATA_4 = 6;
    localparam UART_DATA_5 = 7;
    localparam UART_DATA_6 = 8;
    localparam UART_DATA_7 = 9;
    localparam UART_DATA_PARITY = 10;  // Parity bit
    localparam UART_STOP_0 = 11;  // Stop Bit 1
    localparam UART_STOP_1 = 12;  // Stop Bit 2
    localparam UART_END = 13;  // End of transmission

    // ===== TX =====

    reg [8:0] tx_shift_reg;

    reg tx_parity_bit;

    always @(*)
        case (parity)
            PARITY_OFF: tx_parity_bit = 1'b0;
            PARITY_ODD: tx_parity_bit = ^tx_autofetch_state;
            PARITY_EVEN: tx_parity_bit = ~^tx_autofetch_state;
            PARITY_ZERO: tx_parity_bit = 1'b0;
            PARITY_ONE: tx_parity_bit = 1'b1;
            default: tx_parity_bit = 1'b0;
        endcase

    always @(posedge clk) begin
        if (!rstn) begin
            tx_state <= UART_IDLE;
            tx       <= 1;
        end else
            case (tx_state)

                UART_IDLE: begin
                    if (tx_autofetch_state == TX_AUTOFETCH_VALID) begin
                        tx_shift_reg <= {tx_parity_bit, tx_autofetch_data};
                        tx_state     <= UART_START;
                    end

                    tx <= 1;
                end

                UART_START:
                if (tx_clock_actuate) begin
                    tx       <= 0;
                    tx_state <= UART_DATA_0;
                end

                UART_DATA_0:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_DATA_1;
                end

                UART_DATA_1:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_DATA_2;
                end

                UART_DATA_2:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_DATA_3;
                end

                UART_DATA_3:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_DATA_4;
                end

                UART_DATA_4:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_DATA_5;
                end

                UART_DATA_5:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_DATA_6;
                end

                UART_DATA_6:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_DATA_7;
                end

                UART_DATA_7:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};

                    if (parity != PARITY_OFF) tx_state <= UART_DATA_PARITY;
                    else tx_state <= UART_STOP_0;
                end

                UART_DATA_PARITY:
                if (tx_clock_actuate) begin
                    tx           <= tx_shift_reg[0];
                    tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                    tx_state     <= UART_STOP_0;
                end

                UART_STOP_0:
                if (tx_clock_actuate) begin
                    tx <= 1;
                    if (stop_bits == STOPBIT_2) tx_state <= UART_STOP_1;
                    else tx_state <= UART_END;
                end

                UART_STOP_1:
                if (tx_clock_actuate) begin
                    tx       <= 1;
                    tx_state <= UART_END;
                end

                UART_END: if (tx_clock_actuate) tx_state <= UART_IDLE;

            endcase
    end

    assign tx_data_sent    = tx_state == UART_STOP_0;
    assign tx_clock_enable = tx_state != UART_IDLE;

    // ===== RX =====

    reg [8:0] rx_shift_reg;

    reg parity_error_calc;

    // Eliminate indeterminate values

    reg rx_sync1, rx_sync2, rx_sync3, rx_sync4;

    always @(posedge clk) begin
        if (!rstn) begin
            rx_sync1 <= 1;
            rx_sync2 <= 1;
            rx_sync3 <= 1;
            rx_sync4 <= 1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
            rx_sync3 <= rx_sync2;
            rx_sync4 <= rx_sync3;
        end
    end

    always @(*)
        case (parity)
            PARITY_OFF: parity_error_calc = 0;
            PARITY_ODD: parity_error_calc = ~^rx_shift_reg;
            PARITY_EVEN: parity_error_calc = ^rx_shift_reg;
            PARITY_ZERO: parity_error_calc = rx_shift_reg[8];
            PARITY_ONE: parity_error_calc = ~rx_shift_reg[8];
            default: parity_error_calc = 1;
        endcase

    always @(posedge clk) begin
        if (!rstn) begin
            rx_shift_reg <= 9'h00;
            parity_error <= 0;
            rx_state     <= UART_IDLE;
        end else
            case (rx_state)

                UART_IDLE: begin
                    if (!rx_sync3 && rx_sync4) begin
                        rx_shift_reg <= 9'h00;
                        rx_state     <= UART_START;
                    end

                    if (parity_clear == 0) parity_error <= 0;
                end

                UART_START: if (rx_clock_actuate) rx_state <= UART_DATA_0;

                UART_DATA_0:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_DATA_1;
                end

                UART_DATA_1:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_DATA_2;
                end

                UART_DATA_2:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_DATA_3;
                end

                UART_DATA_3:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_DATA_4;
                end

                UART_DATA_4:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_DATA_5;
                end

                UART_DATA_5:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_DATA_6;
                end

                UART_DATA_6:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_DATA_7;
                end

                UART_DATA_7:
                if (rx_clock_actuate) begin
                    if (parity != PARITY_OFF) begin
                        rx_state     <= UART_DATA_PARITY;
                        rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    end else begin
                        rx_state     <= UART_STOP_0;
                        rx_shift_reg <= {1'b0, rx_sync4, rx_shift_reg[8:2]};
                    end
                end

                UART_DATA_PARITY:
                if (rx_clock_actuate) begin
                    rx_shift_reg <= {rx_sync4, rx_shift_reg[8:1]};
                    rx_state     <= UART_STOP_0;
                end

                UART_STOP_0:
                if (rx_clock_actuate) begin
                    if (stop_bits == STOPBIT_2) rx_state <= UART_STOP_1;
                    else rx_state <= UART_END;

                    parity_error <= parity_error_calc;
                end

                UART_STOP_1:
                if (rx_clock_actuate) begin
                    rx_state <= UART_END;
                end

                UART_END: rx_state <= UART_IDLE;

            endcase
    end

    assign rx_clock_enable = rx_state != UART_IDLE;

    assign rx_fifo_din     = rx_shift_reg[7:0];
    assign rx_fifo_wr_en   = rx_state == UART_END && !parity_error;

    /* AXI STATE CONTROL */

    reg [2:0] axi_state;

    localparam AXI_IDLE = 0;
    localparam AXI_WRITE_DATA = 1;  // Execute asynchronous write, issue synchronous write
    localparam AXI_WRITE_RESP = 2;  // Write response
    localparam AXI_READ_EXECUTE = 3;  // Issue synchronous read
    localparam AXI_READ_DATA = 4;  // Save acquired data into register
    localparam AXI_READ_BACK = 5;  // Send back data

    reg [5:0] araddr_reg, awaddr_reg;
    reg [31:0] wdata_reg, rdata_reg;
    reg [3:0] wstrb_reg;
    wire [31:0] wstrb_bitmask = {
        {8{wstrb_reg[3]}}, {8{wstrb_reg[2]}}, {8{wstrb_reg[1]}}, {8{wstrb_reg[0]}}
    };

    localparam ADDR_TX = 0;
    localparam ADDR_RX = 1;
    localparam ADDR_CFG = 2;
    localparam ADDR_STAT = 3;

    assign awready = axi_state == AXI_IDLE;

    assign arready = axi_state == AXI_IDLE;

    assign wready = axi_state == AXI_WRITE_DATA;
    assign bresp = 2'b0;

    assign bvalid = axi_state == AXI_WRITE_RESP;

    assign rvalid = axi_state == AXI_READ_BACK;
    assign rresp = 2'b0;
    assign rdata = rdata_reg;

    assign rx_fifo_rd_en = axi_state == AXI_READ_EXECUTE && araddr_reg == ADDR_RX;

    assign tx_fifo_wr_en = axi_state == AXI_WRITE_RESP && awaddr_reg == ADDR_TX && wstrb_reg[0] && bready;
    assign tx_fifo_din = wdata_reg[7:0];

    always @(posedge clk) begin
        if (!rstn) begin
            axi_state    <= AXI_IDLE;
            wdata_reg    <= 0;
            wstrb_reg    <= 0;
            rdata_reg    <= 0;
            config_reg   <= 0;
            parity_clear <= 1;
        end else
            case (axi_state)
                AXI_IDLE: begin
                    // Store address for later use
                    if (awvalid) begin
                        awaddr_reg <= awaddr[7:2];
                        axi_state  <= AXI_WRITE_DATA;
                    end else if (arvalid) begin
                        araddr_reg <= araddr[7:2];
                        axi_state  <= AXI_READ_EXECUTE;
                    end

                    if (parity_error == 0) parity_clear <= 1;
                end

                AXI_WRITE_DATA:
                if (wvalid) begin  // Receive write data and write strobe
                    wdata_reg <= wdata;
                    wstrb_reg <= wstrb;
                    axi_state <= AXI_WRITE_RESP;
                end

                AXI_WRITE_RESP:
                if (bready) begin
                    axi_state <= AXI_IDLE;

                    // Execute register write
                    case (awaddr_reg)
                        ADDR_CFG:
                        config_reg <= wdata_reg & wstrb_bitmask | config_reg & ~wstrb_bitmask;
                        ADDR_STAT: begin
                            parity_clear <= wdata_reg[2] & wstrb_bitmask[2] | parity_error & ~wstrb_bitmask[2];
                        end
                    endcase
                end

                AXI_READ_EXECUTE: axi_state <= AXI_READ_DATA;

                AXI_READ_DATA: begin
                    axi_state <= AXI_READ_BACK;

                    case (araddr_reg)
                        ADDR_RX:   rdata_reg <= rx_fifo_dout;
                        ADDR_CFG:  rdata_reg <= config_reg;
                        ADDR_STAT: rdata_reg <= {parity_error, tx_available, rx_available};
                        default:   rdata_reg <= 0;
                    endcase
                end

                AXI_READ_BACK: if (rready) axi_state <= AXI_IDLE;
            endcase
    end

endmodule
