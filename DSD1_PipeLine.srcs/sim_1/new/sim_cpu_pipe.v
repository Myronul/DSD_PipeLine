`timescale 1ns / 1ps

module sim_cpu_pipe();

reg clk;
reg rst;

cpu_pipe dut (
    .clk(clk),
    .rst(rst)
);

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

initial begin
    rst = 1;
    #20;
    rst = 0;
    #200;
end


endmodule
