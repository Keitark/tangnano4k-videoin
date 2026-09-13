`timescale 1ns/1ps
module tb_delta_cic2;
    reg clk=0,reset=1,bit_in=0;
    always #5 clk=~clk;
    wire [7:0] level,wide,legacy_level,legacy_wide;
    wire feedback,legacy_feedback,strobe,legacy_strobe;
    delta_modulator_core #(.WIDE_CIC2(1)) dut(
        .clk(clk),.reset(reset),.comparator_bit(bit_in),.feedback_bit(feedback),
        .reconstructed_level(level),.wide_reconstructed_level(wide),.sample_strobe(strobe));
    delta_modulator_core legacy(
        .clk(clk),.reset(reset),.comparator_bit(bit_in),.feedback_bit(legacy_feedback),
        .reconstructed_level(legacy_level),.wide_reconstructed_level(legacy_wide),.sample_strobe(legacy_strobe));
    integer n,k,j,total,samples=0;
    reg [31:0] rng=32'h12345678;
    reg [63:0] bits=0;
    reg b0=0,b1=0;
    initial begin
        repeat(4) @(negedge clk);reset=0;
        for(n=0;n<10000;n=n+1) begin
            rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
            bit_in=n<256 ? 1'b0 : n<512 ? 1'b1 : rng[0];
            bits={bits[62:0],b1};b1=b0;b0=bit_in;
            total=0;
            for(k=0;k<16;k=k+1)
                for(j=0;j<16;j=j+1) total=total+bits[k+j+1];
            @(posedge clk);#1;
            if(feedback!==legacy_feedback || feedback!==bit_in ||
               strobe!==legacy_strobe || level!==legacy_level)
                $fatal(1,"feedback, narrow sync or strobe changed");
            if(strobe) begin
                if(wide!==(total>255 ? 255 : total))
                    $fatal(1,"triangular sum n=%0d actual=%0d expected=%0d",n,wide,total);
                samples=samples+1;
            end
            @(negedge clk);
        end
        $display("PASS CIC2 exact triangular sums over %0d samples; unchanged feedback/sync; zero/full-scale/random",samples);
        $finish;
    end
endmodule
