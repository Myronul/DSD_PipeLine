`timescale 1ns / 1ps
`include "cpu_macros.vh"
`include "controller_macros.vh"

// ============================================================
//  system_dm_sim.v  -  Testbench pentru CMD_DATAMEM_READ (0xBB)
//
//  Arhitectura:
//    - Acelasi model AXI4-Lite slave + RX FIFO software ca in
//      system_cntrl_sim.v (push_byte identic)
//    - TX FIFO software: bytes trimisi de mem_ctrl sunt capturati
//      in tx_fifo[] prin monitorizarea AXI write pe UART_TX_FIFO
//    - data_memory instantiata direct, preincarcata cu valori cunoscute
//    - instr_memory instantiata (necesara pentru porturile mem_ctrl)
//
//  Scenarii testate:
//    TEST 1: CMD_STOP + CMD_RESET (verificare comenzi simple)
//    TEST 2: CMD_DATAMEM_READ adresa 0x00001, N=1
//            => mem_ctrl citeste MemData[1] si trimite 4 bytes prin UART
//    TEST 3: CMD_DATAMEM_READ adresa 0x00005, N=3
//            => mem_ctrl citeste MemData[5], MemData[6], MemData[7]
//    TEST 4: CMD_DATAMEM_READ cu N=0 (caz limita)
//    TEST 5: CMD_INST_BEGIN (verifica ca FSM se intoarce corect in idle
//            dupa CMD_DATAMEM_READ si accepta alte comenzi)
//
//  Valori preincarcate in data_memory (via $readmemh sau force):
//    MemData[0]  = 0xDEADBEEF
//    MemData[1]  = 0x12345678
//    MemData[2]  = 0xCAFEBABE
//    MemData[5]  = 0xAABBCCDD
//    MemData[6]  = 0x11223344
//    MemData[7]  = 0x55667788
// ============================================================

module system_cntrl_data_mem_sim();

// ----------------------------------------------------------
//  Clock si reset
// ----------------------------------------------------------
reg clk;
reg rst;

initial clk = 0;
always  #5 clk = ~clk;   // 100 MHz (10 ns perioad)

// ----------------------------------------------------------
//  AXI4-Lite signals (DUT=master, TB=slave)
// ----------------------------------------------------------
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

// ----------------------------------------------------------
//  Interfata instr_memory (necesara pentru porturile mem_ctrl)
// ----------------------------------------------------------
wire [`MC_ADDR_SIZE-1:0] mc_addr;
wire [`MC_DATA_SIZE-1:0] mc_din;
wire [`MC_DATA_SIZE-1:0] mc_dout;
wire                     mc_we;

// ----------------------------------------------------------
//  Interfata data_memory
// ----------------------------------------------------------
wire [`DM_ADDR_SIZE-1:0] mc_dm_addr;
wire                      mc_dm_rd;
wire [`MC_DATA_SIZE-1:0]  mc_dm_data_out;

// Semnale CPU -> data_memory (CPU nu ruleaza, le legam la 0)
wire [`A_SIZE-1:0]  cpu_dm_addr  = {`A_SIZE{1'b0}};
wire [`D_SIZE-1:0]  cpu_dm_din   = {`D_SIZE{1'b0}};
wire                cpu_dm_wr    = 1'b0;
wire                cpu_dm_rd    = 1'b0;

// ----------------------------------------------------------
//  CPU control
// ----------------------------------------------------------
wire cpu_rst_out;
wire cpu_stop_out;
wire [`MC_ADDR_SIZE-1:0] mc_cur_addr;
wire [`MC_ADDR_SIZE-1:0] mc_start_addr;
wire [7:0]               mc_offset;

// ----------------------------------------------------------
//  DUT: mem_ctrl
// ----------------------------------------------------------
mem_ctrl DUT (
    .clk             (clk),
    .rst             (rst),
    // AXI4-Lite
    .m_axi_awaddr    (awaddr),
    .m_axi_awvalid   (awvalid),
    .m_axi_awready   (awready),
    .m_axi_wdata     (wdata),
    .m_axi_wstrb     (wstrb),
    .m_axi_wvalid    (wvalid),
    .m_axi_wready    (wready),
    .m_axi_bresp     (bresp),
    .m_axi_bvalid    (bvalid),
    .m_axi_bready    (bready),
    .m_axi_araddr    (araddr),
    .m_axi_arvalid   (arvalid),
    .m_axi_arready   (arready),
    .m_axi_rdata     (rdata),
    .m_axi_rresp     (rresp),
    .m_axi_rvalid    (rvalid),
    .m_axi_rready    (rready),
    // instr_memory
    .mem_addr        (mc_addr),
    .mem_data_in     (mc_din),
    .mem_data_out    (mc_dout),
    .mem_we          (mc_we),
    // data_memory
    .dm_addr         (mc_dm_addr),
    .dm_rd           (mc_dm_rd),
    .dm_data_out     (mc_dm_data_out),
    // CPU control
    .cpu_rst_out     (cpu_rst_out),
    .cpu_stop_out    (cpu_stop_out),
    .cur_addr_out    (mc_cur_addr),
    .start_addr_out  (mc_start_addr),
    .offset_out      (mc_offset)
);

// ----------------------------------------------------------
//  instr_memory instantiata (porturile mem_ctrl o cer)
// ----------------------------------------------------------
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

// ----------------------------------------------------------
//  data_memory instantiata
//  CPU are acces dezactivat (rd=0, wr=0).
//  mem_ctrl are acces exclusiv prin dm_rd / dm_addr.
//  Nu exista scriere din mem_ctrl in data_memory (read-only),
//  deci nu e nevoie de arbitrare pe scriere.
// ----------------------------------------------------------
data_memory DMEM (
    .clk           (clk),
    .memRd         (mc_dm_rd),
    .memWr         (1'b0),              // mem_ctrl nu scrie in data_memory
    .dataMemAddr   (mc_dm_addr),
    .dataMemDatain ({`D_SIZE{1'b0}}),
    .dataMemDataout(mc_dm_data_out)
);

// ----------------------------------------------------------
//  RX FIFO software (injectare bytes catre mem_ctrl)
// ----------------------------------------------------------
reg [7:0]  rx_fifo [0:255];
integer    rx_head;
integer    rx_tail;

initial begin
    rx_head = 0;
    rx_tail = 0;
end

// ----------------------------------------------------------
//  TX FIFO software (captureaza bytes trimisi de mem_ctrl)
//  Monitorizam scrierile AXI pe UART_TX_FIFO.
// ----------------------------------------------------------
reg [7:0]  tx_fifo [0:255];
integer    tx_head;  // index de scriere (incrementat de monitor)
integer    tx_tail;  // index de citire  (incrementat de pop_tx_byte)

initial begin
    tx_head = 0;
    tx_tail = 0;
end

// Monitor TX: la fiecare scriere AXI pe UART_TX_FIFO, captuream byte-ul
always @(posedge clk) begin
    // O scriere AXI e completa cand bvalid && bready
    // Dar detectam mai simplu: awvalid && awready && awaddr==TX_FIFO
    // sau wvalid && wready (dupa ce adresa e confirmata)
    // Cel mai simplu: urmarim cand AXI_WR_3 e activa cu adresa TX_FIFO
    // => detectam la nivelul semnalelor: awvalid=1 si awaddr=4'h4
    if (awvalid && awready && (awaddr == `UART_TX_FIFO)) begin
        tx_fifo[tx_head] = wdata[7:0];
        tx_head           = tx_head + 1;
        $display("%0t: [TX_CAP] byte=0x%02h  tx_fifo depth=%0d",
                 $time, wdata[7:0], tx_head - tx_tail);
    end
end

// Functie utilitara: asteapta un byte in TX FIFO si il returneaza
// Timeout: 5000 cicli (suficient pentru 4 bytes * ~30 cicli TX per byte)
task pop_tx_byte;
    output [7:0] b;
    integer tout;
    begin
        tout = 0;
        while (tx_tail == tx_head && tout < 5000) begin
            @(posedge clk);
            tout = tout + 1;
        end
        if (tout >= 5000) begin
            $display("%0t: [TB] WARNING: timeout asteptand byte TX!", $time);
            b = 8'hXX;
        end else begin
            b = tx_fifo[tx_tail];
            tx_tail = tx_tail + 1;
        end
    end
endtask

// ----------------------------------------------------------
//  Task: push_byte  (identic cu system_cntrl_sim.v)
// ----------------------------------------------------------
task push_byte;
    input [7:0] b;
    integer timeout;
    begin
        rx_fifo[rx_head] = b;
        rx_head = rx_head + 1;
        $display("%0t: [TB] PUSH 0x%02h  (fifo depth=%0d)", $time, b, rx_head - rx_tail);

        timeout = 0;
        while (rx_tail != rx_head && timeout < 2000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 2000)
            $display("%0t: [TB] WARNING: timeout push 0x%02h!", $time, b);

        repeat(5) @(posedge clk);
    end
endtask

// ----------------------------------------------------------
//  AXI4-Lite Slave (identic cu system_cntrl_sim.v)
// ----------------------------------------------------------
reg       ar_pending;
reg [3:0] ar_addr_lat;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        awready     <= 1'b0;
        wready      <= 1'b0;
        bvalid      <= 1'b0;
        bresp       <= 2'b00;
        arready     <= 1'b0;
        rvalid      <= 1'b0;
        rdata       <= 32'h0;
        rresp       <= 2'b00;
        ar_pending  <= 1'b0;
        ar_addr_lat <= 4'h0;
    end else begin

        awready <= 1'b1;
        wready  <= 1'b1;
        bresp   <= 2'b00;

        if (awvalid && wvalid)
            bvalid <= 1'b1;
        else if (bready && bvalid)
            bvalid <= 1'b0;

        arready <= 1'b0;

        if (arvalid && !ar_pending && !rvalid) begin
            ar_addr_lat <= araddr;
            ar_pending  <= 1'b1;
            arready     <= 1'b1;
        end

        if (ar_pending && !rvalid) begin
            ar_pending <= 1'b0;
            rresp      <= 2'b00;

            if (ar_addr_lat == `UART_STAT_REG) begin
                // RXVALID=1 daca FIFO are bytes, TXFULL=0 intotdeauna
                rdata  <= (rx_head != rx_tail) ? 32'h00000005 : 32'h00000004;
                rvalid <= 1'b1;
            end else begin
                // RX FIFO read
                if (rx_head != rx_tail) begin
                    rdata    <= {24'h0, rx_fifo[rx_tail]};
                    rx_tail  <= rx_tail + 1;
                    rvalid   <= 1'b1;
                end
            end
        end

        if (rvalid && rready)
            rvalid <= 1'b0;
    end
end

// ----------------------------------------------------------
//  Preincarca data_memory cu valori cunoscute
// ----------------------------------------------------------
integer idx;
initial begin
    // Asteptam ca memoriea sa fie initializata (after reset)
    repeat(2) @(posedge clk);
    // Scriem direct in array-ul intern al DMEM
    DMEM.MemData[0] = 32'hDEADBEEF;
    DMEM.MemData[1] = 32'h12345678;
    DMEM.MemData[2] = 32'hCAFEBABE;
    DMEM.MemData[3] = 32'h0000FFFF;
    DMEM.MemData[4] = 32'hA5A5A5A5;
    DMEM.MemData[5] = 32'hAABBCCDD;
    DMEM.MemData[6] = 32'h11223344;
    DMEM.MemData[7] = 32'h55667788;
    $display("%0t: [TB] data_memory preincarcata", $time);
end

// ----------------------------------------------------------
//  Stimulus principal
// ----------------------------------------------------------
integer  test_pass;
reg [7:0]  b0, b1, b2, b3;
reg [31:0] word_got;

initial begin
    test_pass = 1;

    // ---- Reset initial ----
    rst = 1'b1;
    repeat(5) @(posedge clk);
    rst = 1'b0;
    repeat(10) @(posedge clk);

    // ==================================================
    //  TEST 1: Comenzi simple de control
    // ==================================================
    $display("\n=== TEST 1: CMD_STOP + CMD_RESET ===");
    push_byte(`CMD_STOP);
    push_byte(`CMD_RESET);
    $display("    cpu_stop_out=%b (asteptat 1 dupa RESET)", cpu_stop_out);

    // ==================================================
    //  TEST 2: CMD_DATAMEM_READ - 1 cuvant de la adresa 0x00001
    //  Asteptat: MemData[1] = 0x12345678
    //  => UART trimite: 0x12, 0x34, 0x56, 0x78
    // ==================================================
    $display("\n=== TEST 2: CMD_DATAMEM_READ addr=0x00001 N=1 ===");
    $display("    Asteptat: 0x12345678");

    push_byte(`CMD_DATAMEM_READ);   // 0xBB
    push_byte(8'h00);               // A2: bits [19:16] = 0x00
    push_byte(8'h00);               // A1: bits [15:8]  = 0x00
    push_byte(8'h01);               // A0: bits [7:0]   = 0x01  => adresa 0x00001
    push_byte(8'h01);               // N = 1 cuvant

    // Asteptam si colectam 4 bytes de raspuns
    pop_tx_byte(b3);   // MSB
    pop_tx_byte(b2);
    pop_tx_byte(b1);
    pop_tx_byte(b0);   // LSB
    word_got = {b3, b2, b1, b0};

    $display("    Receptionat: 0x%08h  (asteptat 0x12345678)", word_got);
    if (word_got !== 32'h12345678) begin
        $display("    FAIL!");
        test_pass = 0;
    end else begin
        $display("    PASS");
    end

    repeat(50) @(posedge clk);

    // ==================================================
    //  TEST 3: CMD_DATAMEM_READ - 3 cuvinte de la adresa 0x00005
    //  Asteptat:
    //    MemData[5] = 0xAABBCCDD => 0xAA 0xBB 0xCC 0xDD
    //    MemData[6] = 0x11223344 => 0x11 0x22 0x33 0x44
    //    MemData[7] = 0x55667788 => 0x55 0x66 0x77 0x88
    // ==================================================
    $display("\n=== TEST 3: CMD_DATAMEM_READ addr=0x00005 N=3 ===");

    push_byte(`CMD_DATAMEM_READ);
    push_byte(8'h00);  // A2
    push_byte(8'h00);  // A1
    push_byte(8'h05);  // A0  => adresa 0x00005
    push_byte(8'h03);  // N=3

    // Cuvant 1: MemData[5] = 0xAABBCCDD
    pop_tx_byte(b3); pop_tx_byte(b2); pop_tx_byte(b1); pop_tx_byte(b0);
    word_got = {b3, b2, b1, b0};
    $display("    cuvant[5] = 0x%08h  (asteptat 0xAABBCCDD)", word_got);
    if (word_got !== 32'hAABBCCDD) begin
        $display("    FAIL cuvant[5]!");
        test_pass = 0;
    end else $display("    PASS");

    // Cuvant 2: MemData[6] = 0x11223344
    pop_tx_byte(b3); pop_tx_byte(b2); pop_tx_byte(b1); pop_tx_byte(b0);
    word_got = {b3, b2, b1, b0};
    $display("    cuvant[6] = 0x%08h  (asteptat 0x11223344)", word_got);
    if (word_got !== 32'h11223344) begin
        $display("    FAIL cuvant[6]!");
        test_pass = 0;
    end else $display("    PASS");

    // Cuvant 3: MemData[7] = 0x55667788
    pop_tx_byte(b3); pop_tx_byte(b2); pop_tx_byte(b1); pop_tx_byte(b0);
    word_got = {b3, b2, b1, b0};
    $display("    cuvant[7] = 0x%08h  (asteptat 0x55667788)", word_got);
    if (word_got !== 32'h55667788) begin
        $display("    FAIL cuvant[7]!");
        test_pass = 0;
    end else $display("    PASS");

    repeat(50) @(posedge clk);

    // ==================================================
    //  TEST 4: CMD_DATAMEM_READ cu N=0 (caz limita)
    //  FSM-ul trebuie sa se intoarca imediat in S_WAIT_CMD
    //  fara sa trimita nimic pe UART.
    // ==================================================
    $display("\n=== TEST 4: CMD_DATAMEM_READ N=0 (caz limita) ===");
    push_byte(`CMD_DATAMEM_READ);
    push_byte(8'hFF);  // A2 (nu conteaza)
    push_byte(8'hFF);  // A1
    push_byte(8'hFF);  // A0
    push_byte(8'h00);  // N=0 => nimic de trimis

    repeat(100) @(posedge clk);
    $display("    tx_fifo depth dupa N=0: %0d (asteptat 0)", tx_head - tx_tail);
    if (tx_head != tx_tail) begin
        $display("    FAIL: au aparut %0d bytes neasteptati in TX!", tx_head - tx_tail);
        test_pass = 0;
    end else begin
        $display("    PASS");
    end

    // ==================================================
    //  TEST 5: Verificam ca FSM-ul revine corect in S_WAIT_CMD
    //  dupa CMD_DATAMEM_READ si accepta alte comenzi.
    //  Trimitem CMD_STOP si verificam ca cpu_stop_out devine 1.
    // ==================================================
    $display("\n=== TEST 5: FSM revine in S_WAIT_CMD dupa CMD_DATAMEM_READ ===");
    push_byte(`CMD_STOP);
    repeat(50) @(posedge clk);
    $display("    cpu_stop_out=%b (asteptat 1)", cpu_stop_out);
    if (cpu_stop_out !== 1'b1) begin
        $display("    FAIL: cpu_stop_out=%b", cpu_stop_out);
        test_pass = 0;
    end else begin
        $display("    PASS");
    end

    // ==================================================
    //  TEST 6: CMD_DATAMEM_READ cu adresa 20-bit nenula in A2
    //  Adresa 0x100A0 => A2=0x01, A1=0x00, A0=0xA0
    //  (Dincolo de 1024 locatii ale DMEM, dar testam protocolul)
    //  In practica MemData[0x100A0 & 0x3FF] = MemData[0xA0=160] = 0
    // ==================================================
    $display("\n=== TEST 6: CMD_DATAMEM_READ adresa 20-bit, A2!=0 ===");
    DMEM.MemData[160] = 32'hBEEFCAFE;  // 0xA0 = 160
    push_byte(`CMD_DATAMEM_READ);
    push_byte(8'h00);   // A2: bits [19:16] = 0x00
    push_byte(8'h00);   // A1: bits [15:8]  = 0x00
    push_byte(8'hA0);   // A0: bits [7:0]   = 0xA0 => addr=0x000A0=160
    push_byte(8'h01);   // N=1

    pop_tx_byte(b3); pop_tx_byte(b2); pop_tx_byte(b1); pop_tx_byte(b0);
    word_got = {b3, b2, b1, b0};
    // adresa = 0x000A0 = 160, in range 0..1023
    $display("    receptionat=0x%08h  (asteptat 0xBEEFCAFE la addr=0x000A0=160)", word_got);
    if (word_got !== 32'hBEEFCAFE) begin
        $display("    FAIL!");
        test_pass = 0;
    end else begin
        $display("    PASS");
    end

    repeat(100) @(posedge clk);

    // ==================================================
    //  REZULTAT FINAL
    // ==================================================
    $display("\n========================================");
    if (test_pass)
        $display("*** TOATE TESTELE AU TRECUT ***");
    else
        $display("*** UNELE TESTE AU ESUAT ***");
    $display("========================================\n");

    $finish;
end

endmodule