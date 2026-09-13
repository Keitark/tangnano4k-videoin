`timescale 1ns/1ps
// Identical external stimulus for RTL and the exact failed synthesized decoder.
module tb_color_decoder_audit;
    reg clk=0, reset=1, hs=0;
    reg [7:0] level=64, wide=64;
    wire valid, color;
    wire [7:0] black, luma, pixel;
    integer line, pos, pixels=0;
    always #37 clk=~clk;
`ifdef GATE
    GSR GSR(.GSRI(1'b1));
    ntsc_color_decoder dut(.clk_sample_13m5(clk),.n1044_5(reset),
        .sample_reset_pipe(!reset),.hsync_pulse(hs),.decoder_level_hold(level[7:1]),
        .burst_level_hold_0(wide[0]),.burst_level_hold_4(wide[4]),
        .burst_level_hold_5(wide[5]),.burst_level_hold_6(wide[6]),.burst_level_hold_7(wide[7]),
        .decoded_pixel_valid(valid),.color_locked_Z(color),
        .debug_black_level_Z(black),.debug_luma_level_Z(luma),
        .decoded_pixel_rgb565_15(pixel[7]),.decoded_pixel_rgb565_14(pixel[6]),
        .decoded_pixel_rgb565_13(pixel[5]),.decoded_pixel_rgb565_10(pixel[4]),
        .decoded_pixel_rgb565_9(pixel[3]),.decoded_pixel_rgb565_8(pixel[2]),
        .decoded_pixel_rgb565_4(pixel[1]),.decoded_pixel_rgb565_3(pixel[0]));
`else
    wire [15:0] rgb;
    assign pixel={rgb[15:13],rgb[10:8],rgb[4:3]};
    ntsc_color_decoder #(.REQUIRE_FIELD_WINDOW(0),.ENABLE_COLOR(1),.LUMA_GAIN_SHIFT(1),
        .SPLIT_CHROMA(1),.PHASE_QUALIFIED(1),.BURST_START(0),.BURST_END(32),.TRACK_BLACK(1)) dut(
        .clk(clk),.reset(reset),.sample_level(level),.chroma_level(wide),
        .hsync_pulse(hs),.vsync_pulse(1'b0),.pixel_valid(valid),.pixel_rgb565(rgb),
        .color_locked(color),.debug_black_level(black),.debug_luma_level(luma));
`endif
    always @(negedge clk) if(!reset && valid) pixels=pixels+1;
    initial begin
        repeat(8) @(negedge clk); reset=0;
        for(line=0;line<24;line=line+1) begin
            for(pos=0;pos<858;pos=pos+1) begin
                @(negedge clk); hs=(pos==0);
                level=(pos>=78 && pos<789) ? 128 : 64;
                wide=level;
            end
        end
        @(negedge clk); hs=0;
        repeat(4) @(negedge clk);
        $display("AUDIT pixels=%d black=%d luma=%d rgb332=%h color=%b",pixels,black,luma,pixel,color);
        if(pixels!=24*640 || black<62 || black>65)
            $fatal(1,"decoder cannot reconstruct basic luma without burst");
        $display("PASS decoder no-burst fallback: pixel count and black tracking");
        $finish;
    end
endmodule
