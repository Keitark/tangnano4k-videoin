`timescale 1ns/1ps
module tb_ntsc_chroma_fir #(parameter integer CLEAN=1);
    reg clk=0,reset=1;
    always #5 clk=~clk;
    reg signed [13:0] signal_q4=0;
    reg [23:0] phase=0;
    wire signed [14:0] mi,mq;
    wire signed [15:0] fi,fq;
    ntsc_chroma_fir dut(clk,reset,signal_q4,phase,mi,mq,fi,fq);
    reg [7:0] level=0;
    ntsc_color_decoder #(.CLEAN_CHROMA(CLEAN),.FIXED_BLACK_LEVEL(32)) decoder(
        .clk(clk),.reset(reset),.color_enable(1'b0),.sample_level(level),
        .chroma_level(level),.hsync_pulse(1'b0),.vsync_pulse(1'b0));
    integer k,n,expected_i,expected_q,sum_i,sum_q;
    integer hist_i[0:15],hist_q[0:15];
    real a;
    function integer coeff;
        input integer p;
        begin
            case(p&15)
                0,8:coeff=0; 1,7:coeff=3; 2,6:coeff=6; 3,5:coeff=7;
                4:coeff=8; 9,15:coeff=-3; 10,14:coeff=-6;
                11,13:coeff=-7; default:coeff=-8;
            endcase
        end
    endfunction
    initial begin
        sum_i=0;sum_q=0;
        for(k=0;k<16;k=k+1) begin hist_i[k]=0;hist_q[k]=0;end
        repeat(4) @(negedge clk);reset=0;
        for(n=0;n<4096;n=n+1) begin
            phase=n*24'h43e0f8;
            a=6.283185307179586*phase/16777216.0;
            signal_q4=$rtoi(640.0*$cos(a));
            level=n<256 ? n : 128;
            #1;
            expected_i=($signed(signal_q4)*coeff((phase>>20)+4))>>>3;
            expected_q=($signed(signal_q4)*coeff(phase>>20))>>>3;
            if(mi!==expected_i || mq!==expected_q) $fatal(1,"mixer signed arithmetic n=%0d",n);
            sum_i=sum_i+expected_i-hist_i[n&15];
            sum_q=sum_q+expected_q-hist_q[n&15];
            hist_i[n&15]=expected_i;hist_q[n&15]=expected_q;
            @(posedge clk);#1;
            if(fi!==(sum_i>>>4) || fq!==(sum_q>>>4)) $fatal(1,"FIR sum n=%0d",n);
            if(n>300 && (fi<270 || fi>350 || fq < -100 || fq>40))
                $fatal(1,"coherent tone outside expected amplitude I=%0d Q=%0d",fi,fq);
            if(n>300 && decoder.notch_y_q4!==13'sd2048) $fatal(1,"notch DC gain");
            if(n>300 && decoder.y_value!==16'sd96) $fatal(1,"clean luma/black signed arithmetic");
            @(negedge clk);
        end
        level=0;repeat(32) @(negedge clk);
        if(decoder.y_value!==-16'sd32) $fatal(1,"negative black subtraction");
        level=255;repeat(32) @(negedge clk);
        if(decoder.y_value!==16'sd223) $fatal(1,"maximum luma overflow");
        $display("PASS sinusoidal mixer, 4096 sliding sums, coherent tone, DC gain and signed luma limits");
        $finish;
    end
endmodule
