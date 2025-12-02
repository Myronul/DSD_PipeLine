`timescale 1ns / 1ps
`include"cpu_macros.vh"
/*syncronous data memory with 2 latency clk for data read*/

module data_memory(
    input clk,
    input memRd,
    input memWr,
    input[`A_SIZE-1:0]dataMemAddr,
    input [`D_SIZE-1:0]dataMemDatain,
    output reg [`D_SIZE-1:0]dataMemDataout
);

reg [`D_SIZE-1:0]MemData[`A_SIZE-1:0];

reg [1:0]state=0;
reg [`A_SIZE-1:0]RegAddr;
reg [`D_SIZE-1:0]RegData;

always@(posedge clk) begin  
    case(state)
        0: begin /*execute stage*/
           if(memRd == 1) begin
                RegAddr <= dataMemAddr;
                state <= 1;
                end
           if(memWr == 1) begin /*data ready!*/
                MemData[dataMemAddr] <= dataMemDatain;
                end
           end
           
        1: begin /*writeback stage*/
           if(memRd == 1) begin
                dataMemDataout <= RegData;
                state <= 0;
           end
        end
    endcase
end

always@(*) begin
   RegData = MemData[RegAddr];    
end


endmodule
