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
    input [`D_SIZE-1:0]RRop1,
    input [`D_SIZE-1:0]RRop2,
    input [`REG_ADR-1:0]RRdest,
    input [`OPCODE_SIZE-1:0]RRopcode,
    /*output data to the write back stage*/
    output reg [`D_SIZE-1:0]dataOut,
    output reg [`REG_ADR-1:0]dataDest,
    /*signals for the memory data*/
    output reg [`A_SIZE-1:0]addrMem,
    output reg [`D_SIZE-1:0]dataMem,
    /*signals for the jmp instruction to the fetch stage*/
    output reg [`A_SIZE-1:0] jmpPC,
    output reg pc_wr_enable, 
    output reg flush,
    
    input [7:0] wbIndexIn, 
    output reg [7:0] wbIndexOut,
    
    output reg branch_done, /*NEW: Signal IW to release stall*/

    /*Data forwarding from EX to READ unit RAW hazard*/
    output reg [`REG_ADR-1:0] src, 
    output reg [`D_SIZE-1:0] res,
    output readyForward
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
always@(*) begin
    src = 0;
    res = 0;
    branch_done = 0; /*Default 0*/
    
    case(RRopcode[`OPCODE_SIZE-1:0])
        `NOP: begin 
            RegResult = 0;
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
            res = RegResult;
            src = RRdest;
        end
        `ADD: begin
            RegResult = RRop1 + RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;        
            res = RegResult;
            src = RRdest;
        end
        `ADDF: begin
            RegResult = RRop1 + RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end     
        `SUB: begin
            RegResult = RRop1 - RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end              
        `SUBF: begin
            RegResult = RRop1 - RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end
        `OR: begin
            RegResult = RRop1 | RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end
        `XOR: begin
            RegResult = RRop1 ^ RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end
        `NAND: begin
            RegResult = ~(RRop1 & RRop2);
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end
        `NOR: begin
            RegResult = ~(RRop1 | RRop2);
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end
        `NXOR: begin
            RegResult = ~(RRop1 ^ RRop2);
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end 
        `SHIFTR: begin
            RegResult = RRop1 >> RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end     
        `SHIFTRA: begin
            RegResult = RRop1 >>> RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end 
        `SHIFTL: begin
            RegResult = RRop1 << RRop2;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end
        `LOADC: begin
            RegResult = RRop1;
            flag = 0;
            jmpPC = 0;
            pc_wr_enable = 0;
            flush = 0;
            res = RegResult;
            src = RRdest;
        end

        `JMP: begin
            RegResult = 0;
            flag = 1;
            jmpPC = RRop1[`A_SIZE-1:0];
            pc_wr_enable = 1;
            flush = 1;
            branch_done = 1; /*Semnalizam ca s-a procesat JMP*/
        end
        `JMPcond: begin
            branch_done = 1; /*Semnalizam ca s-a procesat JMPcond (Taken or Not)*/
            case(RRopcode[2:0]) 
                3'b000: begin
                    if(RRop1 <= 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[`A_SIZE-1:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
                end 
                3'b001: begin
                    if(RRop1 >= 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[`A_SIZE-1:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
                end
                3'b010: begin
                    if(RRop1 == 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[`A_SIZE-1:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
                end
                3'b011: begin
                    if(RRop1 != 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[`A_SIZE-1:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
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
        `JMPR: begin
            RegResult = 0;
            flag = 1;
            jmpPC = RRop1[5:0];
            pc_wr_enable = 1;
            flush = 1;
            branch_done = 1;
        end
        `JMPRcond: begin
            branch_done = 1;
            case(RRopcode[2:0]) 
                3'b000: begin
                    if(RRop1 <= 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[5:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
                end 
                3'b001: begin
                    if(RRop1 >= 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[5:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
                end
                3'b010: begin
                    if(RRop1 == 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[5:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
                end
                3'b011: begin
                    if(RRop1 != 0) begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = RRop2[5:0];
                        pc_wr_enable = 1;
                        flush = 1;
                    end
                    else begin
                        RegResult = 0;
                        flag = 1;
                        jmpPC = 0;
                        pc_wr_enable = 0;
                        flush = 0;
                    end
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

assign readyForward = 1'b1; /*data forwarding always ready*/

always@(posedge clk) begin
    /*add fsm for memRd and stall logic*/
    
    wbIndexOut <= wbIndexIn;
    if(stateRead != 0) begin
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
    
    else if(RRopcode[`OPCODE_SIZE-1:0] == `STORE) begin
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
        /*normal case for no load no store*/
        if(!flag) begin
            loadEnable <= 1; /*load value in registers*/
            loadMem <= 0;
            memWr <= 0;
            memRd <= 0;
            dataOut <= RegResult;
            dataDest <= RRdest;
        end
        else begin
            loadEnable <= 0;
            loadMem <= 0;
            memWr <= 0;
            memRd <= 0;
            dataOut <= 0;
            dataDest <= 0;
        end
    end
end

endmodule