`timescale 1ns / 1ps
`include"cpu_macros.vh"

module cpu_registers(
    input wire clk,
    /*signals from the read stage*/
    output reg[`D_SIZE-1:0]operandValue1,
    input [`REG_ADR-1:0]operandAddr1,
    output reg[`D_SIZE-1:0]operandValue2,
    input [`REG_ADR-1:0]operandAddr2,
    /*signals from the write back stage*/
    input [`REG_ADR-1:0]regAddress, /*destination*/
    input [`D_SIZE-1:0]regValue, /*result*/
    input enableWb
);

/*defines registers memory*/
reg [`D_SIZE-1:0]REG[7:0]; /*8 registers*/
integer i = 0;

initial begin
    for(i=0;i<8;i=i+1) begin
        REG[i] = 16'h0000;
    end
end

always@(*) begin
    /*read stage - combinational read*/
    operandValue1 = REG[operandAddr1];
    operandValue2 = REG[operandAddr2];    
end

/*sequential writing write back stage*/
always@(posedge clk) begin
    if(enableWb == 1) begin
        REG[regAddress] <= regValue;
    end
end

endmodule