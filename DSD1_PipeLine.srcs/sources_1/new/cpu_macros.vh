`define A_SIZE 20 //address space size 2^20 addresses
`define D_SIZE 32
`define INSTR_SIZE 16
`define REG_ADR 3
`define OPCODE_SIZE 7

//registers addreses
`define R0 3'h0
`define R1 3'h1
`define R2 3'h2
`define R3 3'h3
`define R4 3'h4
`define R5 3'h5
`define R6 3'h6
`define R7 3'h7

//opcodes defines
`define NOP      7'b0000000
`define ADD      7'b0000001
`define ADDF     7'b0000010
`define SUB      7'b0000011
`define SUBF     7'b0000100
`define AND      7'b0000101
`define OR       7'b0000110
`define XOR      7'b0000111
`define NAND     7'b0001000
`define NOR      7'b0001001
`define NXOR     7'b0001010
`define SHIFTR   7'b0001011
`define SHIFTRA  7'b0001100
`define SHIFTL   7'b0001101
`define LOAD     5'b10000 //5 bits 
`define LOADC    5'b11000 //5 bits 
`define STORE    5'b10100 //5 bits
`define JMP      4'b1111 //4 bits 
`define JMPR     4'b1110 //4 bits 
`define JMPcond  4'b1101 //4 bits
`define JMPRcond 4'b1001 //4bits

//take bits from instructions to decode the opcodes
`define FIELD_OPCODE_5 `INSTR_SIZE-1:`INSTR_SIZE-5 /*select bit expression 5 bit*/
`define FIELD_OPCODE_7 `INSTR_SIZE-1:`INSTR_SIZE-7 /*select bit expression 7 bit*/
`define FIELD_OPCODE_4 `INSTR_SIZE-1:`INSTR_SIZE-4 /*select bit expression 4 bit*/

















