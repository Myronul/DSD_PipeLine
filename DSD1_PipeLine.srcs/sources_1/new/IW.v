/*
Structure for IW:
Valid bit(1) | INSTR(16) | Readybit(1) | Age(2) | SRC1Valid(1) | SRC2Valid(1)
0 0000000000000000  0   0  0  0  0  | 000...000
0 1.............    16 17 18 19 20 21          31

IMPORTANT: When instruction is stored in queue:
  - qeue[i][16:1] contains IR[15:0]
  - To access IR[8:6] from queue: qeue[i][9:7]
  - To access IR[10:8] from queue: qeue[i][11:9]
  - To access IR[5:3] from queue: qeue[i][6:4]
  - To access IR[2:0] from queue: qeue[i][3:1]
*/

`timescale 1ns / 1ps
`include "cpu_macros.vh"

module IW(
    input clk,
    input rst,
    input flush,                    /*NEW: Input to clear stall on JMP taken*/
    input branch_processed_ex,      /*NEW: Input to clear stall on JMP NOT taken*/
    input wire pc_wr_enable,
    input [`INSTR_SIZE-1:0] IR,
    input [7:0] wbIndex,
    
    input [7:0] readIndex, /*instruction being read THIS cycle*/
    output [31:0] q0w,
    output [31:0] q1w,
    output [31:0] q2w,
    output [31:0] q3w,
    output reg stall
);
    integer i;
    reg [1:0] index;                 
    reg [31:0] qeue[3:0];           
    reg [31:0] q;                    
    reg [2:0] counter;
    
    /*NEW: Internal flag to hold stall state until branch resolves*/
    reg stall_control_active;

    /*decoded fields from current instruction IR*/
    reg [2:0] ir_dest;
    reg [2:0] ir_src1;
    reg [2:0] ir_src2;
    reg ir_has_dest;
    reg ir_writes_reg;
    /*decoded fields from queued instructions*/
    reg [2:0] q_dest[3:0];
    reg [2:0] q_src1[3:0];
    reg [2:0] q_src2[3:0];
    reg q_has_dest[3:0];
    reg q_has_src1[3:0];
    reg q_has_src2[3:0];
    /*outputs with ready bit cleared for instruction being dispatched*/
    reg [31:0] q0_modified;
    reg [31:0] q1_modified;
    reg [31:0] q2_modified;
    reg [31:0] q3_modified;
    
    initial begin
        stall = 0;
        stall_control_active = 0;
        qeue[0] = 0;
        qeue[1] = 0;
        qeue[2] = 0;
        qeue[3] = 0;
    end

    /*decode current instruction IR*/
    always @(*) begin
        ir_dest = 3'b000;
        ir_src1 = 3'b000;
        ir_src2 = 3'b000;
        ir_has_dest = 0;
        ir_writes_reg = 0;
        
        case (IR[`FIELD_OPCODE_7])
            `NOP: begin
                ir_has_dest = 0;
                ir_writes_reg = 0;
            end
            `AND, `ADD, `ADDF, `SUB, `SUBF,
            `OR, `XOR, `NAND, `NOR, `NXOR: begin
                ir_dest = IR[8:6];
                ir_src1 = IR[5:3];
                ir_src2 = IR[2:0];
                ir_has_dest = 1;
                ir_writes_reg = 1;
            end
            `SHIFTR, `SHIFTRA, `SHIFTL: begin
                ir_dest = IR[8:6];
                ir_src1 = IR[8:6];
                ir_has_dest = 1;
                ir_writes_reg = 1;
            end
            default: begin
                case (IR[`FIELD_OPCODE_5])
                    `LOAD: begin
                        ir_dest = IR[10:8];
                        ir_src1 = IR[2:0];
                        ir_has_dest = 1;
                        ir_writes_reg = 1;
                    end
                    `LOADC: begin
                        ir_dest = IR[10:8];
                        ir_has_dest = 1;
                        ir_writes_reg = 1;
                    end
                    `STORE: begin
                        ir_src1 = IR[2:0];
                        ir_src2 = IR[10:8];
                        ir_has_dest = 0;
                        ir_writes_reg = 0;
                    end
                    default: begin
                        case (IR[`FIELD_OPCODE_4])
                            `JMP: begin
                                ir_src1 = IR[2:0];
                                ir_has_dest = 0;
                                ir_writes_reg = 0;
                            end
                            `JMPR: begin
                                ir_has_dest = 0;
                                ir_writes_reg = 0;
                            end
                            `JMPcond: begin
                                ir_src1 = IR[8:6];
                                ir_src2 = IR[2:0];
                                ir_has_dest = 0;
                                ir_writes_reg = 0;
                            end
                            `JMPRcond: begin
                                ir_src1 = IR[8:6];
                                ir_has_dest = 0;
                                ir_writes_reg = 0;
                            end
                            default: begin
                                ir_has_dest = 0;
                                ir_writes_reg = 0;
                            end
                        endcase
                    end
                endcase
            end
        endcase
    end

    /*decode all queued instructions*/
    always @(*) begin
        for(i = 0; i < 4; i = i + 1) begin
            q_dest[i] = 3'b000;
            q_src1[i] = 3'b000;
            q_src2[i] = 3'b000;
            q_has_dest[i] = 0;
            q_has_src1[i] = 0;
            q_has_src2[i] = 0;
            if(qeue[i][0] == 1'b1) begin
                case (qeue[i][16:10])
                    `NOP: begin
                        q_has_dest[i] = 0;
                    end
                    `AND, `ADD, `ADDF, `SUB, `SUBF,
                    `OR, `XOR, `NAND, `NOR, `NXOR: begin
                        q_dest[i] = qeue[i][9:7];
                        q_src1[i] = qeue[i][6:4];
                        q_src2[i] = qeue[i][3:1];
                        q_has_dest[i] = 1;
                        q_has_src1[i] = 1;
                        q_has_src2[i] = 1;
                    end
                    `SHIFTR, `SHIFTRA, `SHIFTL: begin
                        q_dest[i] = qeue[i][9:7];
                        q_src1[i] = qeue[i][9:7];
                        q_has_dest[i] = 1;
                        q_has_src1[i] = 1;
                    end
                    default: begin
                        case (qeue[i][16:12])
                            `LOAD: begin
                                q_dest[i] = qeue[i][11:9];
                                q_src1[i] = qeue[i][3:1];
                                q_has_dest[i] = 1;
                                q_has_src1[i] = 1;
                            end
                            `LOADC: begin
                                q_dest[i] = qeue[i][11:9];
                                q_has_dest[i] = 1;
                            end
                            `STORE: begin
                                q_src1[i] = qeue[i][3:1];
                                q_src2[i] = qeue[i][11:9];
                                q_has_src1[i] = 1;
                                q_has_src2[i] = 1;
                            end
                            default: begin
                                case (qeue[i][16:13])
                                    `JMP: begin
                                        q_src1[i] = qeue[i][3:1];
                                        q_has_src1[i] = 1;
                                    end
                                    `JMPcond: begin
                                        q_src1[i] = qeue[i][9:7];
                                        q_src2[i] = qeue[i][3:1];
                                        q_has_src1[i] = 1;
                                        q_has_src2[i] = 1;
                                    end
                                    `JMPRcond: begin
                                        q_src1[i] = qeue[i][9:7];
                                        q_has_src1[i] = 1;
                                    end
                                endcase
                            end
                        endcase
                    end
                endcase
            end
        end
    end

    /*COMBINATIONAL: Clear ready bit for instruction being dispatched*/
    always @(*) begin
        q0_modified = qeue[0];
        q1_modified = qeue[1];
        q2_modified = qeue[2];
        q3_modified = qeue[3];
        
        /*if readIndex is valid, clear that instruction's ready bit*/
        if(readIndex < 4) begin
            case(readIndex)
                0: q0_modified[17] = 1'b0;
                1: q1_modified[17] = 1'b0;
                2: q2_modified[17] = 1'b0;
                3: q3_modified[17] = 1'b0;
            endcase
        end
    end

    /*outputs with ready bit masked*/
    assign q0w = q0_modified;
    assign q1w = q1_modified;
    assign q2w = q2_modified;
    assign q3w = q3_modified;

    /*combinational logic for stall and new instruction preparation*/
    always @(*) begin   
        counter = 0;
        stall = 0;
        q = 0;
        
        if(pc_wr_enable) begin
            stall = 0;
        end
        else begin
            /*check valid spaces*/
            index = 2'b11;
            for(i=0; i<4; i=i+1) begin
                if(qeue[i][0] == 1'b1) begin  
                    counter = counter + 1;
                end
                else if(index == 2'b11) begin
                    index = i[1:0];
                end
            end
            
            /* STALL LOGIC REVISED */
            if(counter == 4) begin
                stall = 1;
            end
            else if (stall_control_active) begin
                /* Daca avem un branch in pipe, tinem stall pana se rezolva */
                stall = 1;
            end
            /* Important: Nu dam stall combinational IMEDIAT cand vedem JMP la input.
               Il lasam sa intre in coada (next clock cycle logic), si setam stall_control_active */
            
            else if(IR == 16'h0000) begin
                stall = 0;
            end
            else begin
                q[16:1] = IR;
                q[0] = 1'b1;
                q[17] = 1'b1;
                q[19:18] = 2'b00;
                q[20] = 1'b0;
                q[21] = 1'b0;
                
                /*WAW check*/
                if(ir_writes_reg) begin
                    for(i=0; i<4; i=i+1) begin
                        if(qeue[i][0] == 1'b1 && q_has_dest[i] == 1) begin
                            if(q_dest[i] == ir_dest) begin
                                q[17] = 1'b0;
                                /*Aici stall e ok pentru hazard, nu pentru control*/
                                stall = 1; 
                            end
                        end
                    end
                end
                
                /*WAR check*/
                if(ir_writes_reg) begin
                    for(i=0; i<4; i=i+1) begin
                        if(qeue[i][0] == 1'b1) begin
                            if((q_has_src1[i] == 1 && q_src1[i] == ir_dest) ||
                               (q_has_src2[i] == 1 && q_src2[i] == ir_dest)) begin
                                q[17] = 1'b0;
                                stall = 1;
                            end
                        end
                    end
                end
            end
        end
    end

    /*sequential logic*/
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            qeue[0] <= 32'b0;
            qeue[1] <= 32'b0;
            qeue[2] <= 32'b0;
            qeue[3] <= 32'b0;
            stall_control_active <= 0;
        end
        else if(flush) begin
            /* FLUSH: Golim tot si resetam stall-ul */
            qeue[0] <= 32'b0;
            qeue[1] <= 32'b0;
            qeue[2] <= 32'b0;
            qeue[3] <= 32'b0;
            stall_control_active <= 0;
        end
        else begin
            /* Daca nu e flush, dar EX zice ca a terminat un branch (Not Taken) */
            if (branch_processed_ex) begin
                stall_control_active <= 0;
            end
            
            /*free slot from writeback*/
            if(wbIndex < 4) begin
                qeue[wbIndex][0] <= 1'b0;
            end
            
            /*insert new instruction*/
            /* Modificare: Nu mai blocam JMP sa intre in coada */
            if(!stall && counter < 4 && IR != 16'h0000) begin
                
                /* Daca instructiunea care INTRA acum e JMP, activam stall pe viitor */
                if (IR[`FIELD_OPCODE_4] == `JMP ||
                    IR[`FIELD_OPCODE_4] == `JMPR ||
                    IR[`FIELD_OPCODE_4] == `JMPcond ||
                    IR[`FIELD_OPCODE_4] == `JMPRcond) begin
                        stall_control_active <= 1;
                end

                /*update age*/
                for(i=0; i<4; i=i+1) begin
                    if(qeue[i][0] == 1'b1 && qeue[i][19:18] < 2'b11) begin  
                        qeue[i][19:18] <= qeue[i][19:18] + 2'b01;
                    end
                end
                
                qeue[index] <= q;
            end
        end
    end

endmodule