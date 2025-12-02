`timescale 1ns / 1ps

module execute_stage(
    input clk,
    /*signals from the read stage to the execute*/
    input [`REG_ADR-1:0]RRop1, /*Read register that will contain: OP1 | OP2 | DEST */
    input [`REG_ADR-1:0]RRop2,
    input [`REG_ADR-1:0]RRdest,
    input [`OPCODE_SIZE-1:0]RRopcode, /*the opcode of the instrction*/
    /*output data to the write back stage*/
    output [`D_SIZE-1:0]dataOut,
    /*signals for the memory data*/
    output [`A_SIZE-1:0]addrMem,
    output [`D_SIZE-1:0]dataOutMem
);


endmodule
