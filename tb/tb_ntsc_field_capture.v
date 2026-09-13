`timescale 1ns/1ps
module tb_ntsc_field_capture;
    parameter integer FRAME_WIDTH=128;
    parameter integer RUNTIME_PROBE=0;
    localparam integer PIXELS=FRAME_WIDTH*120;
    reg clk=0, reset=1, hs=0, vs=0, valid=0;
    integer i, f, writes=0;
    reg [2*PIXELS-1:0] written=0;
    always #5 clk=~clk;
    nano4k_ntsc_hdmi #(.SOURCE_FIELD_SYNC(1),.FRAME_WIDTH(FRAME_WIDTH),
        .RUNTIME_PROBE(RUNTIME_PROBE),.COLOR_OUTPUT(FRAME_WIDTH==80)) dut(.clk_27m(1'b0),.reset_n(1'b1),.video_p(1'b0),.video_n(1'b0));
    always @(posedge clk) if (!reset && dut.frame_wr_en) begin
        if(dut.frame_wr_addr >= 2*PIXELS) $fatal(1,"write out of bounds");
        if(written[dut.frame_wr_addr]) $fatal(1,"duplicate pixel address");
        written[dut.frame_wr_addr]=1;
        writes=writes+1;
    end
    initial begin
        force dut.clk_sample_13m5=clk;
        force dut.sample_reset=reset;
        force dut.hsync_pulse=hs;
        force dut.source_field_pulse=vs;
        force dut.decoded_pixel_valid=valid;
        if(RUNTIME_PROBE) force dut.adopted_toggle=dut.probe_toggle;
        repeat(4) @(negedge clk); reset=0;
        @(negedge clk); vs=1;
        @(negedge clk); vs=0;
        for(f=0;f<2;f=f+1) begin
            for(i=0;i<262;i=i+1) begin
                hs=1; @(negedge clk); hs=0; valid=1;
                repeat(640) @(negedge clk);
                valid=0; repeat(217) @(negedge clk);
            end
            vs=1; @(negedge clk); vs=0;
            @(negedge clk);
            if(writes != (f+1)*PIXELS) $fatal(1,"incorrect field size %d",writes);
            if(dut.completed_bank !== f[0]) $fatal(1,"incorrect bank handoff");
        end
        if(!(&written)) $fatal(1,"missing capture addresses");
        repeat(8) @(negedge clk);
        // Buffered runtime waits for ACK then a fresh boundary: the second
        // source field is skipped while the first published bank is adopted.
        if(RUNTIME_PROBE && (dut.probe_status_source[39:32]!=1 || dut.probe_status_source[31:16]!=0 ||
            dut.probe_status_source[15:0]!=PIXELS))
            $fatal(1,"runtime capture accepted=%d rejected=%d words=%d flags=%h",
                dut.probe_status_source[39:32],dut.probe_status_source[31:16],
                dut.probe_status_source[15:0],dut.probe_status_source[47:40]);
        $display("PASS source-anchored capture: two complete banks, each pixel written exactly once");
        $finish;
    end
endmodule
