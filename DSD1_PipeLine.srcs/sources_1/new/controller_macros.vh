`ifndef CONTROLLER_MACROS_VH
`define CONTROLLER_MACROS_VH

// ============================================================
// UART AXI4-Lite Register Byte Addresses  (4-bit AXI addr)
// Source: Xilinx LogiCORE AXI UART Lite IP, Table 4
// ============================================================
`define UART_RX_FIFO    4'h0    // Receive Data FIFO Register  (read)
`define UART_TX_FIFO    4'h4    // Transmit Data FIFO Register (write)
`define UART_STAT_REG   4'h8    // Status Register             (read)
`define UART_CTRL_REG   4'hC    // Control Register            (write)

// ============================================================
// UART Status Register bit positions (UART_STAT_REG)
// ============================================================
`define UART_RXVALID    0       // Bit 0: RX FIFO has valid data
`define UART_RXFULL     1       // Bit 1: RX FIFO is full
`define UART_TXEMPTY    2       // Bit 2: TX FIFO is empty
`define UART_TXFULL     3       // Bit 3: TX FIFO is full

// ============================================================
// Host -> MemCtrl Protocol Command Codes (1 byte each)
// ============================================================
`define CMD_RESET       8'h01   // Reset the Simple RISC CPU
`define CMD_STOP        8'h02   // Freeze (stop) the CPU clock gating
`define CMD_START       8'h03   // Un-freeze (start) the CPU
`define CMD_WRITE       8'h04   // Write N 32-bit words to memory
`define CMD_READ        8'h05   // Read  N 32-bit words from memory

// ============================================================
// Memory / Address sizes used by MemCtrl
// Keep consistent with cpu_macros.vh  (A_SIZE / D_SIZE)
// ============================================================
`define MC_ADDR_SIZE    16      // Word-address bus width
`define MC_DATA_SIZE    32      // Data word width

// Depth of the shared BRAM (2^10 = 1024 words = 4 KB)
`define BRAM_ADDR_WIDTH 10

`endif
