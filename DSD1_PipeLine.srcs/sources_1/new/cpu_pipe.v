`timescale 1ns / 1ps
`include"cpu_macros.vh"

module cpu_pipe(
    input wire clk,
    input wire rst
);

    /*wire to connect all the modules*/
    wire flush;
    wire stall;

    /*fetch*/
    wire [`INSTR_SIZE-1:0] IR;
    wire pc_wr_enable;
    wire [`A_SIZE-1:0] jmpPC;
    wire [`A_SIZE-1:0] PC;    

    /*read*/
    wire [`REG_ADR-1:0] operandAddr1;
    wire [`REG_ADR-1:0] operandAddr2;
    wire [`D_SIZE-1:0] operandValue1;
    wire [`D_SIZE-1:0] operandValue2;
    
    
    /*execute and read stage*/
    wire [`D_SIZE-1:0]RRop1;
    wire [`D_SIZE-1:0]RRop2;
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
    wire loadMem;
    wire loadEnable;
    
    /*write back and executes outputs*/
    wire [`REG_ADR-1:0] wb_regAddr;
    wire [`D_SIZE-1:0] wb_regValue;
    

    fetch_stage FETCH (
        .clk(clk),
        .rst(rst),
        .jmpPC(jmpPC),
        .pc_wr_enable(pc_wr_enable),
        .flush(flush),
        .stall(stall),
        .PC(PC),
        .IR(IR)
    );


    read_stage READ (
        .rst(rst),
        .clk(clk),
        .flush(flush),
        .stall(stall),
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
    
    /*add jump pc instruction*/
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
        .loadMem(loadMem),/*sequential to the wb*/
        .loadEnable(loadEnable),
        //memory output signals
        .addrMem(addrMem),
        .dataMem(dataInMem),
        //jmp signals to the fetch
        .jmpPC(jmpPC),
        .flush(flush),/*sent from execute stage to fetch and read*/
        .stall(stall),/*sent from execute stage to fetch and read*/
        .pc_wr_enable(pc_wr_enable)
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
    
    
    write_back_stage WRITEBACK (
       /*data from data memory*/
       .loadMem(loadMem),
       .loadEnable(loadEnable),
       .dataInMem(dataOutMem),
       /*data from pipeline reg*/
       .dataIn(dataOut),
       .dataDest(dataDest),
       /*registers*/
       .regAddress(wb_regAddr),
       .regValue(wb_regValue) 
    );
    
    


endmodule
