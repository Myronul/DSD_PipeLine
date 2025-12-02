`timescale 1ns / 1ps
`include"cpu_macros.vh"

module instr_memory(
    input wire clk,
    input [`A_SIZE-1:0]addr,
    output reg [`INSTR_SIZE-1:0]dataOut
);

reg [`INSTR_SIZE-1:0]instrMemory[`A_SIZE:0]; /*instruction memory A_SIZE locations each of INSTR_SIZE*/


always@(posedge clk) begin
    dataOut <= instrMemory[addr];  
end


endmodule
