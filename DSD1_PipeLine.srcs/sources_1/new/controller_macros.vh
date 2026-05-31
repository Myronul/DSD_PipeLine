`ifndef CONTROLLER_MACROS_VH
`define CONTROLLER_MACROS_VH

// ============================================================
// UART AXI4-Lite Register Byte Addresses (4-bit AXI addr)
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
`define CMD_RESET        8'h01   // Reset CPU (1 ciclu)
`define CMD_STOP         8'h02   // Opreste CPU (freeze)
`define CMD_START        8'h03   // Porneste CPU (unfreeze)
`define CMD_WRITE        8'h04   // Scrie N cuvinte 32-bit in instr_memory
`define CMD_READ         8'h05   // Citeste N cuvinte 32-bit din instr_memory
`define CMD_INST_BEGIN   8'hAA   // MAGIC: incepe incarcarea instructiunilor
//                               //   [0xAA][AH][AL][CH][CL] + COUNT*2 bytes

`define CMD_DATAMEM_READ 8'hBB   // MAGIC: citeste N cuvinte 32-bit din data_memory
//                               //   [0xBB][A2][A1][A0][N]
//                               //   A2:A1:A0 = adresa 20-bit (MSB first, 3 octeti)
//                               //   N        = numar de cuvinte 32-bit de citit
//                               //   Raspuns: N * 4 bytes (MSB first per cuvant)

// ============================================================
// Memory / Address sizes
// ============================================================
`define MC_ADDR_SIZE    16      // Word-address bus width instr_memory (16-bit)
`define MC_DATA_SIZE    32      // Data word width (32-bit)
`define DM_ADDR_SIZE    20      // data_memory address width (A_SIZE din cpu_macros)

// Depth of instr_memory (2^10 = 1024 locatii de 16 biti = 2 KB)
`define BRAM_ADDR_WIDTH 10

`endif
