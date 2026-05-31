`timescale 1ns / 1ps
`include "cpu_macros.vh"
`include "controller_macros.vh"

module module_system_tb;

    reg clk;
    reg rst;
    reg uart_rxd;
    wire uart_txd;

    // Instantiate the full top-level design
    ModuleTop UUT (
        .clk      (clk),
        .rst      (rst),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd)
    );

    parameter BIT_PERIOD = 100; // 100 ns per bit = 10 MHz serial bit rate for simulation

    // UART transmit task (LSB first, 1 stop bit, no parity)
    task send_uart_byte;
        input [7:0] byte;
        integer k;
        begin
            uart_rxd = 1'b0; // start bit
            #(BIT_PERIOD);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rxd = byte[k];
                #(BIT_PERIOD);
            end
            uart_rxd = 1'b1; // stop bit
            #(BIT_PERIOD);
            #(BIT_PERIOD); // small gap between bytes
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        uart_rxd = 1'b1;
        #100;
        rst = 1'b0;
        #1000;

        send_uart_byte(`CMD_RESET);
        send_uart_byte(`CMD_STOP);
        send_uart_byte(`CMD_START);

        send_uart_byte(`CMD_INST_BEGIN);
        send_uart_byte(8'h00);
        send_uart_byte(8'h10);
        send_uart_byte(8'h00);
        send_uart_byte(8'h03);

        send_uart_byte(8'hC2);
        send_uart_byte(8'h07);
        send_uart_byte(8'hC2);
        send_uart_byte(8'h05);
        send_uart_byte(8'h00);
        send_uart_byte(8'h00);

        #20000;
        $finish;
    end

    always #5 clk = ~clk;

endmodule
