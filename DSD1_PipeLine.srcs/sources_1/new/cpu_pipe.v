`timescale 1ns / 1ps
`include"cpu_macros.vh"

module cpu_pipe(
    input wire clk,
    input wire rst
);
    /*wire to connect all the modules*/
    wire flush;
    wire stall;
    wire stallFetch;
    
    /*NEW: semnal de confirmare ca branch-ul a fost procesat in EX*/
    wire branch_processed; 

    /*fetch*/
    wire [`INSTR_SIZE-1:0] IR;
    wire pc_wr_enable;
    wire [`A_SIZE-1:0] jmpPC;
    wire [`A_SIZE-1:0] PC;
    
    /*IW*/
    wire [31:0] q0;
    wire [31:0] q1;
    wire [31:0] q2;
    wire [31:0] q3;
    
    /*index to clear IW instruction*/
    wire [7:0] wbIndex0;
    wire [7:0] wbIndex1;
    wire [7:0] wbIndex2;
    wire [7:0] readIndex;

    /*read*/
    wire [`REG_ADR-1:0] operandAddr1;
    wire [`REG_ADR-1:0] operandAddr2;
    wire [`D_SIZE-1:0] operandValue1;
    wire [`D_SIZE-1:0] operandValue2;
    
    /*data forwarding*/
    wire [`REG_ADR-1:0] src;
    wire [`D_SIZE-1:0] res;
    wire readyForward;
    
    /*execute and read stage*/
    wire [`D_SIZE-1:0]RRop1;
    wire [`D_SIZE-1:0]RRop2;
    wire [`REG_ADR-1:0]RRdest;
    wire [`OPCODE_SIZE-1:0]RRopcode;
    wire [`D_SIZE-1:0]dataOut;
    wire [`REG_ADR-1:0]dataDest;
    
    /*datamemory signals*/
    wire [`A_SIZE-1:0]addrMem;
    wire [`D_SIZE-1:0] dataInMem;
    wire [`D_SIZE-1:0]dataOutMem;
    wire memWr;
    wire memRd;
    wire loadMem;
    wire loadEnable;
    wire enableWb; /*enable wb on regfile*/
    
    /*write back and executes outputs*/
    wire [`REG_ADR-1:0] wb_regAddr;
    wire [`D_SIZE-1:0] wb_regValue;
    

    fetch_stage FETCH (
        .clk(clk),
        .rst(rst),
        .jmpPC(jmpPC),
        .pc_wr_enable(pc_wr_enable),
        .flush(flush),
        .stall(stallFetch),
        .PC(PC),
        .IR(IR)
    );

    IW IW (
        .clk(clk),
        .rst(rst),
        .flush(flush), /*NEW: flush curata coada si stall-ul*/
        .branch_processed_ex(branch_processed), /*NEW: confirmare de la EX*/
        .IR(IR),
        .q0w(q0),
        .q1w(q1),
        .q2w(q2),
        .q3w(q3),
        .stall(stallFetch),
        .pc_wr_enable(pc_wr_enable),
        .wbIndex(wbIndex2),
        .readIndex(readIndex) 
    );


    read_stage READ (
        .rst(rst),
        .clk(clk),
        .flush(flush),
        .stall(stall),
        /*IW registers pipe*/
        .q0(q0),
        .q1(q1),
        .q2(q2),
        .q3(q3),
        /*regfile*/
        .operandAddr1(operandAddr1),
        .operandValue1(operandValue1),
        .operandAddr2(operandAddr2),
        .operandValue2(operandValue2),
        /*pipeline outputs*/
        .RRop1(RRop1),
        .RRop2(RRop2),
        .RRdest(RRdest),
        .RRopcode(RRopcode),
        .wbIndexOut(wbIndex0),
        .readIndexOut(readIndex), 
        /*data forwarding*/
        .src(src),
        .res(res),
        .readyForward(readyForward)
    );

    cpu_registers REGFILE (
        .clk(clk),
        /*read*/
        .operandValue1(operandValue1),
        .operandAddr1(operandAddr1),
        .operandValue2(operandValue2),
        .operandAddr2(operandAddr2),
        /*write-back*/
        .regAddress(wb_regAddr),
        .regValue(wb_regValue),
        .enableWb(enableWb)
    );

    execute_stage EXECUTE (
        .clk(clk),
        /*memory connections*/
        .memWr(memWr),
        .memRd(memRd),
        /*pipeline inputs from read*/
        .RRop1(RRop1),
        .RRop2(RRop2),
        .RRdest(RRdest),
        .RRopcode(RRopcode),
        .wbIndexIn(wbIndex0),
        /*pipeline output*/
        .wbIndexOut(wbIndex1),
        .dataOut(dataOut),
        .dataDest(dataDest),
        .loadMem(loadMem),
        .loadEnable(loadEnable),
        /*memory output signals*/
        .addrMem(addrMem),
        .dataMem(dataInMem),
        /*jmp signals to the fetch*/
        .jmpPC(jmpPC),
        .flush(flush),
        .stall(stall),
        .pc_wr_enable(pc_wr_enable),
        .branch_done(branch_processed), /*NEW: output signal*/
        /*data forwarding*/
        .src(src),
        .res(res),
        .readyForward(readyForward)
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
       .wbIndexIn(wbIndex1),
       .wbIndexOut(wbIndex2),
       .dataIn(dataOut),
       .dataDest(dataDest),
       /*registers*/
       .regAddress(wb_regAddr),
       .regValue(wb_regValue),
       .enableWb(enableWb) 
    );

endmodule