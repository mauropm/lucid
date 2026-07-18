`default_nettype none

package lucid_msg_pkg;

    parameter int MODULE_SCHEDULER    = 0;
    parameter int MODULE_ARITH        = 1;
    parameter int MODULE_COMPARE      = 2;
    parameter int MODULE_CLOSURE      = 3;
    parameter int MODULE_ENV          = 4;
    parameter int MODULE_CONTINUATION = 5;
    parameter int MODULE_HEAP         = 6;
    parameter int MODULE_GC           = 7;
    parameter int MODULE_BROADCAST    = 8'hFF;

    parameter int HEADER_DEST_TOP   = 31;
    parameter int HEADER_DEST_BOT   = 24;
    parameter int HEADER_SRC_TOP    = 23;
    parameter int HEADER_SRC_BOT    = 16;
    parameter int HEADER_TYPE_TOP   = 15;
    parameter int HEADER_TYPE_BOT   = 8;
    parameter int HEADER_FLAGS_TOP  = 7;
    parameter int HEADER_FLAGS_BOT  = 0;

    parameter int FLAG_RESP_REQ   = 0;
    parameter int FLAG_HIGH_PRIO  = 1;
    parameter int FLAG_ERROR      = 2;
    parameter int FLAG_BROADCAST  = 3;
    parameter int FLAG_LAST       = 4;

    parameter int MSG_NOP        = 8'h00;
    parameter int MSG_RESET      = 8'h01;
    parameter int MSG_HALT       = 8'h02;
    parameter int MSG_ACK        = 8'h03;
    parameter int MSG_NACK       = 8'h04;
    parameter int MSG_STATUS_REQ = 8'h05;
    parameter int MSG_STATUS_RESP= 8'h06;

    parameter int MSG_GRAPH_LOAD  = 8'h10;
    parameter int MSG_GRAPH_EXEC  = 8'h11;
    parameter int MSG_NODE_READY  = 8'h12;
    parameter int MSG_NODE_SCHED  = 8'h13;
    parameter int MSG_NODE_RESULT = 8'h14;
    parameter int MSG_GRAPH_DONE  = 8'h15;

    parameter int MSG_ALLOC      = 8'h20;
    parameter int MSG_ALLOC_RESP = 8'h21;
    parameter int MSG_ALLOC_FAIL = 8'h22;

    parameter int MSG_EXEC_PRIM   = 8'h30;
    parameter int MSG_PRIM_RESULT = 8'h31;

    parameter int MSG_MAKE_CLOSURE   = 8'h40;
    parameter int MSG_CLOSURE_RESULT = 8'h41;
    parameter int MSG_APPLY          = 8'h42;

    parameter int MSG_GC_TRIGGER = 8'h50;
    parameter int MSG_GC_DONE    = 8'h51;
    parameter int MSG_GC_MARK    = 8'h52;

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
