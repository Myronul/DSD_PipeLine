`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/05/2026 09:19:18 PM
// Design Name: 
// Module Name: system_cntrl_sim
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`include "cpu_macros.vh"
`include "controller_macros.vh"

module ctrl_sim();

reg clk;
reg rst;

// AXI4-Lite signals
wire [3:0]  awaddr;
wire        awvalid;
reg         awready;

wire [31:0] wdata;
wire [3:0]  wstrb;
wire        wvalid;
reg         wready;

reg  [1:0]  bresp;
reg         bvalid;
wire        bready;

wire [3:0]  araddr;
wire        arvalid;
reg         arready;

reg  [31:0] rdata;
reg  [1:0]  rresp;
reg         rvalid;
wire        rready;

// Memory interface
wire [`MC_ADDR_SIZE-1:0] mc_addr;
wire [`MC_DATA_SIZE-1:0] mc_din;
wire [`MC_DATA_SIZE-1:0] mc_dout;
wire                     mc_we;

// CPU control outputs
wire cpu_rst_out;
wire cpu_stop_out;

// mem_ctrl instance
mem_ctrl DUT (
    .clk            (clk),
    .rst            (rst),
    .m_axi_awaddr   (awaddr),
    .m_axi_awvalid  (awvalid),
    .m_axi_awready  (awready),
    .m_axi_wdata    (wdata),
    .m_axi_wstrb    (wstrb),
    .m_axi_wvalid   (wvalid),
    .m_axi_wready   (wready),
    .m_axi_bresp    (bresp),
    .m_axi_bvalid   (bvalid),
    .m_axi_bready   (bready),
    .m_axi_araddr   (araddr),
    .m_axi_arvalid  (arvalid),
    .m_axi_arready  (arready),
    .m_axi_rdata    (rdata),
    .m_axi_rresp    (rresp),
    .m_axi_rvalid   (rvalid),
    .m_axi_rready   (rready),
    .mem_addr       (mc_addr),
    .mem_data_in    (mc_din),
    .mem_data_out   (mc_dout),
    .mem_we         (mc_we),
    .cpu_rst_out    (cpu_rst_out),
    .cpu_stop_out   (cpu_stop_out)
);

// instr_memory instance
instr_memory IMEM (
    .addr    ({`A_SIZE{1'b0}}),
    .dataOut (),
    .clk     (clk),
    .wr_addr (mc_addr),
    .wr_data (mc_din[`INSTR_SIZE-1:0]),
    .wr_en   (mc_we),
    .rd_addr (mc_addr),
    .rd_data (mc_dout)
);

// Byte sequence sent to mem_ctrl (simulates what the host sends over UART)
// Sequence:
//   [0]      CMD_RESET
//   [1]      CMD_STOP
//   [2]      CMD_START
//   [3..10]  CMD_WRITE  addr=0x0005  len=1  data=0x0000C205
reg [7:0] rx_bytes [0:10];
reg [3:0] rx_idx;

// Clock generation
initial clk = 0;
always #5 clk = ~clk;

// Simple AXI UART slave:
//   - write channel: always accepts (awready=wready=1, bvalid follows)
//   - read channel : on STAT_REG return RXVALID=1, on RX_FIFO return next byte
always @(posedge clk or posedge rst) begin
    if (rst) begin
        awready <= 1'b0;
        wready  <= 1'b0;
        bvalid  <= 1'b0;
        arready <= 1'b0;
        rvalid  <= 1'b0;
        rdata   <= 32'h0;
        bresp   <= 2'b00;
        rresp   <= 2'b00;
        rx_idx  <= 4'd0;
    end else begin

        // Write channel - always accept immediately
        awready <= 1'b1;
        wready  <= 1'b1;
        bvalid  <= awvalid & wvalid;
        bresp   <= 2'b00;

        // Read channel - respond one cycle after address is presented
        arready <= arvalid;
        rvalid  <= arvalid;
        rresp   <= 2'b00;

        if (arvalid) begin
            if (araddr == `UART_STAT_REG) begin
                // bit0 = RXVALID=1, bit2 = TXEMPTY=1
                rdata <= 32'h00000005;
            end else begin
                // UART_RX_FIFO: return next byte from predefined sequence
                rdata  <= {24'h0, rx_bytes[rx_idx]};
                rx_idx <= rx_idx + 4'd1;
            end
        end

    end
end

// Stimulus
initial begin
    rx_bytes[0]  = `CMD_RESET;  // 0x01
    rx_bytes[1]  = `CMD_STOP;   // 0x02
    rx_bytes[2]  = `CMD_START;  // 0x03
    rx_bytes[3]  = `CMD_WRITE;  // 0x04
    rx_bytes[4]  = 8'h00;       // ADDR_HI = 0
    rx_bytes[5]  = 8'h05;       // ADDR_LO = 5  ->  word address 0x0005
    rx_bytes[6]  = 8'h01;       // LEN = 1 word
    rx_bytes[7]  = 8'h00;       // word[31:24]  MSB first
    rx_bytes[8]  = 8'h00;       // word[23:16]
    rx_bytes[9]  = 8'hC2;       // word[15:8]   instruction = 0xC205
    rx_bytes[10] = 8'h05;       // word[7:0]    (LOADC R1, 5)

    rx_idx = 4'd0;

    rst = 1'b1;
    #30;
    rst = 1'b0;

    #20000;
    $finish;
end

endmodule