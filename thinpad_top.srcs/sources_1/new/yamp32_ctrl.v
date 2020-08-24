/***************************************************************************/
/*  yamp32 (Yet Another MIPS Processor)                                    */
/*  Copyright (C) 2020 cassuto <diyer175@hotmail.com>                      */
/*  This project is free edition; you can redistribute it and/or           */
/*  modify it under the terms of the GNU Lesser General Public             */
/*  License(GPL) as published by the Free Software Foundation; either      */
/*  version 2.1 of the License, or (at your option) any later version.     */
/*                                                                         */
/*  This project is distributed in the hope that it will be useful,        */
/*  but WITHOUT ANY WARRANTY; without even the implied warranty of         */
/*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU      */
/*  Lesser General Public License for more details.                        */
/***************************************************************************/

module yamp32_ctrl(
    input wire i_ic_stall,
    input wire i_lsu_stall,
    input wire i_bypass_stall,
    output wire o_ifu_stall,
    output wire o_exu_stall,
    output wire o_exu_inv
);
    // Priority MUX
    assign o_ifu_stall = i_lsu_stall ? 1'b1 : (i_ic_stall|i_bypass_stall);
    assign o_exu_stall = i_lsu_stall ? 1'b1 : i_ic_stall;
    // It causes unexpected behaviors that issuing LSU insn repeatedly while ICACHE stalling.
    // so we make the output of EXU invalid (i.e. issue NOP insn)
    assign o_exu_inv = i_lsu_stall ? 1'b0 : i_ic_stall;

endmodule
