/* The read stage will decode the instruction, to see the operations type
* the operands, and the destination. It will firstly read the values from the registers,
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
    /*Data forwarding from EX unit RAW hazard*/
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
    output reg [`D_SIZE-1:0]RRop1,
    output reg [`D_SIZE-1:0]RRop2,
    output reg [`REG_ADR-1:0]RRdest,
    output reg [`OPCODE_SIZE-1:0]RRopcode,
    output reg [7:0] wbIndexOut, /*signal to IW end instruction*/
    output reg [7:0] readIndexOut /*signal to IW that instruction is being dispatched*/
);

reg [`INSTR_SIZE-1:0]IR;
reg [1:0]index_min;
reg [7:0]indexq;
reg [1:0] age_min;

always@(*) begin
    /*take first instruction ready and available with minimum age*/
    IR = 16'h0000;
    index_min = 2'b00;
    indexq = 8'd4; /*default: no valid instruction*/
    age_min = 2'b11; /*start with maximum age*/
    operandAddr1 = 3'b000;
    operandAddr2 = 3'b000;
    
    /*find instruction with minimum age that is valid and ready*/
    /*check q0*/
    if((q0[0] == 1'b1) && (q0[17] == 1'b1)) begin
        if(q0[19:18] <= age_min) begin
            age_min = q0[19:18];
            index_min = 2'b00;
            indexq = 8'd0;
            IR = q0[16:1];
        end
    end
    
    /*check q1*/
    if((q1[0] == 1'b1) && (q1[17] == 1'b1)) begin
        if(q1[19:18] < age_min) begin  /*strictly less to keep first found*/
            age_min = q1[19:18];
            index_min = 2'b01;
            indexq = 8'd1;
            IR = q1[16:1];
        end
    end
    
    /*check q2*/
    if((q2[0] == 1'b1) && (q2[17] == 1'b1)) begin
        if(q2[19:18] < age_min) begin
            age_min = q2[19:18];
            index_min = 2'b10;
            indexq = 8'd2;
            IR = q2[16:1];
        end
    end
    
    /*check q3*/
    if((q3[0] == 1'b1) && (q3[17] == 1'b1)) begin
        if(q3[19:18] < age_min) begin
            age_min = q3[19:18];
            index_min = 2'b11;
            indexq = 8'd3;
            IR = q3[16:1];
        end
    end
    
    /*if no valid instruction found, indexq remains 4 and IR remains NOP*/
    
    /*combinational decoder for the instruction from the IR*/
    case (IR[`FIELD_OPCODE_7])
        `AND, `ADD, `ADDF, `SUB, `SUBF,
        `OR, `XOR, `NAND, `NOR, `NXOR: begin
            operandAddr1 = IR[5:3];
            operandAddr2 = IR[2:0];
        end
        `SHIFTR, `SHIFTRA, `SHIFTL: begin
            operandAddr1 = IR[8:6];
            operandAddr2 = 3'b000;
        end
        default: begin
            case (IR[`FIELD_OPCODE_5])
                `LOAD: begin
                    operandAddr1 = IR[2:0];
                    operandAddr2 = 3'b000;
                end
                `LOADC: begin
                    operandAddr1 = 3'b000;
                    operandAddr2 = 3'b000;
                end
                `STORE: begin
                    operandAddr1 = IR[2:0];
                    operandAddr2 = IR[10:8];
                end
                default: begin
                    case (IR[`FIELD_OPCODE_4])
                        `JMP: begin
                            operandAddr1 = IR[2:0];
                            operandAddr2 = 3'b000;
                        end
                        `JMPR: begin
                            operandAddr1 = 3'b000;
                            operandAddr2 = 3'b000;
                        end
                        `JMPcond: begin
                            operandAddr1 = IR[8:6];
                            operandAddr2 = IR[2:0];
                        end
                        `JMPRcond: begin
                            operandAddr1 = IR[8:6];
                            operandAddr2 = 3'b000;
                        end
                        default: begin
                            operandAddr1 = 3'b000;
                            operandAddr2 = 3'b000;
                        end
                    endcase
                end
            endcase
        end
    endcase
end

always@(posedge clk or posedge rst) begin
    if(rst) begin
        RRop1 <= 0;
        RRop2 <= 0;
        RRdest <= 0;
        RRopcode <= 0;
        wbIndexOut <= 8'd4;
        readIndexOut <= 8'd4;
    end else if(flush) begin
        RRop1 <= 0;
        RRop2 <= 0;
        RRdest <= 0;
        RRopcode <= 0;
        wbIndexOut <= 8'd4;
        readIndexOut <= 8'd4;
    end else if(stall) begin
        RRop1 <= RRop1;
        RRop2 <= RRop2;
        RRdest <= RRdest;
        RRopcode <= RRopcode;
        wbIndexOut <= wbIndexOut;
        readIndexOut <= 8'd4; /*don't signal dispatch during stall*/
    end else begin
        wbIndexOut <= indexq; /*send index instruction*/
        readIndexOut <= indexq; /*NEW: signal to IW which instruction is being dispatched*/
        
        case(IR[`FIELD_OPCODE_7])
            `NOP: begin
                RRopcode <= IR[`FIELD_OPCODE_7];
                RRop1 <= 0;
                RRop2 <= 0;
                RRdest <= 0;
            end
            `AND, `ADD, `ADDF, `SUB, `SUBF, `OR, `XOR, `NAND, `NOR, `NXOR: begin 
                if(operandAddr1 == src && readyForward) begin
                    RRop1 <= res;
                    RRop2 <= operandValue2;
                end
                else if(operandAddr2 == src && readyForward) begin
                    RRop2 <= res;
                    RRop1 <= operandValue1;
                end
                else begin
                    RRop1 <= operandValue1;
                    RRop2 <= operandValue2;                
                end              
                RRdest <= IR[8:6];
                RRopcode <= IR[`FIELD_OPCODE_7];
            end
            `SHIFTR, `SHIFTRA, `SHIFTL: begin
                if(operandAddr1 == src && readyForward) begin
                    RRop1 <= res;
                end
                else begin
                    RRop1 <= operandValue1;
                end
                RRop2 <= {10'b0, IR[5:0]};  /*immediate value*/
                RRdest <= IR[8:6];
                RRopcode <= IR[`FIELD_OPCODE_7];
            end
            
            default: begin      
                case(IR[`FIELD_OPCODE_5])
                    `LOAD: begin
                        if(operandAddr1 == src && readyForward) begin
                            RRop1 <= res;
                        end
                        else begin
                            RRop1 <= operandValue1;
                        end
                        RRop2 <= 0;
                        RRdest <= IR[10:8];
                        RRopcode <= IR[`FIELD_OPCODE_5];
                    end
                    `LOADC: begin
                        RRop1 <= {8'b0, IR[7:0]};  /*immediate value*/
                        RRop2 <= 0;
                        RRdest <= IR[10:8];
                        RRopcode <= IR[`FIELD_OPCODE_5];
                    end      
                    `STORE: begin
                        if(operandAddr1 == src && readyForward) begin
                            RRop1 <= res;
                            RRop2 <= operandValue2;
                        end
                        else if(operandAddr2 == src && readyForward) begin
                            RRop1 <= operandValue1;
                            RRop2 <= res;
                        end
                        else begin
                            RRop1 <= operandValue1;
                            RRop2 <= operandValue2;
                        end
                        RRdest <= IR[10:8];
                        RRopcode <= IR[`FIELD_OPCODE_5];
                    end
                    default: begin             
                        case(IR[`FIELD_OPCODE_4])
                            `JMP: begin
                                if(operandAddr1 == src && readyForward) begin
                                    RRop1 <= res[`A_SIZE-1:0];
                                end
                                else begin
                                    RRop1 <= operandValue1[`A_SIZE-1:0];
                                end
                                RRop2 <= 0;
                                RRdest <= 0;
                                RRopcode <= IR[`FIELD_OPCODE_4];
                            end
                            `JMPR: begin
                                RRop1 <= {10'b0, IR[5:0]};  /*immediate value*/
                                RRop2 <= 0;
                                RRdest <= 0;
                                RRopcode <= IR[`FIELD_OPCODE_4];
                            end
                            `JMPcond: begin
                                if(operandAddr1 == src && readyForward) begin
                                    RRop1 <= res;
                                    RRop2 <= operandValue2;
                                end
                                else if(operandAddr2 == src && readyForward) begin
                                    RRop1 <= operandValue1;
                                    RRop2 <= res;
                                end
                                else begin
                                    RRop1 <= operandValue1;
                                    RRop2 <= operandValue2;
                                end
                                RRdest <= 0;
                                RRopcode <= IR[`FIELD_OPCODE_7]; /*give opcode + condition*/
                            end
                            `JMPRcond: begin
                                if(operandAddr1 == src && readyForward) begin
                                    RRop1 <= res;
                                end
                                else begin
                                    RRop1 <= operandValue1;
                                end
                                RRop2 <= {10'b0, IR[5:0]};  /*immediate value*/
                                RRdest <= 0;
                                RRopcode <= IR[`FIELD_OPCODE_7]; /*give opcode + condition*/
                            end
                            default: begin
                                RRop1 <= 0;
                                RRop2 <= 0;
                                RRdest <= 0;
                                RRopcode <= 0;
                            end
                        endcase
                    end
                endcase
            end
        endcase
    end
end    

endmodule