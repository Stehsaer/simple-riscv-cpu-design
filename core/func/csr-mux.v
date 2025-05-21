`define CSR_INPUT input wire [31:0]

`include "csr-encoding.vh"

module csr_mux (
    input  wire [11:0] addr,
    output reg  [31:0] csr_data,

    output reg fail,

    `CSR_INPUT mvendorid,
    `CSR_INPUT marchid,
    `CSR_INPUT mimpid,
    `CSR_INPUT mhartid,
    `CSR_INPUT mconfigptr,

    `CSR_INPUT mstatus,
    `CSR_INPUT misa,
    `CSR_INPUT mie,
    `CSR_INPUT mtvec,
    `CSR_INPUT mstatush,
    `CSR_INPUT medelegh,

    `CSR_INPUT mscratch,
    `CSR_INPUT mepc,
    `CSR_INPUT mcause,
    `CSR_INPUT mtval,
    `CSR_INPUT mip,

    `CSR_INPUT menvcfg,
    `CSR_INPUT menvcfgh
);

    always @(*) begin
        case (addr)
            `CSR_MVENDORID: csr_data = mvendorid;
            `CSR_MARCHID: csr_data = marchid;
            `CSR_MIMPID: csr_data = mimpid;
            `CSR_MHARTID: csr_data = mhartid;
            `CSR_MCONFIGPTR: csr_data = mconfigptr;
            `CSR_MSTATUS: csr_data = mstatus;
            `CSR_MISA: csr_data = misa;
            `CSR_MIE: csr_data = mie;
            `CSR_MTVEC: csr_data = mtvec;
            `CSR_MSTATUSH: csr_data = mstatush;
            `CSR_MEDELEGH: csr_data = medelegh;
            `CSR_MSCRATCH: csr_data = mscratch;
            `CSR_MEPC: csr_data = mepc;
            `CSR_MCAUSE: csr_data = mcause;
            `CSR_MTVAL: csr_data = mtval;
            `CSR_MIP: csr_data = mip;
            `CSR_MENVCFG: csr_data = menvcfg;
            `CSR_MENVCFGH: csr_data = menvcfgh;

            default: csr_data = 32'b0;
        endcase
    end

    always @(*) begin
        case (addr)
            `CSR_MVENDORID,
            `CSR_MARCHID,
            `CSR_MIMPID,
            `CSR_MHARTID,
            `CSR_MCONFIGPTR,
            `CSR_MSTATUS,
            `CSR_MISA,
            `CSR_MIE,
            `CSR_MTVEC,
            `CSR_MSTATUSH,
            `CSR_MEDELEGH,
            `CSR_MSCRATCH,
            `CSR_MEPC,
            `CSR_MCAUSE,
            `CSR_MTVAL,
            `CSR_MIP,
            `CSR_MENVCFG,
            `CSR_MENVCFGH:
            fail = 0;

            default: fail = 1;
        endcase
    end

endmodule
