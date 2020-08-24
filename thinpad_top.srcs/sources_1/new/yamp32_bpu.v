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

module yamp32_bpu#(
    parameter ALGORITHM = "static"
)(
    input wire i_bcc_op,
    input wire i_bcc_backward,
    output wire o_bp_taken
);

generate
    if (ALGORITHM == "static") begin
        assign o_bp_taken = i_bcc_op & i_bcc_backward;
    end else begin
        $fatal ("\n unknown BPU algorithm\n");
    end
endgenerate

endmodule
