`ifndef YAMP32_PARAMETERS

//
// Configurations
//
parameter BPU_ALGORITHM = "static";

parameter ICACHE_P_WAYS = 2; // 2^P_WAYS ways
parameter ICACHE_P_SETS = 6; // 2^P_SETS sets
parameter ICACHE_P_LINE  = 8; // 2~P_LINE bytes

//
// IOPC
//
parameter IOPC_W = 22;
parameter IOPC_ADDU = 0;
parameter IOPC_ADDIU = 1;
parameter IOPC_MUL = 2;
parameter IOPC_AND = 3;
parameter IOPC_ANDI = 4;
parameter IOPC_LUI = 5;
parameter IOPC_OR = 6;
parameter IOPC_ORI = 7;
parameter IOPC_XOR = 8;
parameter IOPC_XORI = 9;
parameter IOPC_SLL = 10;
parameter IOPC_SRL = 11;
parameter IOPC_BEQ = 12;
parameter IOPC_BNE = 13;
parameter IOPC_BGTZ = 14;
parameter IOPC_J = 15;
parameter IOPC_JAL = 16;
parameter IOPC_JR = 17;
parameter IOPC_LB = 18;
parameter IOPC_LW = 19;
parameter IOPC_SB = 20;
parameter IOPC_SW = 21;

`endif // YAMP32_PARAMETERS
