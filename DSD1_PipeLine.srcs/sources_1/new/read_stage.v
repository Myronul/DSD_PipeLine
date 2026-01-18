/* The read stage will decode the instruction, to see the operations type
* the operands, and the destination. It will firslty read the values from the registers,
* and will pass to the execute pipe the values read and the destination to write it back 
* the value
*/

`timescale 1ns / 1ps
`include "cpu_macros.vh"

module read_stage(
    input rst,
    input clk,
    /*IW registers*/
    input [31:0] q0, /*list of instructions*/
    input [31:0] q1,
    input [31:0] q2,
    input [31:0] q3,
    /*Data fowarindg from EX unit RAW hazard*/
    input [`REG_ADR-1:0] src, 
    input [`D_SIZE-1:0] res,  
    input readyForward,
    /*control signals*/
    input flush, /*flush signal from execute jmp instr*/
    input stall, /*stall sgn for load*/
    output reg [`REG_ADR-1:0] operandAddr1, /*send registers address*/
    input [`D_SIZE-1:0] operandValue1,
    output reg [`REG_ADR-1:0] operandAddr2, /*send registers address*/
    input [`D_SIZE-1:0] operandValue2,    
    /*pipeline outputs registers*/
    output reg [`D_SIZE-1:0]RRop1, /*Read register that will contain: OP1 | OP2 | DEST */
    output reg [`D_SIZE-1:0]RRop2,
    output reg [`REG_ADR-1:0]RRdest,
    output reg [`OPCODE_SIZE-1:0]RRopcode, /*the opcode of the instrction*/
    output reg [7:0] wbIndexOut /*signal to IW end instruction*/
);

reg [`INSTR_SIZE-1:0]IR;
reg [2:0]index; /*found minimum*/
reg [7:0]indexq; /*store index qeue and send to next pipe*/


always@(*) begin
    /*take first instruction ready
    and avaliable, if there are not send NOP*/
    IR = 0;
    index = 3; /*found minimum*/
    indexq = 0;
    operandAddr1 = 0;
    operandAddr2 = 0;
    
    if((index >= q0[19:18]) && (q0[0] == 1'b1) && (q0[17] == 1)) begin
        index = q0[19:18]; /*update mmin*/
        indexq = 0; /*update index*/
        IR = q0[16:1]; /*set current valid IR*/
    end
    else if(index >= q1[19:18] && (q1[0] == 1'b1) && (q1[17] == 1)) begin
        index = q1[19:18];
        indexq = 1;
        IR = q1[16:1];
    end
    else if(index >= q2[19:18] && (q2[0] == 1'b1) && (q2[17] == 1)) begin
        index = q2[19:18];
        indexq = 2;
        IR = q2[16:1];
    end
    else if(index >= q3[19:18] && (q3[0] == 1'b1) && (q3[17] == 1)) begin
        index = q3[19:18];
        indexq = 3;
        IR = q3[16:1];
    end
    else begin
         IR = 0; /*send NOP*/
         indexq = 4; /*ignore clear IW qeue*/
         end
    /*now check for src2 and src2 operands if there is RAW hazard
    within the CPU until next rising edge to keep the state on always posedge*/
    
    
    /*combinational decoder for the instruction from the IR*/
    case (IR[`FIELD_OPCODE_7])
        `AND, `ADD, `ADDF, `SUB, `SUBF,
        `OR, `XOR, `NAND, `NOR, `NXOR: begin
            operandAddr1 = IR[5:3];
            operandAddr2 = IR[2:0];
        end
        `SHIFTR, `SHIFTRA, `SHIFTL: begin
            operandAddr1 = IR[8:6];
        end
        default: begin
        
        case (IR[`FIELD_OPCODE_5])
            `LOAD, `STORE: begin
             operandAddr1 = IR[2:0];
             operandAddr2 = IR[10:8];
             end
         default: begin
         
         case (IR[`FIELD_OPCODE_4])
             `JMP: begin
              operandAddr1 = IR[2:0];
              end
              `JMPcond: begin
               operandAddr1 = IR[8:6];
               operandAddr2 = IR[2:0];
               end
              `JMPRcond: begin
               operandAddr1 = IR[8:6];
               end
               default: begin
               operandAddr1 = 0;
               operandAddr2 = 0;
               end
          endcase
        end
      endcase
     end
   endcase
end   


  
always@(posedge clk or posedge rst) begin
    if(rst)begin
        RRop1 <= 0;
        RRop2 <= 0;
        RRdest <= 0;
        RRopcode <=0;
    end else if(flush) begin
        RRop1 <= 0;
        RRop2 <= 0;
        RRdest <= 0;
        RRopcode <= 0;        
    end else if(stall) begin
        RRop1 <= RRop1;
        RRop2 <= RRop2;
        RRdest <= RRdest;
        RRopcode <= RRopcode;
    end else begin
    wbIndexOut <= indexq; /*send index instruction*/
    case(IR[`FIELD_OPCODE_7])
        `NOP: begin
              RRopcode <= IR[`FIELD_OPCODE_7];/*do nothing*/
              RRop1 <= 0;
              RRop2 <= 0;
              RRdest <= 0;
              end
        `AND: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end              
                RRdest <= IR[8:6]; /*destination*/
                RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `ADD: begin
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6];
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `ADDF: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `SUB: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end  
        `SUBF: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `OR: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `XOR: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `NAND: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end 
        `NOR: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `NXOR: begin 
              if(operandAddr1 == src) begin
                /*RAW*/
                RRop1 <= res; /*save val for next stage*/
                RRop2 <= operandValue2;
                end
              else if(operandAddr2 == src) begin
                /*RAW*/
                RRop2 <= res; /*save val for next stage*/
                RRop1 <= operandValue1;
                end
              else begin
                RRop1 <= operandValue1; /*save val for next stage*/
                RRop2 <= operandValue2;                
              end 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `SHIFTR: begin
              RRop1 <= operandValue1; /*reg value*/
              RRop2 <= IR[5:0];/*immediate value*/ 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `SHIFTRA: begin 
              RRop1 <= IR[5:0];/*immediate value*/ 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end 
        `SHIFTL: begin 
              RRop1 <= IR[5:0];/*immediate value*/ 
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end 
         default: begin      
         
         case(IR[`FIELD_OPCODE_5])
             `LOAD: begin
                   RRop1 <= operandValue1; /*memory address*/
                   RRdest <= IR[10:8]; /*register address*/
                   RRopcode <= IR[`FIELD_OPCODE_5];
                   end
             `LOADC: begin
                   RRop1 <= IR[7:0];/*immediat value*/
                   RRop2 <= 0;
                   RRdest <= IR[10:8];
                   RRopcode <= IR[`FIELD_OPCODE_5];
                   end      
             `STORE: begin
                   RRop1 <= operandValue1; /*value*/
                   RRop2 <= operandValue2; /*address*/
                   RRdest <= IR[10:8];
                   RRopcode <= IR[`FIELD_OPCODE_5];
                   end
           default: begin             
    
           case(IR[`FIELD_OPCODE_4])
               `JMP: begin
                     RRop1 <= operandValue1[`A_SIZE-1:0];
                     RRopcode <= IR[`FIELD_OPCODE_4];
                     end
               `JMPR: begin
                     RRop1 <= IR[5:0]; /*immediat value*/
                     RRopcode <= IR[`FIELD_OPCODE_4];
                     end
               `JMPcond: begin
                     RRop1 <= operandValue1;
                     RRop2 <= operandValue2;
                     RRopcode <= IR[`FIELD_OPCODE_7]; /*! give opcode + condition*/
                     end
               `JMPRcond: begin
                     RRop1 <= operandValue1;
                     RRop2 <= IR[5:0]; /*immediate value*/
                     RRopcode <= IR[`FIELD_OPCODE_7]; /*! give opcode + condition*/
                     end
                endcase
               end
             endcase
           end
       endcase
    end
end    



endmodule












