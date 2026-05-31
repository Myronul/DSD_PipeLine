`timescale 1ns / 1ps
`include "controller_macros.vh"

// ============================================================
//  mem_ctrl.v  -  Memory Controller
//
//  Protocol (host -> MemCtrl):
//  -------------------------------------------------------
//  CMD_RESET        [0x01]               : Reset CPU (1 ciclu)
//  CMD_STOP         [0x02]               : Opreste CPU
//  CMD_START        [0x03]               : Porneste CPU
//  CMD_WRITE        [0x04][AH][AL][N]    : Scrie N cuvinte 32-bit in instr_memory
//  CMD_READ         [0x05][AH][AL][N]    : Citeste N cuvinte din instr_memory
//  CMD_INST_BEGIN   [0xAA][AH][AL][CH][CL] + COUNT*2 bytes (instructiuni 16-bit)
//  CMD_DATAMEM_READ [0xBB][A2][A1][A0][N]
//                   A2:A1:A0 = adresa 20-bit in data_memory (MSB first, 3 octeti)
//                   N        = numar de cuvinte 32-bit de citit (1..255)
//                   Raspuns UART: N * 4 bytes (MSB first per cuvant 32-bit)
//
//  Latenta data_memory (IMPORTANT):
//    data_memory latcheaza adresa la posedge cand memRd=1.
//    dataMemDataout = MemData[RegAddr] e combinational.
//    Deoarece semnalele sunt non-blocking (<=), dm_rd devine 1 vizibil
//    abia in ciclul URMATOR posedge-ului din S_DM_RD_EN.
//    Fluxul corect necesita 2 cicli de asteptare dupa setarea dm_rd:
//
//    S_DM_RD_EN  (ciclu T): dm_rd<=1, dm_addr setat, state<=S_DM_WAIT
//    S_DM_WAIT   (ciclu T+1): la posedge T+1, data_memory vede dm_rd=1,
//                 face RegAddr<=dm_addr; state<=S_DM_LATCH
//    S_DM_LATCH  (ciclu T+2): la posedge T+2, dataMemDataout=MemData[RegAddr]
//                 e stabil (combinational dupa RegAddr latched la T+1);
//                 dm_rd<=0; laturam dm_data_latch<=dm_data_out; state<=TX
// ============================================================

module mem_ctrl (
    input  wire        clk,
    input  wire        rst,

    // AXI4-Lite Master port
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

    // Interfata instr_memory
    output       [`MC_ADDR_SIZE-1:0] mem_addr,
    output       [`MC_DATA_SIZE-1:0] mem_data_in,
    input  wire  [`MC_DATA_SIZE-1:0] mem_data_out,
    output       mem_we,

    // Interfata data_memory (read-only din mem_ctrl)
    output reg  [`DM_ADDR_SIZE-1:0] dm_addr,
    output reg                       dm_rd,
    input  wire [`MC_DATA_SIZE-1:0]  dm_data_out,

    // Control CPU
    output reg  cpu_rst_out,
    output reg  cpu_stop_out,

    // Monitorizare
    output reg [`MC_ADDR_SIZE-1:0] cur_addr_out,
    output reg [`MC_ADDR_SIZE-1:0] start_addr_out,
    output reg [7:0]               offset_out
);

    // ==========================================================
    // CODIFICARE STARI
    // ==========================================================
    localparam AXI_RD_1      = 6'd0;
    localparam AXI_RD_2      = 6'd1;
    localparam AXI_RD_3      = 6'd2;
    localparam AXI_WR_1      = 6'd3;
    localparam AXI_WR_2      = 6'd4;
    localparam AXI_WR_3      = 6'd5;
    localparam RX_POLL       = 6'd6;
    localparam RX_CHK        = 6'd7;
    localparam RX_GOT        = 6'd8;
    localparam TX_CHK        = 6'd9;
    localparam TX_EVAL       = 6'd10;
    localparam TX_DONE       = 6'd11;
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
    localparam S_INST_AH     = 6'd27;
    localparam S_INST_AL     = 6'd28;
    localparam S_INST_CNT_H  = 6'd29;
    localparam S_INST_CNT_L  = 6'd30;
    localparam S_INST_RX_B1  = 6'd31;
    localparam S_INST_RX_B2  = 6'd32;
    localparam S_INST_WRITE  = 6'd33;
    localparam S_INST_DONE   = 6'd34;

    // --- CMD_DATAMEM_READ states ---
    localparam S_DM_A2       = 6'd35;  // primeste A2: bits [19:16] ai adresei
    localparam S_DM_A1       = 6'd36;  // primeste A1: bits [15:8]
    localparam S_DM_A0       = 6'd37;  // primeste A0: bits [7:0], asambleaza adresa
    localparam S_DM_COUNT    = 6'd38;  // primeste N (numar cuvinte 32-bit)
    localparam S_DM_RD_EN    = 6'd39;  // seteaza dm_rd=1 si dm_addr
    localparam S_DM_WAIT     = 6'd40;  // asteapta 1 ciclu: data_memory latcheaza RegAddr
    localparam S_DM_LATCH    = 6'd41;  // dm_rd=0, dm_data_out e stabil, laturam
    localparam S_DM_TX_B3    = 6'd42;  // transmite byte [31:24]
    localparam S_DM_TX_B2    = 6'd43;  // transmite byte [23:16]
    localparam S_DM_TX_B1    = 6'd44;  // transmite byte [15:8]
    localparam S_DM_TX_B0    = 6'd45;  // transmite byte [7:0]
    localparam S_DM_NEXT     = 6'd46;  // decide: mai sunt cuvinte sau stop

    // ==========================================================
    // REGISTRE INTERNE
    // ==========================================================
    reg [`MC_ADDR_SIZE-1:0] mem_addr_reg;
    reg [`MC_DATA_SIZE-1:0] mem_data_in_reg;
    reg                     mem_we_reg;

    assign mem_addr    = mem_addr_reg;
    assign mem_data_in = mem_data_in_reg;
    assign mem_we      = mem_we_reg;

    reg [5:0]  state;
    reg [5:0]  axi_ret;
    reg [5:0]  byte_ret;
    reg [5:0]  tx_ret;

    reg [3:0]  axi_addr_latch;
    reg [31:0] axi_wdata_latch;
    reg [31:0] axi_rdata_latch;

    reg [7:0]  rx_byte;
    reg [7:0]  tx_byte;
    reg [7:0]  cur_cmd;

    reg [15:0] cur_addr;
    reg [15:0] start_addr_reg;
    reg [7:0]  offset_reg;

    reg [7:0]  instr_cnt_h;
    reg [15:0] instr_count;
    reg [15:0] instr_buf;

    reg [7:0]  word_count;
    reg [1:0]  byte_pos;
    reg [31:0] data_buf;

    // CMD_DATAMEM_READ registre
    reg [19:0] dm_addr_reg;   // adresa 20-bit asamblata
    reg [7:0]  dm_count;      // numar de cuvinte ramase
    reg [7:0]  dm_byte_a2;    // latch A2
    reg [7:0]  dm_byte_a1;    // latch A1
    reg [31:0] dm_data_latch; // cuvantul capturat din data_memory

    // ==========================================================
    // FSM PRINCIPAL
    // ==========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= S_INIT;
            m_axi_awaddr    <= 4'h0;  m_axi_awvalid <= 1'b0;
            m_axi_wdata     <= 32'h0; m_axi_wstrb   <= 4'hF;
            m_axi_wvalid    <= 1'b0;  m_axi_bready  <= 1'b0;
            m_axi_araddr    <= 4'h0;  m_axi_arvalid <= 1'b0;
            m_axi_rready    <= 1'b0;
            mem_addr_reg    <= {`MC_ADDR_SIZE{1'b0}};
            mem_data_in_reg <= {`MC_DATA_SIZE{1'b0}};
            mem_we_reg      <= 1'b0;
            dm_addr         <= {`DM_ADDR_SIZE{1'b0}};
            dm_rd           <= 1'b0;
            cpu_rst_out     <= 1'b0;  cpu_stop_out  <= 1'b1;
            rx_byte <= 8'h0; tx_byte <= 8'h0; cur_cmd <= 8'h0;
            cur_addr <= 16'h0; start_addr_reg <= 16'h0; offset_reg <= 8'h0;
            instr_cnt_h <= 8'h0; instr_count <= 16'h0; instr_buf <= 16'h0;
            word_count <= 8'h0; byte_pos <= 2'h0; data_buf <= 32'h0;
            dm_addr_reg <= 20'h0; dm_count <= 8'h0;
            dm_byte_a2 <= 8'h0; dm_byte_a1 <= 8'h0; dm_data_latch <= 32'h0;
            axi_addr_latch <= 4'h0; axi_wdata_latch <= 32'h0; axi_rdata_latch <= 32'h0;
            cur_addr_out <= {`MC_ADDR_SIZE{1'b0}};
            start_addr_out <= {`MC_ADDR_SIZE{1'b0}};
            offset_out <= 8'h0;
        end else begin
            case (state)

            // ======================================================
            //  AXI READ / WRITE sub-rutine
            // ======================================================
            AXI_RD_1: begin
                m_axi_araddr  <= axi_addr_latch;
                m_axi_arvalid <= 1'b1;
                state         <= AXI_RD_2;
            end
            AXI_RD_2: begin
                if (m_axi_arready) m_axi_arvalid <= 1'b0;
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
            AXI_WR_1: begin
                m_axi_awaddr  <= axi_addr_latch;  m_axi_awvalid <= 1'b1;
                m_axi_wdata   <= axi_wdata_latch; m_axi_wstrb   <= 4'hF;
                m_axi_wvalid  <= 1'b1;
                state         <= AXI_WR_2;
            end
            AXI_WR_2: begin
                if (m_axi_awready) m_axi_awvalid <= 1'b0;
                if (m_axi_wready)  m_axi_wvalid  <= 1'b0;
                if (m_axi_bvalid) begin
                    m_axi_bready  <= 1'b1;
                    m_axi_awvalid <= 1'b0; m_axi_wvalid <= 1'b0;
                    state         <= AXI_WR_3;
                end
            end
            AXI_WR_3: begin
                m_axi_bready <= 1'b0;
                state        <= axi_ret;
            end

            // ======================================================
            //  RX / TX sub-rutine
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
                    state <= RX_POLL;
                end
            end
            RX_GOT: begin
                rx_byte <= axi_rdata_latch[7:0];
                $display("%0t: RX_GOT byte=0x%02h", $time, axi_rdata_latch[7:0]);
                state   <= byte_ret;
            end
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
            //  INIT / IDLE / DECODE
            // ======================================================
            S_INIT: begin
                cpu_rst_out  <= 1'b0;
                cpu_stop_out <= 1'b1;
                mem_we_reg   <= 1'b0;
                dm_rd        <= 1'b0;
                state        <= S_WAIT_CMD;
            end
            S_WAIT_CMD: begin
                cpu_rst_out <= 1'b0;
                mem_we_reg  <= 1'b0;
                dm_rd       <= 1'b0;
                byte_ret    <= S_DECODE;
                state       <= RX_POLL;
            end
            S_DECODE: begin
                cur_cmd <= rx_byte;
                case (rx_byte)
                    `CMD_RESET:        state    <= S_EXEC_RST;
                    `CMD_STOP:       begin cpu_stop_out <= 1'b1; state <= S_WAIT_CMD; end
                    `CMD_START:      begin cpu_stop_out <= 1'b0; state <= S_WAIT_CMD; end
                    `CMD_WRITE:      begin byte_ret <= S_STORE_AH; state <= RX_POLL; end
                    `CMD_READ:       begin byte_ret <= S_STORE_AH; state <= RX_POLL; end
                    `CMD_INST_BEGIN: begin byte_ret <= S_INST_AH;  state <= RX_POLL; end
                    `CMD_DATAMEM_READ: begin byte_ret <= S_DM_A2;  state <= RX_POLL; end
                    default:           state <= S_WAIT_CMD;
                endcase
            end
            S_EXEC_RST: begin
                cpu_rst_out  <= 1'b1;
                cpu_stop_out <= 1'b1;
                state        <= S_WAIT_CMD;
            end

            // ======================================================
            //  CMD_WRITE / CMD_READ instr_memory
            // ======================================================
            S_STORE_AH: begin
                cur_addr[15:8] <= rx_byte;
                byte_ret <= S_STORE_AL; state <= RX_POLL;
            end
            S_STORE_AL: begin
                cur_addr[7:0] <= rx_byte;
                byte_ret <= S_STORE_LEN; state <= RX_POLL;
            end
            S_STORE_LEN: begin
                word_count <= rx_byte; start_addr_reg <= cur_addr;
                offset_reg <= 8'h0; start_addr_out <= cur_addr; offset_out <= 8'h0;
                if (cur_cmd == `CMD_WRITE) begin
                    byte_pos <= 2'd3; byte_ret <= S_STORE_DATA; state <= RX_POLL;
                end else begin
                    state <= S_READ_MEM;
                end
            end
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
                    byte_pos <= byte_pos - 2'd1; byte_ret <= S_STORE_DATA; state <= RX_POLL;
                end
            end
            S_WRITE_MEM: begin
                mem_addr_reg <= cur_addr; mem_data_in_reg <= data_buf; mem_we_reg <= 1'b1;
                state <= S_WRITE_DONE;
            end
            S_WRITE_DONE: begin
                mem_we_reg <= 1'b0; cur_addr <= cur_addr + 16'd1;
                word_count <= word_count - 8'd1; offset_reg <= offset_reg + 8'd1;
                start_addr_out <= start_addr_reg; cur_addr_out <= cur_addr + 16'd1;
                offset_out <= offset_reg + 8'd1;
                if (word_count == 8'd1) begin
                    state <= S_WAIT_CMD;
                end else begin
                    byte_pos <= 2'd3; byte_ret <= S_STORE_DATA; state <= RX_POLL;
                end
            end
            S_READ_MEM: begin
                mem_addr_reg <= cur_addr; mem_we_reg <= 1'b0; state <= S_READ_LATCH;
            end
            S_READ_LATCH: begin
                data_buf <= mem_data_out; byte_pos <= 2'd3; state <= S_SEND_BYTE;
            end
            S_SEND_BYTE: begin
                case (byte_pos)
                    2'd3: tx_byte <= data_buf[31:24];
                    2'd2: tx_byte <= data_buf[23:16];
                    2'd1: tx_byte <= data_buf[15:8];
                    2'd0: tx_byte <= data_buf[7:0];
                endcase
                tx_ret <= S_SENT_BYTE; state <= TX_CHK;
            end
            S_SENT_BYTE: begin
                if (byte_pos > 2'd0) begin
                    byte_pos <= byte_pos - 2'd1; state <= S_SEND_BYTE;
                end else begin
                    state <= S_NEXT_WORD;
                end
            end
            S_NEXT_WORD: begin
                cur_addr <= cur_addr + 16'd1; word_count <= word_count - 8'd1;
                if (word_count == 8'd1) state <= S_WAIT_CMD;
                else                    state <= S_READ_MEM;
            end

            // ======================================================
            //  INST_BEGIN FSM
            // ======================================================
            S_INST_AH: begin
                cur_addr[15:8] <= rx_byte; byte_ret <= S_INST_AL; state <= RX_POLL;
                $display("%0t: S_INST_AH ADDR_HI=0x%02h", $time, rx_byte);
            end
            S_INST_AL: begin
                cur_addr[7:0]  <= rx_byte;
                start_addr_reg <= {cur_addr[15:8], rx_byte};
                offset_reg <= 8'h0; start_addr_out <= {cur_addr[15:8], rx_byte};
                cur_addr_out <= {cur_addr[15:8], rx_byte};
                byte_ret <= S_INST_CNT_H; state <= RX_POLL;
                $display("%0t: S_INST_AL ADDR_LO=0x%02h", $time, rx_byte);
            end
            S_INST_CNT_H: begin
                instr_cnt_h <= rx_byte; byte_ret <= S_INST_CNT_L; state <= RX_POLL;
            end
            S_INST_CNT_L: begin
                instr_count <= {instr_cnt_h, rx_byte};
                $display("%0t: S_INST_CNT_L COUNT=%0d", $time, {instr_cnt_h, rx_byte});
                if ({instr_cnt_h, rx_byte} != 16'h0) begin
                    byte_ret <= S_INST_RX_B1; state <= RX_POLL;
                end else begin
                    state <= S_WAIT_CMD;
                end
            end
            S_INST_RX_B1: begin
                instr_buf[15:8] <= rx_byte; byte_ret <= S_INST_RX_B2; state <= RX_POLL;
            end
            S_INST_RX_B2: begin
                instr_buf[7:0] <= rx_byte; state <= S_INST_WRITE;
            end
            S_INST_WRITE: begin
                mem_addr_reg <= cur_addr; mem_data_in_reg <= {16'h0, instr_buf};
                mem_we_reg <= 1'b1; state <= S_INST_DONE;
                $display("%0t: S_INST_WRITE addr=0x%04h data=0x%04h", $time, cur_addr, instr_buf);
            end
            S_INST_DONE: begin
                mem_we_reg <= 1'b0; cur_addr <= cur_addr + 16'd1;
                offset_reg <= offset_reg + 8'd1;
                cur_addr_out <= cur_addr + 16'd1; start_addr_out <= start_addr_reg;
                offset_out <= offset_reg + 8'd1;
                if (instr_count == 16'h1) begin
                    instr_count <= 16'h0; state <= S_WAIT_CMD;
                end else begin
                    instr_count <= instr_count - 16'd1;
                    byte_ret <= S_INST_RX_B1; state <= RX_POLL;
                end
            end

            // ======================================================
            //  CMD_DATAMEM_READ FSM
            //
            //  Flux complet:
            //    S_DM_A2   -> RX_POLL -> S_DM_A1  -> RX_POLL
            //    S_DM_A0   -> RX_POLL -> S_DM_COUNT
            //    S_DM_RD_EN (dm_rd<=1, dm_addr setat)
            //    S_DM_WAIT  (data_memory latcheaza la posedge acestui ciclu)
            //    S_DM_LATCH (dm_rd<=0, dm_data_out stabil, capturam)
            //    S_DM_TX_B3 -> TX -> S_DM_TX_B2 -> TX -> S_DM_TX_B1 -> TX -> S_DM_TX_B0 -> TX
            //    S_DM_NEXT  (mai sunt cuvinte? -> S_DM_RD_EN, altfel S_WAIT_CMD)
            //
            //  De ce 2 cicli asteptare (RD_EN + WAIT):
            //    Non-blocking: dm_rd=1 devine vizibil abia la sfarsitul ciclului RD_EN,
            //    deci data_memory il vede (si latcheaza RegAddr) abia la posedge S_DM_WAIT.
            //    La posedge S_DM_LATCH, dataMemDataout=MemData[RegAddr] este stabil.
            // ======================================================

            // --- Primeste A2: byte MSB al adresei (bits [19:16]) ---
            S_DM_A2: begin
                dm_byte_a2 <= rx_byte;
                byte_ret   <= S_DM_A1;
                state      <= RX_POLL;
                $display("%0t: S_DM_A2 A2=0x%02h (bits 19:16)", $time, rx_byte);
            end

            // --- Primeste A1: byte mijloc al adresei (bits [15:8]) ---
            S_DM_A1: begin
                dm_byte_a1 <= rx_byte;
                byte_ret   <= S_DM_A0;
                state      <= RX_POLL;
                $display("%0t: S_DM_A1 A1=0x%02h (bits 15:8)", $time, rx_byte);
            end

            // --- Primeste A0: byte LSB al adresei, asambleaza adresa 20-bit ---
            // dm_byte_a2 si dm_byte_a1 sunt stabile (latched anterior, trecute prin RX_POLL)
            // Adresa: {dm_byte_a2[3:0], dm_byte_a1[7:0], rx_byte[7:0]} = 20 biti
            S_DM_A0: begin
                dm_addr_reg <= {dm_byte_a2[3:0], dm_byte_a1, rx_byte};
                byte_ret    <= S_DM_COUNT;
                state       <= RX_POLL;
                $display("%0t: S_DM_A0 A0=0x%02h addr=0x%05h",
                         $time, rx_byte, {dm_byte_a2[3:0], dm_byte_a1, rx_byte});
            end

            // --- Primeste N: numarul de cuvinte 32-bit de citit ---
            S_DM_COUNT: begin
                $display("%0t: S_DM_COUNT N=%0d", $time, rx_byte);
                if (rx_byte != 8'h0) begin
                    dm_count <= rx_byte;
                    dm_addr  <= dm_addr_reg;  // pregatim adresa
                    state    <= S_DM_RD_EN;
                end else begin
                    state <= S_WAIT_CMD;      // N=0: nimic de facut
                end
            end

            // --- Activeaza memRd=1 si seteaza dm_addr ---
            // La sfarsitul acestui ciclu (non-blocking): dm_rd devine 1
            // data_memory va vedea memRd=1 la posedge-ul URMATOR (S_DM_WAIT)
            S_DM_RD_EN: begin
                dm_rd  <= 1'b1;
                state  <= S_DM_WAIT;
                $display("%0t: S_DM_RD_EN dm_addr=0x%05h", $time, dm_addr);
            end

            // --- Ciclu de asteptare: data_memory latcheaza RegAddr la posedge acestui ciclu ---
            // La posedge S_DM_WAIT: data_memory vede dm_rd=1, face RegAddr<=dm_addr
            // dataMemDataout = MemData[RegAddr_vechi] inca (combinational, nu e gata)
            S_DM_WAIT: begin
                state <= S_DM_LATCH;
            end

            // --- Capturam data_memory output ---
            // La posedge S_DM_LATCH: dataMemDataout = MemData[RegAddr_actualizat] = CORECT
            // dm_rd <= 0 (dezactivam citirea)
            // dm_data_latch <= dm_data_out (captuream cuvantul 32-bit)
            S_DM_LATCH: begin
                dm_rd         <= 1'b0;
                dm_data_latch <= dm_data_out;
                state         <= S_DM_TX_B3;
                $display("%0t: S_DM_LATCH dm_data_out=0x%08h", $time, dm_data_out);
            end

            // --- Transmite cele 4 bytes MSB first prin UART ---
            S_DM_TX_B3: begin
                tx_byte <= dm_data_latch[31:24];
                tx_ret  <= S_DM_TX_B2;
                state   <= TX_CHK;
            end
            S_DM_TX_B2: begin
                tx_byte <= dm_data_latch[23:16];
                tx_ret  <= S_DM_TX_B1;
                state   <= TX_CHK;
            end
            S_DM_TX_B1: begin
                tx_byte <= dm_data_latch[15:8];
                tx_ret  <= S_DM_TX_B0;
                state   <= TX_CHK;
            end
            S_DM_TX_B0: begin
                tx_byte <= dm_data_latch[7:0];
                tx_ret  <= S_DM_NEXT;
                state   <= TX_CHK;
            end

            // --- Decide daca mai sunt cuvinte de citit ---
            S_DM_NEXT: begin
                $display("%0t: S_DM_NEXT remaining=%0d", $time, dm_count - 1);
                if (dm_count == 8'd1) begin
                    // Ultimul cuvant a fost trimis
                    dm_count <= 8'h0;
                    state    <= S_WAIT_CMD;
                end else begin
                    // Mai sunt cuvinte: incrementam adresa si repetam
                    dm_count    <= dm_count - 8'd1;
                    dm_addr     <= dm_addr + 20'd1;
                    dm_addr_reg <= dm_addr_reg + 20'd1;
                    state       <= S_DM_RD_EN;
                end
            end

            // ======================================================
            default: state <= S_INIT;
            endcase
        end
    end

endmodule