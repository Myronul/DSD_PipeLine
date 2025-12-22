`timescale 1ns / 1ps

`include "cpu_macros.vh"
`define MEM_SIZE 32

module fetch_stage(
    input wire clk,
    input wire rst,
    input wire [`A_SIZE-1:0] jmpPC, /*new adr for pc sent by EXECUTE stage*/
    input wire pc_wr_enable,
    input flush, /*flush signal from execute jmp instr*/
    
    output reg [`A_SIZE-1:0] PC, /*update the PC*/
    output reg [`INSTR_SIZE-1:0] IR /*output the instruction in the pipeline register*/   
);

wire [`INSTR_SIZE-1:0] instMemData;

/*instantiere memorie*/
instr_memory MEM (
    .addr(PC),
    .dataOut(instMemData)
);


always @(posedge clk or posedge rst) begin
    if (rst) begin
        PC <= 0;
        IR <= 0;
    end else begin
        if(flush) begin
            IR <= 16'h0000; /*NOP*/
        end
        else begin
            IR <= instMemData;
        end
        
        if(pc_wr_enable)
            PC <= jmpPC;
        else
            PC <= PC + 1;
    end
end


endmodule
