`timescale 1ns / 1ps
`include "cpu_macros.vh"

module write_back_stage(
    input loadMem, /*indicate that the data to write is from the memory*/
    input loadEnable,
    input [`D_SIZE-1:0]dataInMem, /*data from data memory sent by execute 2 cylces stall*/
    input [`D_SIZE-1:0]dataIn, /*from pipeline ex*/
    input [`REG_ADR-1:0]dataDest, /*from pipeline ex*/
    output reg [`REG_ADR-1:0] regAddress, /*data to the registers wb*/
    output reg [`D_SIZE-1:0] regValue
);


always@(*) begin
    if(loadEnable == 1) begin
        regAddress = dataDest;
        regValue = dataIn;
    end
    
    else if(loadMem == 1) begin
         regAddress = dataDest;
         regValue = dataInMem;
         end
end


endmodule
