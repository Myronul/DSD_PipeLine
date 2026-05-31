`timescale 1ns / 1ps
`include "cpu_macros.vh"
`include "controller_macros.vh"

module system_cntrl_mem_data_read_sim();

    reg clk;
    reg rst;

    initial clk = 0;
    always #5 clk = ~clk;

    // AXI4-Lite signals (DUT = master, TB = slave)
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
    reg  [1:0] rresp;
    reg         rvalid;
    wire        rready;

    // Instruction memory interface
    wire [`MC_ADDR_SIZE-1:0] mc_addr;
    wire [`MC_DATA_SIZE-1:0] mc_din;
    wire [`MC_DATA_SIZE-1:0] mc_dout;
    wire                     mc_we;

    // Data memory interface for CMD_MEM_READ
    wire                     data_mem_ctrl_rd;
    wire [`MC_ADDR_SIZE-1:0] data_mem_ctrl_addr;
    wire [`MC_DATA_SIZE-1:0] data_mem_ctrl_dout;

    wire cpu_rst_out;
    wire cpu_stop_out;

    // DUT: mem_ctrl
    mem_ctrl DUT (
        .clk             (clk),
        .rst             (rst),

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

        .mem_addr        (mc_addr),
        .mem_data_in     (mc_din),
        .mem_data_out    (mc_dout),
        .mem_we          (mc_we),

        .data_mem_rd     (data_mem_ctrl_rd),
        .data_mem_addr   (data_mem_ctrl_addr),
        .data_mem_data_out(data_mem_ctrl_dout),

        .cpu_rst_out     (cpu_rst_out),
        .cpu_stop_out    (cpu_stop_out),
        .cur_addr_out    (),
        .start_addr_out  (),
        .offset_out      ()
    );

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

    data_memory DATAMEM (
        .clk(clk),
        .memRd(1'b0),
        .memWr(1'b0),
        .dataMemAddr({`A_SIZE{1'b0}}),
        .dataMemDatain({`D_SIZE{1'b0}}),
        .dataMemDataout(),
        .dataCtrlRd(data_mem_ctrl_rd),
        .dataCtrlAddr({{(`A_SIZE-`MC_ADDR_SIZE){1'b0}}, data_mem_ctrl_addr}),
        .dataCtrlDataout(data_mem_ctrl_dout)
    );

    reg [7:0]  rx_fifo [0:255];
    integer    rx_head;
    integer    rx_tail;

    reg [7:0]  tx_fifo [0:255];
    integer    tx_head;

    initial begin
        rx_head = 0;
        rx_tail = 0;
        tx_head = 0;
    end

    task push_byte;
        input [7:0] b;
        integer timeout;
        begin
            rx_fifo[rx_head] = b;
            rx_head = rx_head + 1;
            $display("%0t: [TB] PUSH 0x%02h", $time, b);

            timeout = 0;
            while (rx_tail != rx_head && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 2000)
                $display("%0t: [TB] WARNING: timeout waiting for byte consumption", $time);

            repeat (5) @(posedge clk);
        end
    endtask

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
            bresp   <= 2'b00;
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rdata   <= 32'h0;
            rresp   <= 2'b00;
            rx_tail <= 0;
        end else begin
            awready <= 1'b1;
            wready  <= 1'b1;
            bresp   <= 2'b00;

            if (awvalid && wvalid)
                bvalid <= 1'b1;
            else if (bready && bvalid)
                bvalid <= 1'b0;

            arready <= 1'b0;
            if (arvalid && !rvalid) begin
                arready <= 1'b1;
                if (araddr == `UART_STAT_REG) begin
                    rdata <= (rx_head != rx_tail) ? 32'h00000005 : 32'h00000004;
                    rresp <= 2'b00;
                    rvalid <= 1'b1;
                end else begin
                    if (rx_head != rx_tail) begin
                        rdata <= {24'h0, rx_fifo[rx_tail]};
                        rx_tail <= rx_tail + 1;
                        rresp <= 2'b00;
                        rvalid <= 1'b1;
                    end
                end
            end

            if (rvalid && rready)
                rvalid <= 1'b0;

            if (awvalid && wvalid && awaddr == `UART_TX_FIFO) begin
                tx_fifo[tx_head] <= wdata[7:0];
                tx_head <= tx_head + 1;
                $display("%0t: [TB] TX_BYTE 0x%02h", $time, wdata[7:0]);
            end
        end
    end

    integer test_pass;
    initial begin
        test_pass = 1;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // Load known data into data memory
        DATAMEM.MemData[0] = 32'hAABBCCDD;
        DATAMEM.MemData[1] = 32'h11223344;

        $display("\n=== TEST: CMD_MEM_READ 0xBB read 5 bytes from data memory ===");
        push_byte(`CMD_MEM_READ);
        push_byte(8'h00);
        push_byte(8'h00);
        push_byte(8'h05);

        repeat (400) @(posedge clk);

        if (tx_head !== 5) begin
            $display("  FAIL: expected 5 bytes sent, got %0d", tx_head);
            test_pass = 0;
        end else begin
            if (tx_fifo[0] !== 8'hAA) test_pass = 0;
            if (tx_fifo[1] !== 8'hBB) test_pass = 0;
            if (tx_fifo[2] !== 8'hCC) test_pass = 0;
            if (tx_fifo[3] !== 8'hDD) test_pass = 0;
            if (tx_fifo[4] !== 8'h11) test_pass = 0;
        end

        if (test_pass)
            $display("\n*** TEST CMD_MEM_READ TRECUT ***\n");
        else begin
            $display("\n*** TEST CMD_MEM_READ ESELUAU ***\n");
            $display("Received bytes: %02h %02h %02h %02h %02h",
                     tx_fifo[0], tx_fifo[1], tx_fifo[2], tx_fifo[3], tx_fifo[4]);
        end

        $finish;
    end

endmodule
