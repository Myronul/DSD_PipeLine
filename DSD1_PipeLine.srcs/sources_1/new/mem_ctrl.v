`timescale 1ns / 1ps
`include "controller_macros.vh"

// ============================================================
//  mem_ctrl.v  -  Memory Controller
//
//  This module is the AXI4-Lite MASTER that talks to the
//  Xilinx axi_uartlite_0 slave in order to receive and send
//  bytes over UART.
//
//  High-level protocol (host ? MemCtrl):
//  ??????????????????????????????????????????????????????????
//  RESET  : [0x01]
//  STOP   : [0x02]
//  START  : [0x03]
//  WRITE  : [0x04][ADDR_HI][ADDR_LO][LEN]
//              followed by LEN×4 bytes (MSB first per word)
//  READ   : [0x05][ADDR_HI][ADDR_LO][LEN]
//              MemCtrl replies with LEN×4 bytes (MSB first)
//
//  Addresses are 16-bit word-addresses.
//  LEN is the number of 32-bit words (1..255).
//
//  Internal FSM structure:
//  ??????????????????????????????????????????????????????????
//   • AXI read / write sub-routines  (states 0-5)
//   • Receive-byte sub-routine       (states 6-8)
//   • Transmit-byte sub-routine      (states 9-11)
//   • Protocol main states           (states 12-26)
// ============================================================

module mem_ctrl (
    input  wire        clk,
    input  wire        rst,

    // ----------------------------------------------------------
    // AXI4-Lite Master port  (connects to axi_uartlite_0 slave)
    // ----------------------------------------------------------

    // Write address channel
    output reg  [3:0]  m_axi_awaddr,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,

    // Write data channel
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    // Write response channel
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,

    // Read address channel
    output reg  [3:0]  m_axi_araddr,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,

    // Read data channel
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,

    // ----------------------------------------------------------
    // Shared BRAM interface  (to bram_mem Port A / read-back)
    // ----------------------------------------------------------
    output reg  [`MC_ADDR_SIZE-1:0] mem_addr,    // word address
    output reg  [`MC_DATA_SIZE-1:0] mem_data_in, // data to write
    input  wire [`MC_DATA_SIZE-1:0] mem_data_out,// data read back
    output reg  mem_we,                          // write enable

    // ----------------------------------------------------------
    // CPU control  (to cpu_pipe / fetch_stage)
    // ----------------------------------------------------------
    output reg  cpu_rst_out,   // synchronous reset pulse (1 cycle)
    output reg  cpu_stop_out   // when high: CPU pipeline is frozen
);

    // ==========================================================
    // STATE ENCODING
    // ==========================================================

    // ---- AXI Read transaction (shared sub-routine) -----------
    // Entry conditions: axi_addr_latch = UART register address
    //                   axi_ret        = state to return to
    localparam AXI_RD_1   = 5'd0;  // assert ARVALID
    localparam AXI_RD_2   = 5'd1;  // wait for ARREADY + RVALID
    localparam AXI_RD_3   = 5'd2;  // clear RREADY, jump to axi_ret

    // ---- AXI Write transaction (shared sub-routine) ----------
    // Entry conditions: axi_addr_latch  = UART register address
    //                   axi_wdata_latch = 32-bit write data
    //                   axi_ret         = state to return to
    localparam AXI_WR_1   = 5'd3;  // assert AWVALID + WVALID
    localparam AXI_WR_2   = 5'd4;  // wait for AWREADY, WREADY, BVALID
    localparam AXI_WR_3   = 5'd5;  // clear BREADY, jump to axi_ret

    // ---- Receive-byte sub-routine ----------------------------
    // Entry condition: byte_ret = caller return state
    // Exit:            rx_byte holds the received byte
    localparam RX_POLL    = 5'd6;  // read UART status register
    localparam RX_CHK     = 5'd7;  // check RXVALID; loop or read FIFO
    localparam RX_GOT     = 5'd8;  // save byte ? jump to byte_ret

    // ---- Transmit-byte sub-routine ---------------------------
    // Entry condition: tx_byte = byte to send
    //                  tx_ret  = caller return state
    localparam TX_CHK     = 5'd9;  // read UART status register
    localparam TX_EVAL    = 5'd10; // check TXFULL; loop or write FIFO
    localparam TX_DONE    = 5'd11; // byte sent ? jump to tx_ret

    // ---- Protocol main states --------------------------------
    localparam S_INIT       = 5'd12; // one-time initialisation
    localparam S_WAIT_CMD   = 5'd13; // wait for next command byte
    localparam S_DECODE     = 5'd14; // decode the received command
    localparam S_EXEC_RST   = 5'd15; // pulse cpu_rst for 1 cycle
    localparam S_STORE_AH   = 5'd16; // save address high byte
    localparam S_STORE_AL   = 5'd17; // save address low  byte
    localparam S_STORE_LEN  = 5'd18; // save length byte
    localparam S_STORE_DATA = 5'd19; // accumulate incoming data bytes
    localparam S_WRITE_MEM  = 5'd20; // write assembled word to BRAM
    localparam S_WRITE_DONE = 5'd21; // advance address/counter
    localparam S_READ_MEM   = 5'd22; // request BRAM read (set addr)
    localparam S_READ_LATCH = 5'd23; // capture BRAM output (1-cyc lat)
    localparam S_SEND_BYTE  = 5'd24; // load tx_byte from data_buf
    localparam S_SENT_BYTE  = 5'd25; // after TX: advance byte_pos
    localparam S_NEXT_WORD  = 5'd26; // after 4 bytes: advance word

    // ==========================================================
    // REGISTERS
    // ==========================================================

    reg [4:0]  state;

    // Sub-routine return-state registers
    reg [4:0]  axi_ret;       // where AXI sub-routine returns
    reg [4:0]  byte_ret;      // where receive-byte sub-routine returns
    reg [4:0]  tx_ret;        // where transmit-byte sub-routine returns

    // AXI helper registers
    reg [3:0]  axi_addr_latch;
    reg [31:0] axi_wdata_latch;
    reg [31:0] axi_rdata_latch;  // captured read data

    // Protocol working registers
    reg [7:0]  rx_byte;       // most recently received UART byte
    reg [7:0]  tx_byte;       // byte being transmitted to UART
    reg [7:0]  cur_cmd;       // CMD_WRITE or CMD_READ in progress
    reg [15:0] cur_addr;      // current word address in BRAM
    reg [7:0]  word_count;    // remaining words to process
    reg [1:0]  byte_pos;      // byte index: 3 = MSB, 0 = LSB
    reg [31:0] data_buf;      // 32-bit assembly / disassembly buffer

    // ==========================================================
    // MAIN FSM  (single synchronous always block)
    // ==========================================================
    always @(posedge clk or posedge rst) begin

        if (rst) begin
            state           <= S_INIT;
            // AXI outputs
            m_axi_awaddr    <= 4'h0;
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= 32'h0;
            m_axi_wstrb     <= 4'hF;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
            m_axi_araddr    <= 4'h0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            // Memory
            mem_addr        <= {`MC_ADDR_SIZE{1'b0}};
            mem_data_in     <= {`MC_DATA_SIZE{1'b0}};
            mem_we          <= 1'b0;
            // CPU
            cpu_rst_out     <= 1'b0;
            cpu_stop_out    <= 1'b1;  // CPU starts in stopped state
            // Internal
            rx_byte         <= 8'h0;
            tx_byte         <= 8'h0;
            cur_cmd         <= 8'h0;
            cur_addr        <= 16'h0;
            word_count      <= 8'h0;
            byte_pos        <= 2'h0;
            data_buf        <= 32'h0;
            axi_addr_latch  <= 4'h0;
            axi_wdata_latch <= 32'h0;
            axi_rdata_latch <= 32'h0;
        end

        else begin
            case (state)

            // ======================================================
            //  AXI READ TRANSACTION
            //  Reads one 32-bit word from the UART register given
            //  in axi_addr_latch and stores it in axi_rdata_latch.
            //  Returns to axi_ret when done.
            // ======================================================

            AXI_RD_1: begin
                // Send read address to slave
                m_axi_araddr  <= axi_addr_latch;
                m_axi_arvalid <= 1'b1;
                state         <= AXI_RD_2;
            end

            AXI_RD_2: begin
                // Deassert address valid once slave accepted it
                if (m_axi_arready)
                    m_axi_arvalid <= 1'b0;

                // Capture data when slave presents it
                if (m_axi_rvalid) begin
                    axi_rdata_latch <= m_axi_rdata;
                    m_axi_rready    <= 1'b1;
                    m_axi_arvalid   <= 1'b0;  // safe to clear if not yet
                    state           <= AXI_RD_3;
                end
            end

            AXI_RD_3: begin
                m_axi_rready <= 1'b0;
                state        <= axi_ret;     // return to caller
            end

            // ======================================================
            //  AXI WRITE TRANSACTION
            //  Writes axi_wdata_latch to the register at
            //  axi_addr_latch.  Returns to axi_ret when done.
            // ======================================================

            AXI_WR_1: begin
                // Send address and data simultaneously (legal in AXI4-Lite)
                m_axi_awaddr  <= axi_addr_latch;
                m_axi_awvalid <= 1'b1;
                m_axi_wdata   <= axi_wdata_latch;
                m_axi_wstrb   <= 4'hF;
                m_axi_wvalid  <= 1'b1;
                state         <= AXI_WR_2;
            end

            AXI_WR_2: begin
                // Deassert each valid when the corresponding ready is seen
                if (m_axi_awready) m_axi_awvalid <= 1'b0;
                if (m_axi_wready)  m_axi_wvalid  <= 1'b0;

                // Wait for write response (BRESP)
                if (m_axi_bvalid) begin
                    m_axi_bready  <= 1'b1;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    state         <= AXI_WR_3;
                end
            end

            AXI_WR_3: begin
                m_axi_bready <= 1'b0;
                state        <= axi_ret;     // return to caller
            end

            // ======================================================
            //  RECEIVE BYTE SUB-ROUTINE
            //  Polls the UART status register until RXVALID=1,
            //  then reads one byte from the RX FIFO.
            //  Result is in rx_byte; resumes at byte_ret.
            // ======================================================

            RX_POLL: begin
                // Issue AXI read of UART status register
                axi_addr_latch <= `UART_STAT_REG;
                axi_ret        <= RX_CHK;
                state          <= AXI_RD_1;
            end

            RX_CHK: begin
                if (axi_rdata_latch[`UART_RXVALID]) begin
                    // Data available: read the RX FIFO
                    axi_addr_latch <= `UART_RX_FIFO;
                    axi_ret        <= RX_GOT;
                    state          <= AXI_RD_1;
                end else begin
                    // No data yet: poll again
                    state <= RX_POLL;
                end
            end

            RX_GOT: begin
                // Save the received byte and return to caller
                rx_byte <= axi_rdata_latch[7:0];
                state   <= byte_ret;
            end

            // ======================================================
            //  TRANSMIT BYTE SUB-ROUTINE
            //  Polls until TX FIFO is not full, then sends tx_byte.
            //  Resumes at tx_ret.
            // ======================================================

            TX_CHK: begin
                // Issue AXI read of UART status register
                axi_addr_latch <= `UART_STAT_REG;
                axi_ret        <= TX_EVAL;
                state          <= AXI_RD_1;
            end

            TX_EVAL: begin
                if (!axi_rdata_latch[`UART_TXFULL]) begin
                    // TX FIFO has space: write byte to TX FIFO
                    axi_addr_latch  <= `UART_TX_FIFO;
                    axi_wdata_latch <= {24'h0, tx_byte}; // only [7:0] used
                    axi_ret         <= TX_DONE;
                    state           <= AXI_WR_1;
                end else begin
                    // TX FIFO full: wait and retry
                    state <= TX_CHK;
                end
            end

            TX_DONE: begin
                state <= tx_ret;    // return to caller
            end

            // ======================================================
            //  PROTOCOL: INITIALISATION
            // ======================================================

            S_INIT: begin
                cpu_rst_out  <= 1'b0;
                cpu_stop_out <= 1'b1;   // keep CPU frozen at power-on
                mem_we       <= 1'b0;
                state        <= S_WAIT_CMD;
            end

            // ======================================================
            //  PROTOCOL: WAIT FOR NEXT COMMAND BYTE
            // ======================================================

            S_WAIT_CMD: begin
                cpu_rst_out <= 1'b0;    // clear any previous reset pulse
                mem_we      <= 1'b0;
                byte_ret    <= S_DECODE;
                state       <= RX_POLL;
            end

            // ======================================================
            //  PROTOCOL: DECODE COMMAND BYTE
            //  rx_byte contains the received command.
            // ======================================================

            S_DECODE: begin
                cur_cmd <= rx_byte;
                case (rx_byte)

                    `CMD_RESET: begin
                        // Pulse cpu_rst for exactly 1 clock cycle
                        state <= S_EXEC_RST;
                    end

                    `CMD_STOP: begin
                        cpu_stop_out <= 1'b1;
                        state        <= S_WAIT_CMD;
                    end

                    `CMD_START: begin
                        cpu_stop_out <= 1'b0;
                        state        <= S_WAIT_CMD;
                    end

                    `CMD_WRITE: begin
                        // Next: receive 2-byte address then 1-byte length
                        byte_ret <= S_STORE_AH;
                        state    <= RX_POLL;
                    end

                    `CMD_READ: begin
                        byte_ret <= S_STORE_AH;
                        state    <= RX_POLL;
                    end

                    default: begin
                        // Unknown command: ignore and wait for next
                        state <= S_WAIT_CMD;
                    end

                endcase
            end

            // ======================================================
            //  PROTOCOL: EXECUTE RESET
            //  Assert cpu_rst_out for exactly 1 clock cycle.
            //  The CPU sees the reset on the NEXT rising edge.
            // ======================================================

            S_EXEC_RST: begin
                cpu_rst_out  <= 1'b1;
                cpu_stop_out <= 1'b1;   // keep stopped after reset
                // cpu_rst_out will be cleared when we return to S_WAIT_CMD
                state <= S_WAIT_CMD;
            end

            // ======================================================
            //  PROTOCOL: RECEIVE ADDRESS AND LENGTH
            //  Shared by both CMD_WRITE and CMD_READ.
            // ======================================================

            S_STORE_AH: begin
                // rx_byte = address[15:8]
                cur_addr[15:8] <= rx_byte;
                byte_ret       <= S_STORE_AL;
                state          <= RX_POLL;
            end

            S_STORE_AL: begin
                // rx_byte = address[7:0]
                cur_addr[7:0] <= rx_byte;
                byte_ret      <= S_STORE_LEN;
                state         <= RX_POLL;
            end

            S_STORE_LEN: begin
                // rx_byte = number of 32-bit words
                word_count <= rx_byte;
                if (cur_cmd == `CMD_WRITE) begin
                    // Start receiving data bytes; byte_pos=3 means MSB first
                    byte_pos <= 2'd3;
                    byte_ret <= S_STORE_DATA;
                    state    <= RX_POLL;
                end else begin
                    // CMD_READ: go directly to memory read
                    state <= S_READ_MEM;
                end
            end

            // ======================================================
            //  PROTOCOL: WRITE  -  receive bytes, assemble, write mem
            //  4 bytes arrive MSB first and are packed into data_buf.
            //  When all 4 bytes are received, write data_buf to BRAM.
            // ======================================================

            S_STORE_DATA: begin
                // Store the incoming byte at the correct position
                case (byte_pos)
                    2'd3: data_buf[31:24] <= rx_byte;
                    2'd2: data_buf[23:16] <= rx_byte;
                    2'd1: data_buf[15:8]  <= rx_byte;
                    2'd0: data_buf[7:0]   <= rx_byte;
                endcase

                if (byte_pos == 2'd0) begin
                    // All 4 bytes assembled ? write to memory
                    state <= S_WRITE_MEM;
                end else begin
                    // Still more bytes for this word
                    byte_pos <= byte_pos - 2'd1;
                    byte_ret <= S_STORE_DATA;
                    state    <= RX_POLL;
                end
            end

            S_WRITE_MEM: begin
                // Drive BRAM write signals for one clock cycle
                mem_addr    <= cur_addr;
                mem_data_in <= data_buf;
                mem_we      <= 1'b1;
                state       <= S_WRITE_DONE;
            end

            S_WRITE_DONE: begin
                mem_we     <= 1'b0;
                cur_addr   <= cur_addr + 16'd1;
                word_count <= word_count - 8'd1;

                if (word_count == 8'd1) begin
                    // That was the last word
                    state <= S_WAIT_CMD;
                end else begin
                    // More words to receive
                    byte_pos <= 2'd3;
                    byte_ret <= S_STORE_DATA;
                    state    <= RX_POLL;
                end
            end

            // ======================================================
            //  PROTOCOL: READ  -  read mem, split into bytes, send
            //  For each word: read BRAM (1-cycle latency), then send
            //  4 bytes MSB first over UART.
            // ======================================================

            S_READ_MEM: begin
                // Present address to BRAM; data appears next cycle
                mem_addr <= cur_addr;
                mem_we   <= 1'b0;
                state    <= S_READ_LATCH;
            end

            S_READ_LATCH: begin
                // BRAM synchronous read: data_out is valid this cycle
                data_buf <= mem_data_out;
                byte_pos <= 2'd3;        // start with MSB
                state    <= S_SEND_BYTE;
            end

            S_SEND_BYTE: begin
                // Select the correct byte from data_buf
                case (byte_pos)
                    2'd3: tx_byte <= data_buf[31:24];
                    2'd2: tx_byte <= data_buf[23:16];
                    2'd1: tx_byte <= data_buf[15:8];
                    2'd0: tx_byte <= data_buf[7:0];
                endcase
                tx_ret <= S_SENT_BYTE;
                state  <= TX_CHK;
            end

            S_SENT_BYTE: begin
                if (byte_pos > 2'd0) begin
                    // More bytes in this word
                    byte_pos <= byte_pos - 2'd1;
                    state    <= S_SEND_BYTE;
                end else begin
                    // All 4 bytes of this word have been sent
                    state <= S_NEXT_WORD;
                end
            end

            S_NEXT_WORD: begin
                cur_addr   <= cur_addr + 16'd1;
                word_count <= word_count - 8'd1;

                if (word_count == 8'd1) begin
                    // Last word was just sent
                    state <= S_WAIT_CMD;
                end else begin
                    // More words to read and send
                    state <= S_READ_MEM;
                end
            end

            // ======================================================
            //  DEFAULT: should never happen; safe fallback
            // ======================================================
            default: begin
                state <= S_INIT;
            end

            endcase
        end
    end

endmodule