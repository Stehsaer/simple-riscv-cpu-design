// |======================|
// | TIMER AXI PERIPHERAL |
// |======================|
//
// | Address | Access | Name
// |---------|--------|-------------
// | 0x00    | R/W    | TIMERL
// | 0x04    | R/W    | TIMERH
// | 0x08    | R/W    | TIMECMPL
// | 0x0C    | R/W    | TIMECMPH
//
// ## TIMERL, TIMERH
//     Forms a 64bit counter that increments every clock cycle unless being written to.
//     When reading from TIMERH, the value of TIMERL is automatically buffered, thus the 64-bit value can be reliably fetched.
//     The 64-bit counter is writable. To avoid unwanted interference,
//         it's recommended to write 0 to TIMERL first, then write TIMERH, at last write the desired value to TIMERL
// ## TIMERCMPL, TIMERCMPH
//     Timer compare value for timer-based interrupt. Interrupt functionality not yet implemented, but reading or writing to the registers are allowed.

module time_axi (
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
    input wire rready
);

    // Timer registers
    reg [63:0] timer_reg;
    reg [63:0] timer_cmp_reg;

    // Buffer low 32bits of timer_reg when reading high 32bits
    reg [31:0] timer_low_temp;
    reg timer_low_temp_valid;

    reg [9:0] axi_address_buffer;
    reg [31:0] axi_data_buffer;
    reg [31:0] axi_write_target;
    reg [3:0] axi_wmask_buffer;

    wire [31:0] ext_wstb = {
        {8{axi_wmask_buffer[3]}},
        {8{axi_wmask_buffer[2]}},
        {8{axi_wmask_buffer[1]}},
        {8{axi_wmask_buffer[0]}}
    };
    wire [31:0] write_result = (axi_write_target & ~ext_wstb) | (axi_data_buffer & ext_wstb);

    wire timer_trigger = timer_reg == timer_cmp_reg;

    reg [2:0] state;

    localparam STATE_IDLE = 0;
    localparam STATE_WRITE = 1;
    localparam STATE_WRITE_RESP = 2;
    localparam STATE_READ = 3;
    localparam STATE_READ_RESPONSE = 4;

    localparam ADDR_TIMERL = 0;
    localparam ADDR_TIMERH = 1;
    localparam ADDR_TIMECMPL = 2;
    localparam ADDR_TIMECMPH = 3;

    always @(posedge aclk) begin
        if (!aresetn) begin
            timer_reg            <= 64'h0;
            timer_cmp_reg        <= 64'h0;
            timer_low_temp_valid <= 0;
        end else begin

            // Timer register
            if (state == STATE_WRITE_RESP) begin
                case (axi_address_buffer)
                    ADDR_TIMERL:   timer_reg[31:0] <= write_result;
                    ADDR_TIMERH:   timer_reg[63:32] <= write_result;
                    ADDR_TIMECMPL: timer_cmp_reg[31:0] <= write_result;
                    ADDR_TIMECMPH: timer_cmp_reg[63:32] <= write_result;
                endcase
            end else timer_reg <= timer_reg + 1;

            case (state)
                STATE_IDLE: begin
                    if (awvalid) begin  // Write gets higher priority
                        axi_address_buffer <= awaddr[11:2];
                        axi_data_buffer    <= wdata;
                        state              <= STATE_WRITE;
                    end else if (arvalid) begin
                        axi_address_buffer <= araddr[11:2];
                        state              <= STATE_READ;
                    end
                end
                STATE_WRITE: begin
                    if (wvalid) begin
                        state            <= STATE_WRITE_RESP;
                        axi_data_buffer  <= wdata;
                        axi_wmask_buffer <= wstrb;

                        case (axi_address_buffer)
                            ADDR_TIMERL: axi_write_target <= timer_reg[31:0];
                            ADDR_TIMERH: axi_write_target <= timer_reg[63:32];
                            ADDR_TIMECMPL: axi_write_target <= timer_cmp_reg[31:0];
                            ADDR_TIMECMPH: axi_write_target <= timer_cmp_reg[63:32];
                            default: axi_write_target <= 32'h0;
                        endcase
                    end
                end
                STATE_WRITE_RESP: begin
                    if (bready) begin
                        state <= STATE_IDLE;
                    end
                end
                STATE_READ: begin
                    state <= STATE_READ_RESPONSE;

                    case (axi_address_buffer)
                        ADDR_TIMERL: begin
                            if (timer_low_temp_valid) begin
                                axi_data_buffer      <= timer_low_temp;
                                timer_low_temp_valid <= 0;
                            end else begin
                                axi_data_buffer <= timer_reg[31:0];
                            end
                        end
                        ADDR_TIMERH: begin
                            timer_low_temp_valid <= 1;
                            timer_low_temp       <= timer_reg[31:0];
                            axi_data_buffer      <= timer_reg[63:32];
                        end
                        ADDR_TIMECMPL: axi_data_buffer <= timer_cmp_reg[31:0];
                        ADDR_TIMECMPH: axi_data_buffer <= timer_cmp_reg[63:32];
                        default: axi_data_buffer <= 32'h0;
                    endcase
                end
                STATE_READ_RESPONSE: begin
                    if (rready) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    assign wready  = state == STATE_WRITE;
    assign bresp   = axi_address_buffer < 4 ? 2'b00 : 2'b11;
    assign bvalid  = state == STATE_WRITE_RESP;
    assign rvalid  = state == STATE_READ_RESPONSE;
    assign rdata   = axi_data_buffer;
    assign rresp   = bresp;
    assign arready = state == STATE_IDLE;
    assign awready = state == STATE_IDLE;

endmodule
