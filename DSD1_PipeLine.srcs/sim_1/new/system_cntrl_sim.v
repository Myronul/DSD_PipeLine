`timescale 1ns / 1ps
`include "cpu_macros.vh"
`include "controller_macros.vh"

// ============================================================
//  system_cntrl_sim_fixed.v  -  Testbench pentru mem_ctrl
//
//  Arhitectura:
//    - Bytes sunt injectati DIRECT in rx_fifo (fara UART serial)
//    - AXI4-Lite Slave simulat in always block sincron
//    - Task push_byte() injecteaza un byte si asteapta consumarea
//
//  Scenarii testate:
//    1. CMD_RESET / CMD_STOP / CMD_START
//    2. CMD_INST_BEGIN cu 0xAA: 3 instructiuni la adresa 0x0010
//    3. CMD_INST_BEGIN cu 0xAA: 2 instructiuni la adresa 0x0000
//    4. CMD_INST_BEGIN cu COUNT=0 (caz limita)
//    5. Verificare finala a continutului memoriei
//
//  IMPORTANT despre timing push_byte:
//    Fiecare byte trece prin ~10-15 cicli de AXI (RX_POLL -> AXI_RD_1..3
//    -> RX_CHK -> AXI_RD_1..3 -> RX_GOT). Timeout-ul de 2000 cicli e
//    intentionat mai mare decat cel din versiunea originala (500 cicli)
//    pentru a acomoda orice intarziere a slave-ului AXI simulat.
// ============================================================

module ctrl_sim();

// ----------------------------------------------------------
//  Clock si reset
// ----------------------------------------------------------
reg clk;
reg rst;

initial clk = 0;
always  #5 clk = ~clk;   // 100 MHz (perioda 10 ns)

// ----------------------------------------------------------
//  AXI4-Lite signals (DUT = master, TB = slave)
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
//  Interfata memorie (conectata intre mem_ctrl si instr_memory)
// ----------------------------------------------------------
wire [`MC_ADDR_SIZE-1:0] mc_addr;
wire [`MC_DATA_SIZE-1:0] mc_din;
wire [`MC_DATA_SIZE-1:0] mc_dout;
wire                     mc_we;

// ----------------------------------------------------------
//  CPU control + monitoring
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
    .clk            (clk),
    .rst            (rst),
    // AXI4-Lite
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
    // Memorie instructiuni
    .mem_addr       (mc_addr),
    .mem_data_in    (mc_din),
    .mem_data_out   (mc_dout),
    .mem_we         (mc_we),
    // CPU control
    .cpu_rst_out    (cpu_rst_out),
    .cpu_stop_out   (cpu_stop_out),
    // Monitorizare
    .cur_addr_out   (mc_cur_addr),
    .start_addr_out (mc_start_addr),
    .offset_out     (mc_offset)
);

// ----------------------------------------------------------
//  instr_memory conectata la DUT
//  Port A (write): primeste de la mem_ctrl
//  Port B (read):  adresa 0 (CPU nu ruleaza in testbench)
// ----------------------------------------------------------
instr_memory IMEM (
    // Port B: CPU (adresa 0, neutilizata in testbench)
    .addr    ({`A_SIZE{1'b0}}),
    .dataOut (),
    // Port A: mem_ctrl (write)
    .clk     (clk),
    .wr_addr (mc_addr),
    .wr_data (mc_din[`INSTR_SIZE-1:0]),  // doar [15:0] din cei 32 bit
    .wr_en   (mc_we),
    // Readback pentru CMD_READ
    .rd_addr (mc_addr),
    .rd_data (mc_dout)
);

// ----------------------------------------------------------
//  RX FIFO SOFTWARE
//  rx_head: avansat de task-ul push_byte (stimulus initial)
//  rx_tail: avansat de slave-ul AXI (always block) la fiecare citire
//
//  Comportament:
//    - Cand DUT face AXI Read pe UART_STAT_REG -> returnam RXVALID=1 daca
//      exista bytes, altfel RXVALID=0
//    - Cand DUT face AXI Read pe UART_RX_FIFO -> returnam rx_fifo[rx_tail]
//      si incrementam rx_tail
// ----------------------------------------------------------
reg [7:0]  rx_fifo [0:255];
integer    rx_head;
integer    rx_tail;

initial begin
    rx_head = 0;
    rx_tail = 0;
end

// ----------------------------------------------------------
//  Task: push_byte
//  Injecteaza un byte in FIFO si asteapta ca DUT sa-l consume.
//  Timeout: 2000 cicli de clock (20 microsecunde la 100 MHz).
//  Dupa consum, asteapta 5 cicli suplimentari pentru ca FSM-ul
//  sa proceseze byte-ul inainte de urmatoarea injectare.
// ----------------------------------------------------------
task push_byte;
    input [7:0] b;
    integer timeout;
    begin
        rx_fifo[rx_head] = b;
        rx_head = rx_head + 1;
        $display("%0t: [TB] PUSH 0x%02h  (fifo depth=%0d)", $time, b, rx_head - rx_tail);

        // Asteapta ca rx_tail sa avanseze (DUT a citit byte-ul)
        timeout = 0;
        while (rx_tail != rx_head && timeout < 2000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 2000)
            $display("%0t: [TB] WARNING: timeout asteptand consumarea 0x%02h (fifo stuck!)", $time, b);

        // Mica pauza: lasa FSM-ul sa proceseze byte-ul si sa treaca
        // in starea urmatoare inainte de a injecta urmatorul byte
        repeat(5) @(posedge clk);
    end
endtask

// ----------------------------------------------------------
//  AXI4-Lite Slave (comportament corect, pipeline-safe)
//
//  Citiri:
//    1. Latch adresa + arready=1 in ciclul cand arvalid=1
//    2. In ciclul urmator: pregateste data si ridica rvalid
//    3. Mentine rvalid pana DUT confirma cu rready=1
//
//  Scrieri:
//    - awready si wready permanent HIGH (accept imediat)
//    - bvalid ridicat cand atat awvalid cat si wvalid sunt HIGH
//    - bvalid coborat cand DUT confirma cu bready=1
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

        // ---- Canal de scriere: accept imediat ----
        awready <= 1'b1;
        wready  <= 1'b1;
        bresp   <= 2'b00;

        // bvalid: ridicat cand ambele canale sunt valide simultan
        if (awvalid && wvalid)
            bvalid <= 1'b1;
        else if (bready && bvalid)
            bvalid <= 1'b0;

        // ---- Canal de citire ----
        // Default: arready dezactivat (puls de 1 ciclu)
        arready <= 1'b0;

        // Pas 1: Latch adresa cand DUT prezinta arvalid
        //   Conditie: nu avem deja o cerere in curs (ar_pending=0)
        //   si nu avem deja un raspuns activ (rvalid=0)
        if (arvalid && !ar_pending && !rvalid) begin
            ar_addr_lat <= araddr;
            ar_pending  <= 1'b1;
            arready     <= 1'b1;  // confirma adresa in ACELASI ciclu
        end

        // Pas 2: Pregateste si trimite data in ciclul urmator
        if (ar_pending && !rvalid) begin
            ar_pending <= 1'b0;
            rresp      <= 2'b00;

            if (ar_addr_lat == `UART_STAT_REG) begin
                // Status register:
                //   Bit 0 (RXVALID) = 1 daca exista bytes in FIFO
                //   Bit 2 (TXEMPTY) = intotdeauna 1 (TX FIFO mereu liber)
                rdata  <= (rx_head != rx_tail) ? 32'h00000005 : 32'h00000004;
                rvalid <= 1'b1;
            end else begin
                // RX FIFO: citeste urmatorul byte daca exista
                if (rx_head != rx_tail) begin
                    rdata    <= {24'h0, rx_fifo[rx_tail]};
                    rx_tail  <= rx_tail + 1;
                    rvalid   <= 1'b1;
                end
                // Daca FIFO e gol, nu ridicam rvalid.
                // Situatia nu ar trebui sa apara daca DUT verifica STAT_REG
                // inainte sa citeasca RX_FIFO (ceea ce face corect).
            end
        end

        // Pas 3: Sterge rvalid dupa handshake (rvalid && rready)
        if (rvalid && rready)
            rvalid <= 1'b0;

    end
end

// ----------------------------------------------------------
//  Monitor: afiseaza orice scriere in instr_memory
// ----------------------------------------------------------
always @(posedge clk) begin
    if (mc_we) begin
        $display("%0t: [MEM] WRITE addr=0x%04h data=0x%04h",
                 $time, mc_addr, mc_din[15:0]);
    end
end

// ----------------------------------------------------------
//  Stimulus principal
// ----------------------------------------------------------
integer test_pass;
initial begin
    test_pass = 1;

    // ---- Reset initial ----
    rst = 1'b1;
    repeat(5) @(posedge clk);
    rst = 1'b0;
    repeat(5) @(posedge clk);

    // ==================================================
    //  TEST 1: Comenzi simple de control CPU
    // ==================================================
    $display("\n=== TEST 1: CMD_RESET / CMD_STOP / CMD_START ===");
    push_byte(`CMD_RESET);
    push_byte(`CMD_STOP);
    push_byte(`CMD_START);
    $display("    cpu_stop_out=%b (asteptat 0)", cpu_stop_out);

    // ==================================================
    //  TEST 2: CMD_INST_BEGIN (0xAA)
    //  Incarca 3 instructiuni la adresa 0x0010
    //    instr[0x10] = 0xC207
    //    instr[0x11] = 0xC205
    //    instr[0x12] = 0x0000 (NOP)
    // ==================================================
    $display("\n=== TEST 2: CMD_INST_BEGIN - 3 instructiuni la 0x0010 ===");
    push_byte(`CMD_INST_BEGIN);    // 0xAA - comanda de start incarcare
    push_byte(8'h00);              // ADDR_HI = 0x00
    push_byte(8'h10);              // ADDR_LO = 0x10  => adresa de start = 0x0010
    push_byte(8'h00);              // COUNT_HI = 0x00
    push_byte(8'h03);              // COUNT_LO = 0x03 => 3 instructiuni

    // Instructiunea 0: 0xC207 (LOADC R2, 7)
    push_byte(8'hC2);
    push_byte(8'h07);

    // Instructiunea 1: 0xC205 (LOADC R2, 5)
    push_byte(8'hC2);
    push_byte(8'h05);

    // Instructiunea 2: 0x0000 (NOP)
    push_byte(8'h00);
    push_byte(8'h00);

    // Asteapta finalizarea scrierilor
    repeat(200) @(posedge clk);

    // ==================================================
    //  TEST 3: A doua comanda CMD_INST_BEGIN
    //  Incarca 2 instructiuni la adresa 0x0000
    //    instr[0x00] = 0xAABB
    //    instr[0x01] = 0x1234
    // ==================================================
    $display("\n=== TEST 3: CMD_INST_BEGIN - 2 instructiuni la 0x0000 ===");
    push_byte(`CMD_INST_BEGIN);
    push_byte(8'h00);  // ADDR_HI
    push_byte(8'h00);  // ADDR_LO => adresa 0x0000
    push_byte(8'h00);  // COUNT_HI
    push_byte(8'h02);  // COUNT_LO => 2 instructiuni

    push_byte(8'hAA);
    push_byte(8'hBB);  // instr[0x00] = 0xAABB

    push_byte(8'h12);
    push_byte(8'h34);  // instr[0x01] = 0x1234

    repeat(200) @(posedge clk);

    // ==================================================
    //  TEST 4: COUNT=0 (caz limita)
    // ==================================================
    $display("\n=== TEST 4: CMD_INST_BEGIN cu COUNT=0 (caz limita) ===");
    push_byte(`CMD_INST_BEGIN);
    push_byte(8'hFF);  // ADDR_HI (nu conteaza, nu se scrie nimic)
    push_byte(8'hFF);  // ADDR_LO
    push_byte(8'h00);  // COUNT_HI
    push_byte(8'h00);  // COUNT_LO = 0 => nu urmeaza bytes de instructiuni

    repeat(100) @(posedge clk);

    // ==================================================
    //  Dupa COUNT=0, FSM-ul trebuie sa fie in S_WAIT_CMD.
    //  Trimitm o comanda CMD_STOP pentru a verifica.
    // ==================================================
    $display("    Trimitere CMD_STOP pentru a verifica ca FSM e in S_WAIT_CMD...");
    push_byte(`CMD_STOP);
    repeat(50) @(posedge clk);
    $display("    cpu_stop_out=%b (asteptat 1)", cpu_stop_out);

    // ==================================================
    //  VERIFICARE FINALA A MEMORIEI
    // ==================================================
    $display("\n=== VERIFICARE FINALA ===");
    $display("instr_memory[0x10] = 0x%04h  (asteptat 0xC207)", IMEM.instrMemory[16]);
    $display("instr_memory[0x11] = 0x%04h  (asteptat 0xC205)", IMEM.instrMemory[17]);
    $display("instr_memory[0x12] = 0x%04h  (asteptat 0x0000)", IMEM.instrMemory[18]);
    $display("instr_memory[0x00] = 0x%04h  (asteptat 0xAABB)", IMEM.instrMemory[0]);
    $display("instr_memory[0x01] = 0x%04h  (asteptat 0x1234)", IMEM.instrMemory[1]);

    // Verificare TEST 2
    if (IMEM.instrMemory[16] !== 16'hC207) begin
        $display("  FAIL: instr[0x10] = %04h, asteptat C207", IMEM.instrMemory[16]);
        test_pass = 0;
    end
    if (IMEM.instrMemory[17] !== 16'hC205) begin
        $display("  FAIL: instr[0x11] = %04h, asteptat C205", IMEM.instrMemory[17]);
        test_pass = 0;
    end
    if (IMEM.instrMemory[18] !== 16'h0000) begin
        $display("  FAIL: instr[0x12] = %04h, asteptat 0000", IMEM.instrMemory[18]);
        test_pass = 0;
    end

    // Verificare TEST 3
    if (IMEM.instrMemory[0] !== 16'hAABB) begin
        $display("  FAIL: instr[0x00] = %04h, asteptat AABB", IMEM.instrMemory[0]);
        test_pass = 0;
    end
    if (IMEM.instrMemory[1] !== 16'h1234) begin
        $display("  FAIL: instr[0x01] = %04h, asteptat 1234", IMEM.instrMemory[1]);
        test_pass = 0;
    end

    // Verificare TEST 4 (cpu_stop_out)
    if (cpu_stop_out !== 1'b1) begin
        $display("  FAIL: cpu_stop_out=%b dupa COUNT=0+CMD_STOP, asteptat 1", cpu_stop_out);
        test_pass = 0;
    end

    if (test_pass)
        $display("\n*** TOATE TESTELE AU TRECUT ***\n");
    else
        $display("\n*** UNELE TESTE AU ESUAT - vezi mai sus ***\n");

    $finish;
end

endmodule