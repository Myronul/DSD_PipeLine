`timescale 1ns / 1ps
`include"cpu_macros.vh"

module instr_memory(
    input [`A_SIZE-1:0]addr,
    output [`INSTR_SIZE-1:0]dataOut
);

reg [`INSTR_SIZE-1:0]instrMemory[0:49]; /*instruction memory A_SIZE locations each of INSTR_SIZE*/
integer i = 0;

initial begin
    for(i=0;i<50;i=i+1) begin
        instrMemory[i] = 16'h0000;
    end
end

initial begin
    instrMemory[0] = 16'b1100001000000111; /*LOADC R2,7*/
    instrMemory[1] = 16'b1100001100000011; /*LOADC R3,3*/
    instrMemory[2] = 16'b1100010000000000; /*LOADC R4,0*/
    instrMemory[3] = 16'b0000000000000000; /*NOP*/
    instrMemory[4] = 16'b0000000000000000; /*NOP*/
    instrMemory[5] = 16'b0000001010010011; /*ADD R2,R2,R3*/
    instrMemory[6] = 16'b0000000000000000;
    instrMemory[7] = 16'b0000000000000000; 
    instrMemory[8] = 16'b0000000000000000;
    instrMemory[9] = 16'b0000000000000000; 
    instrMemory[10] = 16'b0000000000000000; 
    instrMemory[11] = 16'b1010010000000010; /*STORE R4,R2*/
    instrMemory[12] = 16'b0000000000000000;
    instrMemory[13] = 16'b0000000000000000;
    instrMemory[14] = 16'b0000000000000000;
    instrMemory[15] = 16'b0000000000000000;
    instrMemory[16] = 16'b0000000000000000; 
    instrMemory[17] = 16'b1000010000000101; /*LOAD R4,R5*/
    instrMemory[18] = 16'b0000000000000000;
    instrMemory[19] = 16'b0000000000000000;
    instrMemory[20] = 16'b0000000000000000;
    instrMemory[21] = 16'b0000000000000000;
    instrMemory[22] = 16'b1111000000000100; /*JMP R4*/
    instrMemory[23] = 16'b0000000000000000;
    instrMemory[24] = 16'b0000000000000000;
    instrMemory[25] = 16'b0000000000000000;
end


assign dataOut = instrMemory[addr]; /*PC take this data*/


endmodule
