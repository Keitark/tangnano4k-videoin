`timescale 1ns/1ps
module tb_ntsc_clean_colors #(parameter integer CLEAN=1);
    reg clk=0,reset=1,hs=0;
    always #5 clk=~clk;
    reg [7:0] narrow=32,wide=32;
    reg [23:0] source_phase=0;
    wire valid,locked; wire [9:0] x;wire [15:0] rgb;
    ntsc_color_decoder #(.CLEAN_CHROMA(CLEAN),.PHASE_QUALIFIED(1),
        .SPLIT_CHROMA(1),.FIXED_BLACK_LEVEL(32),.REQUIRE_FIELD_WINDOW(0),
        .BURST_START(7),.BURST_END(38),.LUMA_GAIN_SHIFT(1)) dut(
        .clk(clk),.reset(reset),.color_enable(1'b1),.sample_level(narrow),
        .chroma_level(wide),.hsync_pulse(hs),.vsync_pulse(1'b0),
        .pixel_valid(valid),.pixel_x(x),.pixel_rgb565(rgb),.color_locked(locked));
    integer line,pos,r,g,b,checked=0;
    real theta,u,v,y;
    initial begin
        repeat(4) @(negedge clk);reset=0;
        for(line=0;line<300;line=line+1) begin
            for(pos=0;pos<858;pos=pos+1) begin
                hs=pos==0;
                theta=6.283185307179586*source_phase/16777216.0;
                y=32;u=0;v=0;
                if(pos>=7 && pos<38) u=-24;
                if(CLEAN>=3 && (line==100 || line>=280)) u=0;
                if(pos>=78 && pos<789) begin
                    // Independent encoder: same luma, opposing V, zero U.
                    // Red-dominant then cyan-dominant. No forced decoder state.
                    y=96;v=line<120 ? 40 : -40;
                    if(line>=200) begin v=0;u=line<240 ? 40 : -40;end
                end
                narrow=$rtoi(y);wide=$rtoi(y+u*$sin(theta)+v*$cos(theta));
                source_phase=source_phase+24'h43e0f8;
                @(posedge clk);#1;
                if(line>=80 && line<180 && valid && x==300) begin
                    if(!locked) $fatal(1,"synthetic burst failed lock line %0d",line);
                    r=rgb[15:11]*8;g=rgb[10:5]*4;b=rgb[4:0]*8;
                    if(line<120 && !(r>g+50 && r>b+50))
                        $fatal(1,"positive V not red: RGB=%0d %0d %0d",r,g,b);
                    if(line>=120 && !(g>r+50 && b>r+50))
                        $fatal(1,"negative V not cyan: RGB=%0d %0d %0d",r,g,b);
                    checked=checked+1;
                end
                if(line>=200 && line<280 && valid && x==300) begin
                    if(!locked) $fatal(1,"U-axis test lost lock");
                    r=rgb[15:11]*8;g=rgb[10:5]*4;b=rgb[4:0]*8;
                    if(line<240 && !(b>r+50 && b>g+50))
                        $fatal(1,"positive U not blue: RGB=%0d %0d %0d",r,g,b);
                    if(line>=240 && !(r>b+50 && g>b+50))
                        $fatal(1,"negative U not yellow: RGB=%0d %0d %0d",r,g,b);
                    checked=checked+1;
                end
                @(negedge clk);
            end
        end
        if(checked!=180) $fatal(1,"missing tested lines");
        if(CLEAN>=3 && locked) $fatal(1,"sustained absent burst must disable color");
        $display("PASS independent NTSC encoder, burst acquisition and 180 red/cyan/blue/yellow lines");
        $finish;
    end
endmodule
