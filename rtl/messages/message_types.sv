`default_nettype none

package lucid_msg_pkg;

    localparam int MODULE_SCHEDULER    = 0;
    localparam int MODULE_ARITH        = 1;
    localparam int MODULE_COMPARE      = 2;
    localparam int MODULE_CLOSURE      = 3;
    localparam int MODULE_ENV          = 4;
    localparam int MODULE_CONTINUATION = 5;
    localparam int MODULE_HEAP         = 6;
    localparam int MODULE_GC           = 7;
    localparam int MODULE_BROADCAST    = 8'hFF;

    localparam int HEADER_DEST_TOP   = 31;
    localparam int HEADER_DEST_BOT   = 24;
    localparam int HEADER_SRC_TOP    = 23;
    localparam int HEADER_SRC_BOT    = 16;
    localparam int HEADER_TYPE_TOP   = 15;
    localparam int HEADER_TYPE_BOT   = 8;
    localparam int HEADER_FLAGS_TOP  = 7;
    localparam int HEADER_FLAGS_BOT  = 0;

    localparam int FLAG_RESP_REQ   = 0;
    localparam int FLAG_HIGH_PRIO  = 1;
    localparam int FLAG_ERROR      = 2;
    localparam int FLAG_BROADCAST  = 3;
    localparam int FLAG_LAST       = 4;

    localparam int MSG_NOP        = 8'h00;
    localparam int MSG_RESET      = 8'h01;
    localparam int MSG_HALT       = 8'h02;
    localparam int MSG_ACK        = 8'h03;
    localparam int MSG_NACK       = 8'h04;
    localparam int MSG_STATUS_REQ = 8'h05;
    localparam int MSG_STATUS_RESP= 8'h06;

    localparam int MSG_GRAPH_LOAD  = 8'h10;
    localparam int MSG_GRAPH_EXEC  = 8'h11;
    localparam int MSG_NODE_READY  = 8'h12;
    localparam int MSG_NODE_SCHED  = 8'h13;
    localparam int MSG_NODE_RESULT = 8'h14;
    localparam int MSG_GRAPH_DONE  = 8'h15;

    localparam int MSG_ALLOC      = 8'h20;
    localparam int MSG_ALLOC_RESP = 8'h21;
    localparam int MSG_ALLOC_FAIL = 8'h22;

    localparam int MSG_EXEC_PRIM   = 8'h30;
    localparam int MSG_PRIM_RESULT = 8'h31;

    localparam int MSG_MAKE_CLOSURE   = 8'h40;
    localparam int MSG_CLOSURE_RESULT = 8'h41;
    localparam int MSG_APPLY          = 8'h42;

    localparam int MSG_GC_TRIGGER = 8'h50;
    localparam int MSG_GC_DONE    = 8'h51;
    localparam int MSG_GC_MARK    = 8'h52;

    function automatic logic [31:0] make_header(
        input logic [7:0] dest,
        input logic [7:0] src,
        input logic [7:0] msg_type,
        input logic [7:0] flags
    );
        return {dest, src, msg_type, flags};
    endfunction

    function automatic logic [7:0] get_dest(input logic [31:0] header);
        return header[31:24];
    endfunction

    function automatic logic [7:0] get_src(input logic [31:0] header);
        return header[23:16];
    endfunction

    function automatic logic [7:0] get_type(input logic [31:0] header);
        return header[15:8];
    endfunction

    function automatic logic [7:0] get_flags(input logic [31:0] header);
        return header[7:0];
    endfunction

endpackage

`default_nettype wire
