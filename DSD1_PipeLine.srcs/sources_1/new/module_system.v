`timescale 1ns / 1ps
`include "cpu_macros.vh"
`include "controller_macros.vh"

// ============================================================
//  ModuleTop.v  -  System Top Level
//
//  Hierarchy:
//    ModuleTop
//    ??? cpu_pipe        - Simple RISC pipeline
//    ??? instr_memory    - Instruction memory (pseudo dual-port)
//    ?     Port A (write) <- mem_ctrl  (UART programming)
//    ?     Port B (read)  -> cpu_pipe  (fetch stage)
//    ??? mem_ctrl        - Memory / UART controller (AXI master)
//    ??? axi_uartlite_0  - Xilinx UART Lite (AXI slave)
//
//  Notes:
//    - mem_ctrl programs instr_memory through Port A via UART
//    - CPU reads instructions through Port B (read-only, async)
//    - cpu_stop_out from mem_ctrl is declared but not yet wired
//      into cpu_pipe (ext_stop port pending in fetch_stage)
//    - mc_mem_addr is MC_ADDR_SIZE (16-bit) to match mem_ctrl
//      output exactly - no bit truncation or zero-padding needed
//    - mc_mem_dout is 32-bit and driven entirely by instr_memory
//      rd_data port (upper bits are 0 inside instr_memory)
// ============================================================

module ModuleTop (
    input  wire clk,
    input  wire rst,
    input  wire uart_rxd,   // UART receive pin  (board -> FPGA)
    output wire uart_txd    // UART transmit pin (FPGA -> board)
);

    // ----------------------------------------------------------
    // AXI4-Lite wires between mem_ctrl (master) and
    // axi_uartlite_0 (slave).
    // ----------------------------------------------------------

    // Write address channel
    wire [3:0]  s_axi_awaddr;
    wire        s_axi_awvalid;
    wire        s_axi_awready;

    // Write data channel
    wire [31:0] s_axi_wdata;
    wire [3:0]  s_axi_wstrb;
    wire        s_axi_wvalid;
    wire        s_axi_wready;

    // Write response channel
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    wire        s_axi_bready;

    // Read address channel
    wire [3:0]  s_axi_araddr;
    wire        s_axi_arvalid;
    wire        s_axi_arready;

    // Read data channel
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    wire        s_axi_rready;

    // ----------------------------------------------------------
    // CPU control wires (mem_ctrl -> cpu_pipe)
    // ----------------------------------------------------------
    wire cpu_rst_pulse;  // 1-cycle reset pulse from mem_ctrl
    wire cpu_stop;       // freeze CPU when high (pending: wire into fetch_stage)

    // Combine board reset and controller-issued reset
    wire cpu_effective_rst = rst | cpu_rst_pulse;

    // ----------------------------------------------------------
    // Instruction memory interface wires
    //
    //  Port A  -  mem_ctrl (write when programming via UART)
    //  Port B  -  cpu_pipe fetch stage (read instructions)
    //
    //  mc_mem_addr is MC_ADDR_SIZE wide to match mem_ctrl exactly.
    //  instr_memory wr_addr and rd_addr ports are also MC_ADDR_SIZE
    //  so the connection is direct with no bit manipulation.
    //  mc_mem_dout is 32-bit and driven entirely by instr_memory
    //  rd_data (upper bits are zeroed inside instr_memory).
    // ----------------------------------------------------------

    // Port A: mem_ctrl -> instr_memory (write)
    wire [`MC_ADDR_SIZE-1:0] mc_mem_addr;   // word address from controller
    wire [31:0]              mc_mem_din;    // data to write into memory
    wire [31:0]              mc_mem_dout;   // readback from memory to controller
    wire                     mc_mem_we;     // write enable from controller

    // Port B: cpu_pipe -> instr_memory (read)
    wire [`A_SIZE-1:0]       PC;            // current program counter
    wire [`INSTR_SIZE-1:0]   instr_data;    // instruction word to CPU

    // ----------------------------------------------------------
    // UART interrupt (unused in this design, can be tied off)
    // ----------------------------------------------------------
    wire uart_interrupt;

    // ==========================================================
    //  INSTANCES
    // ==========================================================

    // ----------------------------------------------------------
    //  cpu_pipe - Simple RISC processor pipeline
    // ----------------------------------------------------------
    cpu_pipe CPU (
        .clk      (clk),
        .rst      (cpu_effective_rst),
        .PC_cpu   (PC),
        .data_cpu (instr_data)
    );

    // ----------------------------------------------------------
    //  instr_memory - Pseudo dual-port instruction memory
    //
    //  Port A (write) <- mem_ctrl
    //    wr_addr : MC_ADDR_SIZE wide, direct from mc_mem_addr
    //    wr_data : lower INSTR_SIZE bits of mc_mem_din
    //    wr_en   : direct from mem_ctrl
    //
    //  Port B (read) -> cpu_pipe fetch stage
    //    addr    : current PC from cpu_pipe (A_SIZE wide)
    //    dataOut : instruction word back to cpu_pipe
    //
    //  Readback -> mem_ctrl (for CMD_READ)
    //    rd_addr : MC_ADDR_SIZE wide, direct from mc_mem_addr
    //    rd_data : 32-bit, upper bits zeroed inside instr_memory,
    //              connected directly to mc_mem_dout (no conflicts)
    // ----------------------------------------------------------
    instr_memory MEM (
        // Port B: CPU reads instructions
        .addr    (PC),
        .dataOut (instr_data),

        // Port A: mem_ctrl writes instructions
        .clk     (clk),
        .wr_addr (mc_mem_addr),
        .wr_data (mc_mem_din[`INSTR_SIZE-1:0]),
        .wr_en   (mc_mem_we),

        // Readback for CMD_READ
        // mc_mem_dout is driven entirely here (no partial assigns)
        .rd_addr (mc_mem_addr),
        .rd_data (mc_mem_dout)
    );

    // ----------------------------------------------------------
    //  mem_ctrl - Memory / UART Controller  (AXI4-Lite master)
    // ----------------------------------------------------------
    mem_ctrl MC (
        .clk             (clk),
        .rst             (rst),

        // AXI4-Lite master -> axi_uartlite_0 slave
        .m_axi_awaddr    (s_axi_awaddr),
        .m_axi_awvalid   (s_axi_awvalid),
        .m_axi_awready   (s_axi_awready),
        .m_axi_wdata     (s_axi_wdata),
        .m_axi_wstrb     (s_axi_wstrb),
        .m_axi_wvalid    (s_axi_wvalid),
        .m_axi_wready    (s_axi_wready),
        .m_axi_bresp     (s_axi_bresp),
        .m_axi_bvalid    (s_axi_bvalid),
        .m_axi_bready    (s_axi_bready),
        .m_axi_araddr    (s_axi_araddr),
        .m_axi_arvalid   (s_axi_arvalid),
        .m_axi_arready   (s_axi_arready),
        .m_axi_rdata     (s_axi_rdata),
        .m_axi_rresp     (s_axi_rresp),
        .m_axi_rvalid    (s_axi_rvalid),
        .m_axi_rready    (s_axi_rready),

        // Instruction memory interface
        .mem_addr        (mc_mem_addr),
        .mem_data_in     (mc_mem_din),
        .mem_data_out    (mc_mem_dout),
        .mem_we          (mc_mem_we),

        // CPU control
        .cpu_rst_out     (cpu_rst_pulse),
        .cpu_stop_out    (cpu_stop)
    );

    // ----------------------------------------------------------
    //  axi_uartlite_0 - Xilinx UART Lite IP  (AXI4-Lite slave)
    //  Configured for 9600 baud, 8N1, Kintex-7, 100 MHz
    // ----------------------------------------------------------
    axi_uartlite_0 UART_LITE (
        .s_axi_aclk     (clk),
        .s_axi_aresetn  (~rst),          // active-low reset

        // Write address channel
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),

        // Write data channel
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),

        // Write response channel
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),

        // Read address channel
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),

        // Read data channel
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        // UART physical pins
        .rx             (uart_rxd),
        .tx             (uart_txd),

        // Interrupt (not used in this design)
        .interrupt      (uart_interrupt)
    );

endmodule