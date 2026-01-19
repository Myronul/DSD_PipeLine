`timescale 1ns / 1ps
`include "cpu_macros.vh"

module fetch_stage(
    input wire clk,
    input wire rst,
    input wire [`A_SIZE-1:0] jmpPC, /*new adr for pc sent by EXECUTE stage*/
    input wire pc_wr_enable,
    input flush, /*flush signal from execute jmp instr*/
    input stall, /*stall sgn from IW*/
    
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
        IR <= 16'h0000;
    end else begin
        if (pc_wr_enable) begin
            /*jump executed - flush pipeline and update PC*/
            IR <= 16'h0000;  // NOP
            PC <= jmpPC;
        end else if (stall) begin
            /*IW is full or hazard detected - hold everything*/
            PC <= PC;
            IR <= IR;
        end else begin
            /*normal operation - fetch next instruction*/
            IR <= instMemData;
            PC <= PC + 1;
        end
    end
end

endmodule