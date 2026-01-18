/*
Structure for IW:
Valid bit(1) | INSTR(16) | Readybit(1) | Age(2) | SRC1Valid(1) | SRC2Valid(1)
0 0000000000000000  0   0  0  0  0  | 000...000
0 1.............    16 17 18 19 20 21          31
So there will be in total 22 bit -> 32 bit
The src1 and src2 bit will be set by pipeline execution registers, if it is
the case 
RAW hazard is checked in READ stage as it follows another
check logic rather than WAW and WAR
Read at every clock cycle should send the index from which the instr
was dispatched to be set as valid=1 (free)
*/
`timescale 1ns / 1ps
`include "cpu_macros.vh"

module IW(
    input clk,
    input rst,
    input wire pc_wr_enable, /*signal from execute stage jmp ok*/
    input [`INSTR_SIZE-1:0] IR, /*current instruction from fetch*/
    input [7:0] wbIndex, /*index from the WriteBack stage*/ 
    output [31:0] q0w, /*list of instructions structure*/
    output [31:0] q1w,
    output [31:0] q2w,
    output [31:0] q3w,
    output reg stall /*stall fetch signal*/ 
);

integer i;
reg [1:0] index;                 
reg [31:0] qeue[3:0];           
reg [31:0] q;                    
reg [2:0] counter;

/*assign outputs*/
assign q0w = qeue[0];
assign q1w = qeue[1];
assign q2w = qeue[2];
assign q3w = qeue[3];


initial begin
    stall = 0;
    qeue[0] = 0;
    qeue[1] = 0;
    qeue[2] = 0;
    qeue[3] = 0;    
end


/*combinational logic*/
always @(*) begin   
    counter = 0;
    stall = 0;
    q = 0;
    
   /*check if jmp is executing
   if yes, skip IW and reset stall*/
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
        
        /*stall if queue is full*/
        if(counter == 4) begin
            stall = 1;
        end
        /*stall if new instruction is branch*/
        else if(IR[`FIELD_OPCODE_4] == `JMP ||
                IR[`FIELD_OPCODE_4] == `JMPR ||
                IR[`FIELD_OPCODE_4] == `JMPcond ||
                IR[`FIELD_OPCODE_4] == `JMPRcond) begin
            stall = 1;
        end
        else begin
            /*prepare new instruction*/
            q[16:1] = IR;
            q[0] = 1'b1;
            q[17] = 1'b1;
            q[19:18] = 2'b00;
            q[20] = 1'b0;
            q[21] = 1'b0;
            
            /*WAW check*/
            for(i=0; i<4; i=i+1) begin
                if(qeue[i][0] == 1'b1 && qeue[i][9:7] == IR[8:6]) begin
                    q[17] = 1'b0;
                    stall = 1;
                end
            end
            
            /*WAR check*/
            for(i=0; i<4; i=i+1) begin
                if(qeue[i][0] == 1'b1 && 
                   (qeue[i][6:4] == IR[8:6] || qeue[i][3:1] == IR[8:6])) begin
                    q[17] = 1'b0;
                    stall = 1;
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
    end
    else if(pc_wr_enable) begin
        /*flush all instruction for jmp*/
        qeue[0] <= 32'b0;
        qeue[1] <= 32'b0;
        qeue[2] <= 32'b0;
        qeue[3] <= 32'b0;
    end
    else begin
        /*eliberare slot from writeback */
        if(wbIndex < 4) begin
            qeue[wbIndex][0] <= 1'b0;
        end
        
        /*insert new instruction daca nu e stall si mai e loc*/
        if(!stall && counter < 4) begin
            /*update age for all valid instructions*/
            for(i=0; i<4; i=i+1) begin
                if(qeue[i][0] == 1'b1) begin  
                    qeue[i][19:18] <= qeue[i][19:18] + 2'b01;
                end
            end
            
            /*insert new instruction anyway*/
            qeue[index] <= q;
        end
    end
end

endmodule





