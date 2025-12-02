`timescale 1ns / 1ps
`include"cpu_macros.vh"
module cpu_pipe(
    input wire clk,
    input wire rst
);

    /*wire to connect all the modules*/

    /*fetch*/
    wire [`INSTR_SIZE-1:0] IR;
    wire pc_wr_enable = 0;
    wire [`A_SIZE-1:0] jmpPC = 0;
    wire [`A_SIZE-1:0] PC;    

    /*read*/
    wire [`REG_ADR-1:0] operandAddr1;
    wire [`REG_ADR-1:0] operandAddr2;
    wire [`D_SIZE-1:0] operandValue1;
    wire [`D_SIZE-1:0] operandValue2;
    
    
    /*execute and read stage*/
    wire [`REG_ADR-1:0]RRop1;
    wire [`REG_ADR-1:0]RRop2;
    wire [`REG_ADR-1:0]RRdest;
    wire [`OPCODE_SIZE-1:0]RRopcode;
    wire [`D_SIZE-1:0]dataOut;
    wire [`REG_ADR-1:0]dataDest;
    //datamemory signals
    wire [`A_SIZE-1:0]addrMem;
    wire [`D_SIZE-1:0] dataInMem;
    wire [`D_SIZE-1:0]dataOutMem;
    wire memWr;
    wire memRd;
    
    /*write back and executes*/
    wire [`D_SIZE-1:0]dataInput; /*dataOutput from execute stage*/
    wire [`REG_ADR-1:0] wb_regAddr = 0;
    wire [`D_SIZE-1:0] wb_regValue = 0;
    

    fetch_stage FETCH (
        .clk(clk),
        .rst(rst),
        .jmpPC(jmpPC),
        .pc_wr_enable(pc_wr_enable),
        .PC(PC),
        .IR(IR)
    );


    read_stage READ (
        .clk(clk),
        .IR(IR),//pipeline input
        .operandAddr1(operandAddr1),
        .operandValue1(operandValue1),
        .operandAddr2(operandAddr2),
        .operandValue2(operandValue2),
        // pipeline outputs
        .RRop1(RRop1),
        .RRop2(RRop2),
        .RRdest(RRdest),
        .RRopcode(RRopcode)
    );


    cpu_registers REGFILE (
        .clk(clk),
        // read
        .operandValue1(operandValue1),
        .operandAddr1(operandAddr1),
        .operandValue2(operandValue2),
        .operandAddr2(operandAddr2),
        // write-back
        .regAddress(wb_regAddr),
        .regValue(wb_regValue)
    );
    
    
    execute_stage EXECUTE (
        .clk(clk),
        //memory connections
        .memWr(memWr),
        .memRd(memRd),
        //pipeline inputs from read
        .RRop1(RRop1),
        .RRop2(RRop2),
        .RRdest(RRdest),
        .RRopcode(RRopcode),
        //pipeline output
        .dataOut(dataOut),
        .dataDest(dataDest),
        //memory output signals
        .addrMem(addrMem),
        .dataOutMem(dataOutMem)
    );
    
    
    data_memory DATAMEM (
        /*data memory connected to the Wb and Execute states*/
        .clk(clk),
        .memRd(memRd),
        .memWr(memWr),
        .dataMemAddr(addrMem),
        .dataMemDatain(dataInMem),
        .dataMemDataout(dataOutMem)
    );
    
    


endmodule
