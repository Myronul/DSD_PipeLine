`timescale 1ns / 1ps
`include "cpu_macros.vh"

module write_back_stage(
    input loadMem, /*indicate that the data to write is from the memory*/
    input [`D_SIZE-1:0]dataInMem, /*data from data memory 2 cylces stall*/
    input [`D_SIZE-1:0]dataIn, /*from pipeline ex*/
    input [`REG_ADR-1:0]dataDest, /*from pipeline ex*/
    output [`REG_ADR-1:0] regAddress, /*data to the registers wb*/
    output [`D_SIZE-1:0] regValue
);


assign regAddress = dataDest;
assign regValue   = loadMem ? dataInMem : dataIn;



endmodule
