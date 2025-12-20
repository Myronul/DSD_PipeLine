`timescale 1ns / 1ps
`include"cpu_macros.vh"

module instr_memory(
    input [`A_SIZE-1:0]addr,
    output [`INSTR_SIZE-1:0]dataOut
);

reg [`INSTR_SIZE-1:0]instrMemory[0:`A_SIZE-1]; /*instruction memory A_SIZE locations each of INSTR_SIZE*/
integer i = 0;

initial begin
    for(i=0;i<`A_SIZE;i=i+1) begin
        instrMemory[i] = 16'h0000;
    end
end

initial begin
    instrMemory[0] = 16'b0000101001001001;
    instrMemory[1] = 16'b0000101001001001;
    instrMemory[2] = 16'b0000101001001001;
    instrMemory[3] = 16'b0000101001001001;
    instrMemory[4] = 16'b0000101001001001;
    instrMemory[5] = 16'b0000101001001001;
    instrMemory[6] = 16'b0000101001001001;
    instrMemory[7] = 16'b0000101001001001;
    instrMemory[8] = 16'b0000101001001001;
    instrMemory[9] = 16'b0000101001001001;
    instrMemory[10] = 16'b0000101001001001;
    instrMemory[11] = 16'b0000101001001001;
    instrMemory[12] = 16'b0000101001001001;
    instrMemory[13] = 16'b0000101001001001;
    instrMemory[14] = 16'b0000101001001001;
end


assign dataOut = instrMemory[addr]; /*PC take this data*/


endmodule
