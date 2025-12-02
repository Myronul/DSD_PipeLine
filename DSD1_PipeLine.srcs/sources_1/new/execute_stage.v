`timescale 1ns / 1ps

module execute_stage(
    input clk,
    output memRd,
    output memWr,
    /*signals from the read stage to the execute*/
    input [`REG_ADR-1:0]RRop1, /*Read register that will contain: OP1 | OP2 | DEST */
    input [`REG_ADR-1:0]RRop2,
    input [`REG_ADR-1:0]RRdest,
    input [`OPCODE_SIZE-1:0]RRopcode, /*the opcode of the instrction*/
    /*output data to the write back stage*/
    output reg [`D_SIZE-1:0]dataOut,
    output reg [`REG_ADR-1:0]dataDest,
    /*signals for the memory data*/
    output [`A_SIZE-1:0]addrMem, /*obs! vezi sa fie activare semnalelor secventiala ca in memorie se scrie pe ceas!*/
    output [`D_SIZE-1:0]dataOutMem
);

reg [`D_SIZE-1:0]RegResult;

/*define ALU combinational*/
/*when RRop1 or RRop2 or RRopcode changes*/
always@(*)begin
    case(RRopcode)
        `AND: begin
              RegResult = RRop1 & RRop2;
              end
    endcase
end


always@(posedge clk) begin
    dataOut <= RegResult;
    dataDest <= RRdest;
end


endmodule
