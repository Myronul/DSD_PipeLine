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
    input flush, /*flush signal from execute jmp instr*/
    input stall, /*stall sgn for load*/
    input [`INSTR_SIZE-1:0]IR,
    output reg [`REG_ADR-1:0] operandAddr1, /*send registers address*/
    input [`D_SIZE-1:0] operandValue1,
    output reg [`REG_ADR-1:0] operandAddr2, /*send registers address*/
    input [`D_SIZE-1:0] operandValue2,    
    /*pipeline outputs registers*/
    output reg [`D_SIZE-1:0]RRop1, /*Read register that will contain: OP1 | OP2 | DEST */
    output reg [`D_SIZE-1:0]RRop2,
    output reg [`REG_ADR-1:0]RRdest,
    output reg [`OPCODE_SIZE-1:0]RRopcode /*the opcode of the instrction*/
);


always@(*) begin
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
    case(IR[`FIELD_OPCODE_7])
        `NOP: begin
              RRopcode <= IR[`FIELD_OPCODE_7];/*do nothing*/
              RRop1 <= 0;
              RRop2 <= 0;
              RRdest <= 0;
              end
        `AND: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `ADD: begin
              RRop1 <= operandValue1;
              RRop2 <= operandValue2;
              RRdest <= IR[8:6];
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `ADDF: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `SUB: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end  
        `SUBF: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `OR: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `XOR: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `NAND: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end 
        `NOR: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode <= IR[`FIELD_OPCODE_7];
              end
        `NXOR: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
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
                   RRop1 <= operandValue1; /*address*/
                   RRdest <= IR[10:8];
                   RRopcode <= IR[`FIELD_OPCODE_5];
                   end
           default: begin             
    
           case(IR[`FIELD_OPCODE_4])
               `JMP: begin
                     RRop1 <= operandValue1;
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












