`timescale 1ns/1ps
module tb_delta_picture_bandwidth;
    reg clk=0, reset=1, bit_in=0;
    wire [7:0] narrow, wide;
    wire strobe;
    real phase=0.0, accumulator=0.0, ni=0.0,nq=0.0,wi=0.0,wq=0.0,ratio;
    integer i;
    always #5 clk=~clk;
    delta_modulator_core dut(.clk(clk),.reset(reset),.comparator_bit(bit_in),
        .reconstructed_level(narrow),.wide_reconstructed_level(wide),.sample_strobe(strobe));
    initial begin
        repeat(4) @(negedge clk); reset=0;
        // Digital density stimulus at the NTSC subcarrier/ADC-clock ratio;
        // this validates filters only, not the physical analog loop.
        for(i=0;i<32768;i=i+1) begin
            @(negedge clk);
            phase=phase+6.283185307179586*3579545.0/108000000.0;
            accumulator=accumulator+0.45+0.15*$sin(phase);
            bit_in=accumulator>=1.0;
            if(bit_in) accumulator=accumulator-1.0;
            @(posedge clk); #1;
            if(i>1024 && strobe) begin
                ni=ni+(narrow-115.2)*$sin(phase); nq=nq+(narrow-115.2)*$cos(phase);
                wi=wi+(wide-115.2)*$sin(phase); wq=wq+(wide-115.2)*$cos(phase);
            end
        end
        ratio=$sqrt((wi*wi+wq*wq)/(ni*ni+nq*nq));
        if(ratio<6.0) $fatal(1,"insufficient wider-band subcarrier response %f",ratio);
        $display("PASS 16-sample picture filter subcarrier amplitude ratio over 64-sample sync filter: %f",ratio);
        $finish;
    end
endmodule
