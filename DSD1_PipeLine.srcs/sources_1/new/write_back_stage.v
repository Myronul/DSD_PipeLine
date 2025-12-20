`timescale 1ns / 1ps


module write_back_stage(
    input clk,
    input rst,
    input [`D_SIZE-1:0]dataInMem, /*data from data memory 2 cylces stall*/
    input [`D_SIZE-1:0]dataIn,
    input [`REG_ADR-1:0]dataDest,
    output [`REG_ADR-1:0] regAddress, /*data to the registers wb*/
    output [`D_SIZE-1:0] regValue
);





endmodule
