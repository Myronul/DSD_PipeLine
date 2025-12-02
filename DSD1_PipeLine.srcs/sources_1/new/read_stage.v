/* The read stage will decode the instruction, to see the operations type
* the operands, and the destination. It will firslty read the values from the registers,
* and will pass to the execute pipe the values read and the destination to write it back 
* the value
*/

`timescale 1ns / 1ps
`include "cpu_macros.vh"

module read_stage(
    input clk,
    input [`INSTR_SIZE-1:0]IR,
    output [`REG_ADR-1:0] operandAddr1, /*send registers address*/
    input [`D_SIZE-1:0] operandValue1,
    output [`REG_ADR-1:0] operandAddr2, /*send registers address*/
    input [`D_SIZE-1:0] operandValue2,    
    /*pipeline outputs registers*/
    output reg [`REG_ADR-1:0]RRop1, /*Read register that will contain: OP1 | OP2 | DEST */
    output reg [`REG_ADR-1:0]RRop2,
    output reg [`REG_ADR-1:0]RRdest,
    output reg [`OPCODE_SIZE-1:0]RRopcode /*the opcode of the instrction*/
);

/*we will use the clock and IR register*/

reg [`INSTR_SIZE-1:0]IRreg;

/*combinational*/
assign operandAddr1 = IR[5:3];
assign operandAddr2 = IR[2:0];
  
always@(posedge clk) begin
    case(IR[`FIELD_OPCODE_7])
        `NOP: /*do nothing*/;
        `AND: begin 
              RRop1 <= operandValue1; /*save val for next stage*/
              RRop2 <= operandValue2;
              RRdest <= IR[8:6]; /*destination*/
              RRopcode = IR[`FIELD_OPCODE_7];
              end
    endcase

end    

endmodule
