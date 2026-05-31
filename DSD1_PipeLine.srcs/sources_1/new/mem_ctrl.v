`timescale 1ns / 1ps
`include "controller_macros.vh"

// ============================================================
//  mem_ctrl.v  -  Memory Controller (versiune finala)
//
//  Protocol (host -> MemCtrl):
//  -------------------------------------------------------
//  CMD_RESET      [0x01]            : Reset CPU (1 ciclu)
//  CMD_STOP       [0x02]            : Opreste CPU
//  CMD_START      [0x03]            : Porneste CPU
//  CMD_WRITE      [0x04][AH][AL][N] : Scrie N cuvinte 32-bit
//                 urmat de N*4 bytes (MSB first per word)
//  CMD_READ       [0x05][AH][AL][N] : Citeste N cuvinte 32-bit
//                 MemCtrl raspunde cu N*4 bytes (MSB first)
//  CMD_INST_BEGIN [0xAA][AH][AL][CH][CL]
//                 urmat de COUNT*2 bytes (instructiuni 16-bit)
//                 AH:AL  = adresa de start in instr_memory
//                 CH:CL  = numar total de instructiuni
//                 Fiecare instructiune = 2 bytes (MSB first)
//
//  Structura FSM:
//  -------------------------------------------------------
//   AXI_RD_1..3      : citeste un cuvant 32-bit din UART IP
//   AXI_WR_1..3      : scrie un cuvant 32-bit in UART IP
//   RX_POLL/CHK/GOT  : receptioneaza 1 byte prin UART
//   TX_CHK/EVAL/DONE : transmite 1 byte prin UART
//   S_INIT..S_INST_DONE: stari protocol principal
// ============================================================
 
module mem_ctrl (
    input  wire        clk,
    input  wire        rst,
 
    // ----------------------------------------------------------
    // AXI4-Lite Master port (conectat la axi_uartlite_0 slave)
    // ----------------------------------------------------------
    output reg  [3:0]  m_axi_awaddr,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
 
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
 
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
 
    output reg  [3:0]  m_axi_araddr,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
 
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready,
 
    // ----------------------------------------------------------
    // Interfata memorie de instructiuni
    // ----------------------------------------------------------
    output       [`MC_ADDR_SIZE-1:0] mem_addr,
    output       [`MC_DATA_SIZE-1:0] mem_data_in,
    input  wire  [`MC_DATA_SIZE-1:0] mem_data_out,
    output       mem_we,
 
    // ----------------------------------------------------------
    // Control CPU
    // ----------------------------------------------------------
    output reg  cpu_rst_out,
    output reg  cpu_stop_out,
 
    // Iesiri de monitorizare (optional, pot fi lasate neconectate)
    output reg [`MC_ADDR_SIZE-1:0] cur_addr_out,
    output reg [`MC_ADDR_SIZE-1:0] start_addr_out,
    output reg [7:0]               offset_out
);
 
    // ==========================================================
    // CODIFICARE STARI
    // ==========================================================
 
    // ---- AXI Read sub-rutina ---------------------------------
    localparam AXI_RD_1   = 6'd0;
    localparam AXI_RD_2   = 6'd1;
    localparam AXI_RD_3   = 6'd2;
 
    // ---- AXI Write sub-rutina --------------------------------
    localparam AXI_WR_1   = 6'd3;
    localparam AXI_WR_2   = 6'd4;
    localparam AXI_WR_3   = 6'd5;
 
    // ---- Receive-byte sub-rutina ----------------------------
    localparam RX_POLL    = 6'd6;
    localparam RX_CHK     = 6'd7;
    localparam RX_GOT     = 6'd8;
 
    // ---- Transmit-byte sub-rutina ---------------------------
    localparam TX_CHK     = 6'd9;
    localparam TX_EVAL    = 6'd10;
    localparam TX_DONE    = 6'd11;
 
    // ---- Protocol main states --------------------------------
    localparam S_INIT        = 6'd12;
    localparam S_WAIT_CMD    = 6'd13;
    localparam S_DECODE      = 6'd14;
    localparam S_EXEC_RST    = 6'd15;
    localparam S_STORE_AH    = 6'd16;
    localparam S_STORE_AL    = 6'd17;
    localparam S_STORE_LEN   = 6'd18;
    localparam S_STORE_DATA  = 6'd19;
    localparam S_WRITE_MEM   = 6'd20;
    localparam S_WRITE_DONE  = 6'd21;
    localparam S_READ_MEM    = 6'd22;
    localparam S_READ_LATCH  = 6'd23;
    localparam S_SEND_BYTE   = 6'd24;
    localparam S_SENT_BYTE   = 6'd25;
    localparam S_NEXT_WORD   = 6'd26;
    // --- INST_BEGIN FSM states ---
    localparam S_INST_AH     = 6'd27;  // primeste ADDR_HI
    localparam S_INST_AL     = 6'd28;  // primeste ADDR_LO
    localparam S_INST_CNT_H  = 6'd29;  // primeste COUNT_HI
    localparam S_INST_CNT_L  = 6'd30;  // primeste COUNT_LO
    localparam S_INST_RX_B1  = 6'd31;  // primeste byte MSB al instructiunii
    localparam S_INST_RX_B2  = 6'd32;  // primeste byte LSB al instructiunii
    localparam S_INST_WRITE  = 6'd33;  // scrie instructiunea in memorie (wr_en=1)
    localparam S_INST_DONE   = 6'd34;  // dezactiveaza wr_en, avanseaza pointerul
 
    // ==========================================================
    // REGISTRE INTERNE
    // ==========================================================
 
    // Registre care duc porturile de memorie (vizibile combinational)
    reg [`MC_ADDR_SIZE-1:0] mem_addr_reg;
    reg [`MC_DATA_SIZE-1:0] mem_data_in_reg;
    reg                     mem_we_reg;
 
    assign mem_addr    = mem_addr_reg;
    assign mem_data_in = mem_data_in_reg;
    assign mem_we      = mem_we_reg;
 
    reg [5:0]  state;
 
    // Registre de return pentru sub-rutine (call/return pattern)
    reg [5:0]  axi_ret;      // unde se intoarce dupa AXI_RD/WR
    reg [5:0]  byte_ret;     // unde se intoarce dupa RX_POLL/GOT
    reg [5:0]  tx_ret;       // unde se intoarce dupa TX_*
 
    // Registre helper AXI
    reg [3:0]  axi_addr_latch;
    reg [31:0] axi_wdata_latch;
    reg [31:0] axi_rdata_latch;
 
    // Registre protocol
    reg [7:0]  rx_byte;
    reg [7:0]  tx_byte;
    reg [7:0]  cur_cmd;
 
    // Adresa curenta de lucru (avansata la fiecare instructiune/cuvant scris)
    reg [15:0] cur_addr;
    // Adresa de start salvata (pentru readback offset)
    reg [15:0] start_addr_reg;
    // Offset de la start (pentru monitorizare)
    reg [7:0]  offset_reg;
 
    // Numar de instructiuni ramase (COUNT decrementat)
    // FIX: separam HIGH si LOW in registre distincte pentru a evita
    // problema non-blocking assignment la concatenare
    reg [7:0]  instr_cnt_h;  // byte HIGH al numarului de instructiuni
    reg [15:0] instr_count;  // contorul complet (setat corect in S_INST_CNT_L)
 
    // Buffer instructiune curenta (2 bytes, asamblata MSB first)
    reg [15:0] instr_buf;
 
    // CMD_WRITE / CMD_READ
    reg [7:0]  word_count;
    reg [1:0]  byte_pos;
    reg [31:0] data_buf;
 
    // ==========================================================
    // FSM PRINCIPAL (always block sincron)
    // ==========================================================
    always @(posedge clk or posedge rst) begin
 
        if (rst) begin
            state           <= S_INIT;
            m_axi_awaddr    <= 4'h0;
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= 32'h0;
            m_axi_wstrb     <= 4'hF;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
            m_axi_araddr    <= 4'h0;
            m_axi_arvalid   <= 1'b0;
            m_axi_rready    <= 1'b0;
            mem_addr_reg    <= {`MC_ADDR_SIZE{1'b0}};
            mem_data_in_reg <= {`MC_DATA_SIZE{1'b0}};
            mem_we_reg      <= 1'b0;
            cpu_rst_out     <= 1'b0;
            cpu_stop_out    <= 1'b1;
            rx_byte         <= 8'h0;
            tx_byte         <= 8'h0;
            cur_cmd         <= 8'h0;
            cur_addr        <= 16'h0;
            start_addr_reg  <= 16'h0;
            offset_reg      <= 8'h0;
            instr_cnt_h     <= 8'h0;
            instr_count     <= 16'h0;
            instr_buf       <= 16'h0;
            word_count      <= 8'h0;
            byte_pos        <= 2'h0;
            data_buf        <= 32'h0;
            axi_addr_latch  <= 4'h0;
            axi_wdata_latch <= 32'h0;
            axi_rdata_latch <= 32'h0;
            cur_addr_out    <= {`MC_ADDR_SIZE{1'b0}};
            start_addr_out  <= {`MC_ADDR_SIZE{1'b0}};
            offset_out      <= 8'h0;
        end
 
        else begin
            case (state)
 
            // ======================================================
            //  AXI READ TRANSACTION
            //  Citeste un reg 32-bit de la adresa axi_addr_latch.
            //  Rezultatul e in axi_rdata_latch. Return: axi_ret.
            // ======================================================
 
            AXI_RD_1: begin
                m_axi_araddr  <= axi_addr_latch;
                m_axi_arvalid <= 1'b1;
                state         <= AXI_RD_2;
            end
 
            AXI_RD_2: begin
                if (m_axi_arready)
                    m_axi_arvalid <= 1'b0;
                if (m_axi_rvalid) begin
                    axi_rdata_latch <= m_axi_rdata;
                    m_axi_rready    <= 1'b1;
                    m_axi_arvalid   <= 1'b0;
                    state           <= AXI_RD_3;
                end
            end
 
            AXI_RD_3: begin
                m_axi_rready <= 1'b0;
                state        <= axi_ret;
            end
 
            // ======================================================
            //  AXI WRITE TRANSACTION
            //  Scrie axi_wdata_latch la adresa axi_addr_latch.
            //  Return: axi_ret.
            // ======================================================
 
            AXI_WR_1: begin
                m_axi_awaddr  <= axi_addr_latch;
                m_axi_awvalid <= 1'b1;
                m_axi_wdata   <= axi_wdata_latch;
                m_axi_wstrb   <= 4'hF;
                m_axi_wvalid  <= 1'b1;
                state         <= AXI_WR_2;
            end
 
            AXI_WR_2: begin
                if (m_axi_awready) m_axi_awvalid <= 1'b0;
                if (m_axi_wready)  m_axi_wvalid  <= 1'b0;
                if (m_axi_bvalid) begin
                    m_axi_bready  <= 1'b1;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    state         <= AXI_WR_3;
                end
            end
 
            AXI_WR_3: begin
                m_axi_bready <= 1'b0;
                state        <= axi_ret;
            end
 
            // ======================================================
            //  SUB-RUTINA RECEIVE BYTE (RX_POLL -> RX_CHK -> RX_GOT)
            //  Polleaza UART_STAT_REG pana RXVALID=1, apoi citeste
            //  un byte din RX FIFO. Rezultat in rx_byte.
            //  Return: byte_ret.
            // ======================================================
 
            RX_POLL: begin
                axi_addr_latch <= `UART_STAT_REG;
                axi_ret        <= RX_CHK;
                state          <= AXI_RD_1;
            end
 
            RX_CHK: begin
                if (axi_rdata_latch[`UART_RXVALID]) begin
                    axi_addr_latch <= `UART_RX_FIFO;
                    axi_ret        <= RX_GOT;
                    state          <= AXI_RD_1;
                end else begin
                    state <= RX_POLL;   // nu e nimic in FIFO, reincercam
                end
            end
 
            RX_GOT: begin
                rx_byte <= axi_rdata_latch[7:0];
                $display("%0t: RX_GOT byte=0x%02h", $time, axi_rdata_latch[7:0]);
                state   <= byte_ret;
            end
 
            // ======================================================
            //  SUB-RUTINA TRANSMIT BYTE (TX_CHK -> TX_EVAL -> TX_DONE)
            //  Polleaza pana TX FIFO nu e plin, apoi scrie tx_byte.
            //  Return: tx_ret.
            // ======================================================
 
            TX_CHK: begin
                axi_addr_latch <= `UART_STAT_REG;
                axi_ret        <= TX_EVAL;
                state          <= AXI_RD_1;
            end
 
            TX_EVAL: begin
                if (!axi_rdata_latch[`UART_TXFULL]) begin
                    axi_addr_latch  <= `UART_TX_FIFO;
                    axi_wdata_latch <= {24'h0, tx_byte};
                    axi_ret         <= TX_DONE;
                    state           <= AXI_WR_1;
                end else begin
                    state <= TX_CHK;
                end
            end
 
            TX_DONE: begin
                state <= tx_ret;
            end
 
            // ======================================================
            //  INITIALIZARE
            // ======================================================
 
            S_INIT: begin
                cpu_rst_out  <= 1'b0;
                cpu_stop_out <= 1'b1;   // CPU oprit la pornire
                mem_we_reg   <= 1'b0;
                state        <= S_WAIT_CMD;
            end
 
            // ======================================================
            //  ASTEPTARE COMANDA
            //  Starea de idle: asteapta primul byte (codul comenzii)
            // ======================================================
 
            S_WAIT_CMD: begin
                cpu_rst_out <= 1'b0;
                mem_we_reg  <= 1'b0;    // asiguram wr_en=0 in idle
                byte_ret    <= S_DECODE;
                state       <= RX_POLL;
            end
 
            // ======================================================
            //  DECODARE COMANDA
            // ======================================================
 
            S_DECODE: begin
                cur_cmd <= rx_byte;
                case (rx_byte)
 
                    `CMD_RESET: begin
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
                        byte_ret <= S_STORE_AH;
                        state    <= RX_POLL;
                    end
 
                    `CMD_READ: begin
                        byte_ret <= S_STORE_AH;
                        state    <= RX_POLL;
                    end
 
                    // --------------------------------------------------
                    // CMD_INST_BEGIN = 0xAA
                    // Urmeaza: [ADDR_HI][ADDR_LO][COUNT_HI][COUNT_LO]
                    // Apoi COUNT * 2 bytes de instructiuni (MSB first)
                    // --------------------------------------------------
                    `CMD_INST_BEGIN: begin
                        byte_ret <= S_INST_AH;
                        state    <= RX_POLL;
                    end
 
                    default: begin
                        state <= S_WAIT_CMD;
                    end
 
                endcase
            end
 
            // ======================================================
            //  RESET CPU
            // ======================================================
 
            S_EXEC_RST: begin
                cpu_rst_out  <= 1'b1;
                cpu_stop_out <= 1'b1;
                state        <= S_WAIT_CMD;
            end
 
            // ======================================================
            //  CMD_WRITE / CMD_READ - primire adresa si lungime
            // ======================================================
 
            S_STORE_AH: begin
                cur_addr[15:8] <= rx_byte;
                byte_ret       <= S_STORE_AL;
                state          <= RX_POLL;
            end
 
            S_STORE_AL: begin
                cur_addr[7:0] <= rx_byte;
                byte_ret      <= S_STORE_LEN;
                state         <= RX_POLL;
            end
 
            S_STORE_LEN: begin
                word_count     <= rx_byte;
                start_addr_reg <= cur_addr;
                offset_reg     <= 8'h0;
                start_addr_out <= cur_addr;
                offset_out     <= 8'h0;
                if (cur_cmd == `CMD_WRITE) begin
                    byte_pos <= 2'd3;
                    byte_ret <= S_STORE_DATA;
                    state    <= RX_POLL;
                end else begin
                    state <= S_READ_MEM;
                end
            end
 
            // ======================================================
            //  ============  INST_BEGIN FSM  ============
            //
            //  Flux complet:
            //    S_DECODE[0xAA] -> RX_POLL -> S_INST_AH
            //                   -> RX_POLL -> S_INST_AL
            //                   -> RX_POLL -> S_INST_CNT_H
            //                   -> RX_POLL -> S_INST_CNT_L
            //                   -> [S_INST_RX_B1 -> RX_POLL -> S_INST_RX_B2
            //                       -> S_INST_WRITE -> S_INST_DONE] x COUNT
            //                   -> S_WAIT_CMD
            //
            //  Adresare: cur_addr porneste de la ADDR (16-bit word addr)
            //  si se incrementeaza cu +1 dupa fiecare instructiune scrisa.
            //  instr_memory e indexata word cu word (fiecare locatie = 16 biti).
            // ======================================================
 
            // --- Primeste ADDR_HI ---
            S_INST_AH: begin
                cur_addr[15:8] <= rx_byte;
                byte_ret       <= S_INST_AL;
                state          <= RX_POLL;
                $display("%0t: S_INST_AH ADDR_HI=0x%02h", $time, rx_byte);
            end
 
            // --- Primeste ADDR_LO ---
            // FIX CRITIC: byte_ret trebuie sa fie S_INST_CNT_H, NU S_WAIT_CMD!
            // Dupa ce avem adresa completa, mergem direct la citirea COUNT.
            S_INST_AL: begin
                // cur_addr[15:8] a fost deja latched in ciclul anterior
                cur_addr[7:0]  <= rx_byte;
                // Salvam adresa de start (construita din bytes deja latched)
                start_addr_reg <= {cur_addr[15:8], rx_byte};
                offset_reg     <= 8'h0;
                start_addr_out <= {cur_addr[15:8], rx_byte};
                cur_addr_out   <= {cur_addr[15:8], rx_byte};
                // CONTINUAM cu citirea COUNT (NU ne intoarcem in S_WAIT_CMD!)
                byte_ret       <= S_INST_CNT_H;
                state          <= RX_POLL;
                $display("%0t: S_INST_AL ADDR_LO=0x%02h start_addr=0x%04h",
                         $time, rx_byte, {cur_addr[15:8], rx_byte});
            end
 
            // --- Primeste COUNT_HI ---
            // FIX: Salvam in registru separat (instr_cnt_h) pentru a evita
            // problema non-blocking la concatenare in S_INST_CNT_L.
            S_INST_CNT_H: begin
                instr_cnt_h <= rx_byte;   // salvam HIGH byte separat
                byte_ret    <= S_INST_CNT_L;
                state       <= RX_POLL;
                $display("%0t: S_INST_CNT_H COUNT_HI=0x%02h", $time, rx_byte);
            end
 
            // --- Primeste COUNT_LO, formeaza COUNT complet ---
            // FIX CRITIC: folosim instr_cnt_h (nu instr_count[15:8]) la concatenare,
            // deoarece instr_cnt_h e deja stable (latched cu 2+ cicli in urma).
            // Daca am folosi instr_count[15:8] ar fi valoarea DIN S_INST_CNT_H
            // (non-blocking nu a fost aplicata inca in S_INST_CNT_H -> S_INST_CNT_L),
            // INSA deoarece trecem prin RX_POLL intre stari, instr_count[15:8]
            // ar fi de fapt gata. Cu instr_cnt_h eliminam orice ambiguitate.
            S_INST_CNT_L: begin
                instr_count <= {instr_cnt_h, rx_byte};
                $display("%0t: S_INST_CNT_L COUNT_LO=0x%02h total_count=%0d",
                         $time, rx_byte, {instr_cnt_h, rx_byte});
                if ({instr_cnt_h, rx_byte} != 16'h0) begin
                    // Avem instructiuni -> pornim receptia primei instructiuni
                    byte_ret <= S_INST_RX_B1;
                    state    <= RX_POLL;
                end else begin
                    // COUNT=0: nimic de scris, ne intoarcem la idle
                    state <= S_WAIT_CMD;
                end
            end
 
            // --- Primeste byte-ul MSB (HIGH) al instructiunii curente ---
            S_INST_RX_B1: begin
                instr_buf[15:8] <= rx_byte;
                byte_ret        <= S_INST_RX_B2;
                state           <= RX_POLL;
            end
 
            // --- Primeste byte-ul LSB (LOW) al instructiunii curente ---
            // La intrare, rx_byte contine deja byte-ul LOW receptionat
            // (FSM-ul a trecut prin RX_POLL -> RX_CHK -> RX_GOT -> S_INST_RX_B2).
            // instr_buf[15:8] e gata din S_INST_RX_B1.
            S_INST_RX_B2: begin
                instr_buf[7:0] <= rx_byte;
                // Nu mai apelam RX_POLL, mergem direct la scriere
                state          <= S_INST_WRITE;
            end
 
            // --- Scrie instructiunea in instr_memory (wr_en=1 pentru 1 ciclu) ---
            // FIX CRITIC: instr_buf e complet (ambii bytes latched), cur_addr e adresa
            // corecta. Setam mem_we=1 si mergem IMEDIAT in S_INST_DONE.
            // Fara tranzitia la S_INST_DONE, FSM-ul ar ramane blocat si mem_we
            // ar ramane permanent HIGH.
            S_INST_WRITE: begin
                mem_addr_reg    <= cur_addr;
                mem_data_in_reg <= {16'h0, instr_buf};  // upper 16 biti = 0
                mem_we_reg      <= 1'b1;                // wr_en activ pentru 1 ciclu
                state           <= S_INST_DONE;
                $display("%0t: S_INST_WRITE mem_we=1 addr=0x%04h data=0x%04h",
                         $time, cur_addr, instr_buf);
            end
 
            // --- Dezactiveaza wr_en, avanseaza pointerul, decide continuarea ---
            S_INST_DONE: begin
                mem_we_reg     <= 1'b0;         // dezactiveaza wr_en
                cur_addr       <= cur_addr + 16'd1;     // urmatoarea locatie
                offset_reg     <= offset_reg + 8'd1;
                cur_addr_out   <= cur_addr + 16'd1;
                start_addr_out <= start_addr_reg;
                offset_out     <= offset_reg + 8'd1;
 
                $display("%0t: S_INST_DONE wrote 0x%04h at addr=0x%04h remaining=%0d",
                         $time, instr_buf, cur_addr, instr_count - 1);
 
                if (instr_count == 16'h1) begin
                    // Aceasta a fost ultima instructiune
                    instr_count <= 16'h0;
                    state       <= S_WAIT_CMD;
                    $display("%0t: S_INST_DONE -> toate instructiunile scrise!", $time);
                end else begin
                    // Mai sunt instructiuni -> decrementam si citim urmatorul byte
                    instr_count <= instr_count - 16'd1;
                    byte_ret    <= S_INST_RX_B1;
                    state       <= RX_POLL;
                end
            end
 
            // ======================================================
            //  CMD_WRITE - scriere cuvinte 32-bit in memorie
            // ======================================================
 
            S_STORE_DATA: begin
                case (byte_pos)
                    2'd3: data_buf[31:24] <= rx_byte;
                    2'd2: data_buf[23:16] <= rx_byte;
                    2'd1: data_buf[15:8]  <= rx_byte;
                    2'd0: data_buf[7:0]   <= rx_byte;
                endcase
                if (byte_pos == 2'd0) begin
                    state <= S_WRITE_MEM;
                end else begin
                    byte_pos <= byte_pos - 2'd1;
                    byte_ret <= S_STORE_DATA;
                    state    <= RX_POLL;
                end
            end
 
            S_WRITE_MEM: begin
                mem_addr_reg    <= cur_addr;
                mem_data_in_reg <= data_buf;
                mem_we_reg      <= 1'b1;
                state           <= S_WRITE_DONE;
            end
 
            S_WRITE_DONE: begin
                mem_we_reg     <= 1'b0;
                cur_addr       <= cur_addr + 16'd1;
                word_count     <= word_count - 8'd1;
                offset_reg     <= offset_reg + 8'd1;
                start_addr_out <= start_addr_reg;
                cur_addr_out   <= cur_addr + 16'd1;
                offset_out     <= offset_reg + 8'd1;
                if (word_count == 8'd1) begin
                    state <= S_WAIT_CMD;
                end else begin
                    byte_pos <= 2'd3;
                    byte_ret <= S_STORE_DATA;
                    state    <= RX_POLL;
                end
            end
 
            // ======================================================
            //  CMD_READ - citire cuvinte 32-bit din memorie
            // ======================================================
 
            S_READ_MEM: begin
                mem_addr_reg <= cur_addr;
                mem_we_reg   <= 1'b0;
                state        <= S_READ_LATCH;
            end
 
            S_READ_LATCH: begin
                data_buf <= mem_data_out;
                byte_pos <= 2'd3;
                state    <= S_SEND_BYTE;
            end
 
            S_SEND_BYTE: begin
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
                    byte_pos <= byte_pos - 2'd1;
                    state    <= S_SEND_BYTE;
                end else begin
                    state <= S_NEXT_WORD;
                end
            end
 
            S_NEXT_WORD: begin
                cur_addr   <= cur_addr + 16'd1;
                word_count <= word_count - 8'd1;
                if (word_count == 8'd1) begin
                    state <= S_WAIT_CMD;
                end else begin
                    state <= S_READ_MEM;
                end
            end
 
            // ======================================================
            //  DEFAULT: fallback sigur la initializare
            // ======================================================
            default: begin
                state <= S_INIT;
            end
 
            endcase
        end
    end
 
endmodule