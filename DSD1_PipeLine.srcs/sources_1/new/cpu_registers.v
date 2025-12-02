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
    input [`D_SIZE-1:0]regValue /*result*/
);

/*defines registers memory*/
reg [`D_SIZE-1:0]REG[`REG_ADR-1:0]; /*8 registers*/

always@(*) begin
    /*read stage*/
    operandValue1 = REG[operandAddr1];
    operandValue2 = REG[operandAddr2];    
end


/*sequential writing write back stage*/
always@(posedge clk) begin
    REG[regAddress] <= regValue;
end


endmodule
