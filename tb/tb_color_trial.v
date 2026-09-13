`timescale 1ns/1ps
module tb_color_trial;
    reg clk=0, reset=1;
    reg [7:0] data=0;
    integer k, r, g, b;
    reg [23:0] before_phase;
    always #5 clk=~clk;
    hdmi_ntsc_line_tx #(.FRAME_BITS(8),.COLOR_OUTPUT(1),.RUNTIME_PROBE(1),.FRAME_WIDTH(80)) hdmi(
        .clk_pixel(clk),.clk_5x_pixel(clk),.resetn(!reset),.serial_resetn(!reset),
        .frame_rd_data(data),.field_toggle_async(1'b0));
    ntsc_color_decoder #(.PHASE_QUALIFIED(1),.BURST_START(0),.BURST_END(32)) decoder(
        .clk(clk),.reset(reset),.sample_level(8'd64),.chroma_level(8'd64),
        .hsync_pulse(1'b0),.vsync_pulse(1'b0));
    initial begin
        repeat(4) @(negedge clk); reset=0;
        force hdmi.active_mode=0;
        for(k=0;k<256;k=k+1) begin
            data=k; #1;
            r=((k>>5)&7); r=(r<<5)|(r<<2)|(r>>1);
            g=((k>>2)&7); g=(g<<5)|(g<<2)|(g>>1);
            b=(k&3)*85;
            if(hdmi.frame_red!==r || hdmi.frame_green!==g || hdmi.frame_blue!==b)
                $fatal(1,"RGB332 mapping %d",k);
        end
        force hdmi.active_mode=2;
        for(k=0;k<16;k=k+1) begin
            data=k; #1;
            if(hdmi.frame_red!==32+k*12 || hdmi.frame_green!==hdmi.frame_red || hdmi.frame_blue!==hdmi.frame_red)
                $fatal(1,"color mode contaminated raw page");
        end
        @(negedge clk);
        force decoder.line_active=1;
        force decoder.line_position=33;
        force decoder.burst_i=-20'sd2000;
        force decoder.burst_q=20'sd1000;
        force decoder.color_score=15;
        before_phase=decoder.phase_offset;
        @(negedge clk);
        if(decoder.phase_offset !== before_phase+24'h100000 || decoder.color_locked!==0)
            $fatal(1,"phase correction direction/qualification");
        force decoder.burst_q=20'sd0;
        @(negedge clk);
        if(decoder.color_locked!==1) $fatal(1,"aligned burst not accepted");
        force decoder.burst_i=20'sd0;
        @(negedge clk);
        if(decoder.color_locked!==0) $fatal(1,"absent burst not rejected");
        $display("PASS RGB332, diagnostic grayscale, burst phase direction and qualification");
        $finish;
    end
endmodule
