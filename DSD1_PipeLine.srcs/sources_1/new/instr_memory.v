`timescale 1ns / 1ps
`include"cpu_macros.vh"

module instr_memory(
    input [`A_SIZE-1:0]addr,
    output [`INSTR_SIZE-1:0]dataOut
);

reg [`INSTR_SIZE-1:0]instrMemory[0:(`A_SIZE)-1]; /*instruction memory A_SIZE locations each of INSTR_SIZE*/
integer i = 0;

initial begin
    for(i=0;i<(`A_SIZE);i=i+1) begin
        instrMemory[i] = 16'h0000;
    end
end

initial begin
    instrMemory[0] = 16'b1100001000000111; /*LOADC R2,7*/
    instrMemory[1] = 16'b1100001100000011; /*LOADC R3,3*/
    instrMemory[2] = 16'b0000000000000000; /*NOP*/
    instrMemory[3] = 16'b0000000000000000; /*NOP*/
    instrMemory[4] = 16'b0000000000000000; /*NOP*/
    instrMemory[5] = 16'b0000001010010011; /*ADD R2,R2,R3*/
    instrMemory[6] = 16'b0000000000000000;
    instrMemory[7] = 16'b0000000000000000;
    instrMemory[8] = 16'b0000000000000000;
    instrMemory[9] = 16'b0000000000000000;
    instrMemory[10] = 16'b0000000000000000;
    instrMemory[11] = 16'b0000000000000000;
    instrMemory[12] = 16'b0000000000000000;
    instrMemory[13] = 16'b0000000000000000;
    instrMemory[14] = 16'b0000000000000000;
    instrMemory[15] = 16'b0000000000000000;
    instrMemory[16] = 16'b0000000000000000;
    instrMemory[17] = 16'b0000000000000000;
    instrMemory[18] = 16'b0000000000000000;
end


assign dataOut = instrMemory[addr]; /*PC take this data*/


endmodule
