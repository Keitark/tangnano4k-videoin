`timescale 1ns/1ps
module tb_ntsc_frame_store;
    parameter integer DEPTH=38400;
    parameter integer DATA_BITS=4;
    reg wc=0, rc=0, we=0;
    reg [15:0] wa=0, ra=0;
    reg [DATA_BITS-1:0] wd=0;
    wire [DATA_BITS-1:0] data;
    integer i;
    always #5 wc=~wc;
    always #7 rc=~rc;
    ntsc_lowres_frame_store #(.DEPTH(DEPTH),.DATA_BITS(DATA_BITS)) dut(wc,we,wa,wd,rc,ra,data);
    function [DATA_BITS-1:0] pattern;
        input integer address;
        begin pattern=address^(address>>4)^(address>>8)^(address>>12); end
    endfunction
    initial begin
        for(i=0;i<DEPTH;i=i+1) begin
            @(negedge wc); we=1; wa=i; wd=pattern(i);
        end
        @(negedge wc); we=0;
        // Permuted address order crosses segments and banks on every read.
        for(i=0;i<DEPTH;i=i+1) begin
            @(negedge rc); ra=(i*7919)%DEPTH;
            @(posedge rc); #1;
            if(data !== pattern(ra)) $fatal(1,"memory mismatch address=%d",ra);
        end
        $display("PASS %d pixels: dual-clock store, all segments, one-cycle read",DEPTH);
        $finish;
    end
endmodule
