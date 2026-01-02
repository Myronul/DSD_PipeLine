`timescale 1ns / 1ps
`include "cpu_macros.vh"

module execute_stage(
    input clk,
    output reg stall,
    output reg memRd, /*to memory*/
    output reg memWr, 
    output reg loadMem, /*to wb*/
    output reg loadEnable, /*to wb*/
    /*signals from the read stage to the execute*/
    input [`D_SIZE-1:0]RRop1, /*Read register that will contain: OP1 | OP2 | DEST */
    input [`D_SIZE-1:0]RRop2,
    input [`REG_ADR-1:0]RRdest,
    input [`OPCODE_SIZE-1:0]RRopcode, /*the opcode of the instrction*/
    /*output data to the write back stage*/
    output reg [`D_SIZE-1:0]dataOut,
    output reg [`REG_ADR-1:0]dataDest,
    /*signals for the memory data*/
    output reg [`A_SIZE-1:0]addrMem, /*obs! vezi sa fie activare semnalelor secventiala ca in memorie se scrie pe ceas!*/
    output reg [`D_SIZE-1:0]dataMem, /*data to write to the memory*/
    //input [`D_SIZE-1:0]dataOutMem, /*de schimbat! inputul e luat de write back si dus catre registre!*/
    /*signals for the jmp instruction to the fetch stage*/
    output reg [`A_SIZE-1:0] jmpPC,
    output reg pc_wr_enable, 
    output reg flush /*send signal to flush fetch and read pipe*/
);

reg [`D_SIZE-1:0]RegResult;
reg [1:0]stateRead;
reg flag;

initial begin
loadMem = 0;
flush = 0;
stall = 0;
end


/*define ALU combinational*/
/*when RRop1 or RRop2 or RRopcode changes*/
always@(*)begin
    case(RRopcode[`OPCODE_SIZE-1:0])
        `NOP: begin 
              RegResult = 0; /*do nothing*/
              flag = 1;
              jmpPC = 0;
              pc_wr_enable = 0;
              flush = 0;
              end 
        `AND: begin
              RegResult = RRop1 & RRop2;
              flag = 0;
              jmpPC = 0;
              pc_wr_enable = 0;
              flush = 0;
              end
         `ADD: begin
               RegResult = RRop1 + RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end
         `ADDF: begin
               RegResult = RRop1 + RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;
               end     
         `SUB: begin
               RegResult = RRop1 - RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end              
         `SUBF: begin
               RegResult = RRop1 - RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end
         `OR: begin
               RegResult = RRop1 | RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end
         `XOR: begin
               RegResult = RRop1 ^ RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end
         `NAND: begin
               RegResult = ~(RRop1 & RRop2);
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end
         `NOR: begin
               RegResult = ~(RRop1 | RRop2);
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end
         `NXOR: begin
               RegResult = ~(RRop1 ^ RRop2);
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end 
         `SHIFTR: begin
               RegResult = RRop1 >> RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;               
               end     
         `SHIFTRA: begin
               RegResult = RRop1 >> RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;
               end 
         `SHIFTL: begin
               RegResult = RRop1 << RRop2;
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;
               end
         `LOADC: begin
               RegResult = RRop1;  
               flag = 0;
               jmpPC = 0;
               pc_wr_enable = 0;
               flush = 0;
               end
          `JMP: begin
                RegResult = 0;
                flag = 1; /*NOP*/
                jmpPC = RRop1[`A_SIZE-1:0];
                pc_wr_enable = 1;
                flush = 1;
                end
          `LOAD: begin
                RegResult = 0;
                flag = 1;
                jmpPC = 0;
                pc_wr_enable = 0;
                flush = 0;
                end
          `STORE: begin
                RegResult = 0;
                flag = 1;
                jmpPC = 0;
                pc_wr_enable = 0;
                flush = 0;
                end
          default: begin
                RegResult = 0;
                flag = 1;
                jmpPC = 0;
                pc_wr_enable = 0;
                flush = 0;
                end                                     
    endcase
    
end


always@(posedge clk) begin
    /*add fsm for memRd and stall logic*/
    if(stateRead!=0) begin
        case(stateRead)
            1: begin    
            stateRead <= 2;
            end
            
            2: begin
            loadMem <= 1; /*signal to wb*/
            loadEnable <= 0;
            dataDest <= RRdest;
            memRd <= 0;
            stall <= 0;
            stateRead <= 0;
            end
        endcase
    end    
    
    else if(RRopcode[`OPCODE_SIZE-1:0] == `LOAD) begin
        /*on clock enable read*/
        stall <= 1;
        memRd <= 1;
        memWr <= 0;
        addrMem <= RRop1[`A_SIZE-1:0];
        stateRead <= 1;
    end
    
    else if(RRopcode[`OPCODE_SIZE-1:0] == `STORE)begin
        memWr <= 1;
        memRd <= 0;
        dataOut <= 0;
        dataDest <= 0;
        loadMem <= 0;
        loadEnable <= 0;
        addrMem <= RRop2[`A_SIZE-1:0];
        dataMem <= RRop1;        
    end
    
    else begin
        /*normal case for no laod no store*/
        if(!flag) begin
        loadEnable <= 1; /*load value in registers, add JMP case!*/
        loadMem <= 0;
        memWr <= 0;
        memRd <= 0;
        dataOut <= RegResult;
        dataDest <= RRdest;
        end
        
        else begin
        loadEnable <= 0; /*load value in registers, add JMP case!*/
        loadMem <= 0;
        memWr <= 0;
        memRd <= 0;
        dataOut <= 0;
        dataDest <= 0;        
        end
    end
end


endmodule