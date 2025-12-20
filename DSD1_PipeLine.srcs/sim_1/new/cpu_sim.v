`timescale 1ns / 1ps


module cpu_sim();

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
    rst = 1'b1;
    #20;
    rst = 1'b0;
    #500;
    $finish;
end

endmodule
