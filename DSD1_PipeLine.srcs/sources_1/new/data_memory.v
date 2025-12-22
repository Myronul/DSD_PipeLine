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

reg [`D_SIZE-1:0]MemData[(`A_SIZE)-1:0];

reg [1:0]state=0;
reg [`A_SIZE-1:0]RegAddr;

integer i;
initial begin
for(i=0;i<(`A_SIZE);i=i+1)begin
    MemData[i] = 0;
end
RegAddr = 0;
end


always@(posedge clk) begin  
    if (memRd == 1) begin
        RegAddr <= dataMemAddr;
    end
end

always@(*) begin
    /*value taken next clock by cpu*/
    dataMemDataout = MemData[RegAddr];
end


always@(posedge clk) begin
    if (memWr == 1) begin
        MemData[dataMemAddr] <= dataMemDatain;
    end
end



endmodule
