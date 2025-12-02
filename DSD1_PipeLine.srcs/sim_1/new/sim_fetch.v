`timescale 1ns / 1ps

module sim_fetch();


reg clk;
reg rst;
reg [31:0] jmpPC;
reg pc_wr_enable;
wire [31:0] PC;
wire [31:0] IR;


fetch_stage dut (
    .clk(clk),
    .rst(rst),
    .jmpPC(jmpPC),
    .pc_wr_enable(pc_wr_enable),
    .PC(PC),
    .IR(IR)
);

always begin
    clk = 0; #5;
    clk = 1; #5;
end

initial begin

    rst = 1;
    pc_wr_enable = 0;
    jmpPC = 0;
    #20;

    rst = 0;  

    #40;

    //Test jump PC

    pc_wr_enable = 1;
    jmpPC = 2;     
    #10;
    pc_wr_enable = 0;

    #40;
    $stop;
end

endmodule

