`timescale 1ns/1ps
module tb_hdmi_probe_handoff;
    parameter integer FRAME_WIDTH=128;
    reg clk=0, resetn=0, token=0, bank=0;
    reg [1:0] mode=0;
    reg [3:0] data=5;
    integer k, expected, x, y, b;
    reg [9:0] test_x=0, test_y=0;
    reg test_bank=0;
    wire ack;
    always #5 clk=~clk;
    hdmi_ntsc_line_tx #(.RUNTIME_PROBE(1), .FRAME_WIDTH(FRAME_WIDTH)) dut (
        .clk_pixel(clk),.clk_5x_pixel(clk),.resetn(resetn),.serial_resetn(resetn),
        .completed_bank_async(bank),.completed_toggle_async(token),
        .probe_mode_async(mode),.adopted_toggle(ack),.field_toggle_async(1'b0),
        .frame_rd_data(data),.line_locked_async(1'b1),.color_locked_async(1'b0),
        .hpll_phase_error_async(9'd0),.hpll_period_async(10'd858),
        .hsync_width_async(8'd64),.black_level_async(8'd64),.luma_level_async(8'd100));
    task frame_boundary;
        begin
            // Advance the actual frame-boundary logic, skipping only counters.
            force dut.h_count=799;
            force dut.v_count=525;
            force dut.long_frame=1;
            @(negedge clk);
            release dut.h_count; release dut.v_count; release dut.long_frame;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); resetn=1;
        bank=1; mode=1; token=1;
        repeat(10) @(negedge clk);
        if(ack!==0 || dut.active_bank!==0 || dut.active_mode!==0)
            $fatal(1,"page changed outside vblank");
        frame_boundary;
        if(ack!==1 || dut.active_bank!==1 || dut.active_mode!==1)
            $fatal(1,"bank/mode/token not adopted together");
        bank=0; mode=2; token=0;
        repeat(10) @(negedge clk);
        if(ack!==1 || dut.active_mode!==1) $fatal(1,"second page changed early");
        frame_boundary;
        if(ack!==0 || dut.active_bank!==0 || dut.active_mode!==2)
            $fatal(1,"second adoption failed");
        for(k=0;k<16;k=k+1) begin
            data=k; #1;
            if(dut.frame_red !== 32+k*12) $fatal(1,"guarded raw grayscale error");
        end
        force dut.active_mode=0;
        for(k=0;k<16;k=k+1) begin
            data=k; #1;
            expected=k*51; if(expected>255) expected=255;
            if(dut.frame_red !== expected) $fatal(1,"picture brightness/clamp error");
        end
        release dut.active_mode;
        force dut.h_count=test_x;
        force dut.v_count=test_y;
        force dut.active_bank=test_bank;
        for(b=0;b<2;b=b+1) begin
            test_bank=b;
            for(y=0;y<480;y=y+1) begin
                test_y=y;
                for(x=0;x<640;x=x+1) begin
                    test_x=x; #1;
                    expected=b*FRAME_WIDTH*120+(y/4)*FRAME_WIDTH+x/(640/FRAME_WIDTH);
                    if(dut.frame_rd_addr !== expected)
                        $fatal(1,"HDMI pixel/bank address mismatch x=%d y=%d",x,y);
                end
            end
        end
        release dut.h_count; release dut.v_count; release dut.active_bank;
        $display("PASS HDMI page metadata and acknowledgement change only at frame boundary");
        $finish;
    end
endmodule
