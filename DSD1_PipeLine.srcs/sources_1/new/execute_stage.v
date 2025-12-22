`timescale 1ns / 1ps

module execute_stage(
    input clk,
    output reg memRd,
    output memWr,
    output reg loadMem,
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
    output [`D_SIZE-1:0]dataOutMem,
    /*signals for the jmp instruction to the fetch stage*/
    output [`A_SIZE-1:0] jmpPC,
    output pc_wr_enable, 
    output reg flush /*send signal to flush fetch and read pipe*/
);

reg [`D_SIZE-1:0]RegResult;
reg [1:0]state;

initial begin
loadMem = 0;
flush = 0;
end


/*define ALU combinational*/
/*when RRop1 or RRop2 or RRopcode changes*/
always@(*)begin
    case(RRopcode[`OPCODE_SIZE-1:0])
        `NOP: RegResult = 0; /*do nothing*/
        `AND: begin
              RegResult = RRop1 & RRop2;
              end
         `ADD: begin
               RegResult = RRop1 + RRop2;
               end
         `ADD: begin
               RegResult = RRop1 + RRop2;
               end
         `ADDF: begin
               RegResult = RRop1 + RRop2;
               end     
         `SUB: begin
               RegResult = RRop1 - RRop2;
               end              
         `SUBF: begin
               RegResult = RRop1 - RRop2;
               end
         `OR: begin
               RegResult = RRop1 | RRop2;
               end
         `XOR: begin
               RegResult = RRop1 ^ RRop2;
               end
         `NAND: begin
               RegResult = ~(RRop1 & RRop2);
               end
         `NOR: begin
               RegResult = ~(RRop1 | RRop2);
               end
         `NXOR: begin
               RegResult = ~(RRop1 ^ RRop2);
               end 
         `SHIFTR: begin
               RegResult = RRop1 >> RRop2;
               end     
         `SHIFTRA: begin
               RegResult = RRop1 >> RRop2;
               end 
         `SHIFTL: begin
               RegResult = RRop1 << RRop2;
               end
          default: begin case(RRopcode[4:0])
                   `LOAD: begin
                   /*stall fetch and read*/
                   memRd = 1;
                   addrMem = RRop1[`A_SIZE-1:0];
                   end  
                   `LOADC: begin
                   RegResult = RRop1;
                   end 
        endcase
      end                                    
    endcase
    
end


always@(posedge clk) begin
    /*add fsm for memRd and stall logic*/
    dataOut <= RegResult;
    dataDest <= RRdest;
end


endmodule
