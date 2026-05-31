`timescale 1ns / 1ps
`include "cpu_macros.vh"
`include "controller_macros.vh"

// ============================================================
//  instr_memory.v  -  Instruction Memory (pseudo dual-port)
//
//  Port A (write) - mem_ctrl programs instructions via UART
//  Port B (read)  - CPU fetch stage reads instructions via PC
//
//  Port A writes are synchronous (clk).
//  Port B reads  are asynchronous (combinational), same
//  behaviour as the original single-port ROM so fetch_stage
//  requires no changes.
//
//  rd_addr / rd_data provide an extra asynchronous read path
//  for mem_ctrl CMD_READ readback (collision-free because
//  cpu_stop=1 whenever the controller reads back memory).
//
//  NOTE: wr_addr and rd_addr use MC_ADDR_SIZE (16-bit) because
//  mem_ctrl works with 16-bit word addresses. The CPU port
//  (addr) keeps A_SIZE (20-bit) as before. rd_data is 32-bit
//  to match the controller data bus width (upper bits are 0).
// ============================================================

module instr_memory(
    // Port B: CPU fetch stage (read-only, unchanged)
    input  wire [`A_SIZE-1:0]        addr,     // program counter address
    output wire [`INSTR_SIZE-1:0]    dataOut,  // instruction word to CPU

    // Port A: mem_ctrl write port
    input  wire                      clk,      // clock for synchronous write
    input  wire [`MC_ADDR_SIZE-1:0]  wr_addr,  // write address from controller
    input  wire [`INSTR_SIZE-1:0]    wr_data,  // data to write from controller
    input  wire                      wr_en,    // write enable (active high)

    // Readback for mem_ctrl CMD_READ
    input  wire [`MC_ADDR_SIZE-1:0]  rd_addr,  // read address from controller
    output wire [31:0]               rd_data   // data back to controller (32-bit, upper bits 0)
);

    // Instruction memory array: 1024 locations of INSTR_SIZE bits
    reg [`INSTR_SIZE-1:0] instrMemory [0:1023];

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            instrMemory[i] = 16'h0000;
    end

    // Default program loaded at power-on.
    // Will be overwritten by mem_ctrl via UART at runtime.
    initial begin
        //instrMemory[0]  = 16'b1100001000000111; /*LOADC R2,7*/
        //instrMemory[1]  = 16'b1100001100000011; /*LOADC R3,3*/
        //instrMemory[2]  = 16'b1100010000000000; /*LOADC R4,0*/
        //instrMemory[3]  = 16'b0000000000000000; /*NOP*/
        //instrMemory[4]  = 16'b0000000000000000; /*NOP*/
        //instrMemory[5]  = 16'b0000001010010011; /*ADD R2,R2,R3*/
        //instrMemory[6]  = 16'b0000000000000000; /*NOP*/
        //instrMemory[7]  = 16'b0000000000000000; /*NOP*/
        //instrMemory[8]  = 16'b0000000000000000; /*NOP*/
        //instrMemory[9]  = 16'b0000000000000000; /*NOP*/
        //instrMemory[10] = 16'b0000000000000000; /*NOP*/
        //instrMemory[11] = 16'b1010010000000010; /*STORE R4,R2*/
        //instrMemory[12] = 16'b0000000000000000; /*NOP*/
        //instrMemory[13] = 16'b0000000000000000; /*NOP*/
        //instrMemory[14] = 16'b0000000000000000; /*NOP*/
        //instrMemory[15] = 16'b0000000000000000; /*NOP*/
        //instrMemory[16] = 16'b0000000000000000; /*NOP*/
        //instrMemory[17] = 16'b1000010000000101; /*LOAD R4,R5*/
        //instrMemory[18] = 16'b0000000000000000; /*NOP*/
        //instrMemory[19] = 16'b0000000000000000; /*NOP*/
        //instrMemory[20] = 16'b0000000000000000; /*NOP*/
        //instrMemory[21] = 16'b0000000000000000; /*NOP*/
        //instrMemory[22] = 16'b1111000000000100; /*JMP R4*/
        //instrMemory[23] = 16'b0000000000000000; /*NOP*/
        //instrMemory[24] = 16'b0000000000000000; /*NOP*/
        //instrMemory[25] = 16'b0000000000000000; /*NOP*/
    end

    // Port A: synchronous write (mem_ctrl programs instructions)
    always @(posedge clk) begin
        if (wr_en)
            instrMemory[wr_addr] <= wr_data;
    end

    // Port B: asynchronous read (CPU fetch stage)
    assign dataOut = instrMemory[addr];

    // Readback: asynchronous read for mem_ctrl CMD_READ
    // Upper 16 bits are tied to 0 because instructions are 16-bit
    // and the controller data bus is 32-bit
    assign rd_data[`INSTR_SIZE-1:0]  = instrMemory[rd_addr];
    assign rd_data[31:`INSTR_SIZE]   = 0;

endmodule