`timescale 1ns / 1ps
`include "cpu_macros.vh"

module write_back_stage(
    input loadMem, /*indicate that the data to write is from the memory*/
    input loadEnable,
    input [`D_SIZE-1:0]dataInMem, /*data from data memory*/
    input [`D_SIZE-1:0]dataIn, /*from pipeline ex*/
    input [`REG_ADR-1:0]dataDest, /*from pipeline ex*/
    output reg [`REG_ADR-1:0] regAddress, /*data to the registers wb*/
    output reg [`D_SIZE-1:0] regValue,
    output reg enableWb, /*write data regfile*/
    
    input [7:0] wbIndexIn, 
    output [7:0] wbIndexOut /*signal to IW end instruction*/
);

assign wbIndexOut = wbIndexIn; /*IW check on rising edge new value*/

always@(*) begin
    regAddress = 0;
    regValue = 0;
    enableWb = 0;
    
    if(loadEnable == 1) begin
        regAddress = dataDest;
        regValue = dataIn;
        enableWb = 1;
    end
    else if(loadMem == 1) begin
        regAddress = dataDest;
        regValue = dataInMem;
        enableWb = 1;
    end
end

endmodule