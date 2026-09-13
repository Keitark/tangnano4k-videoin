`timescale 1ns/1ps
module tb_delta_measurement_cdc;
    reg clk=0, reset=1, comparator_bit=0;
    integer i, j, population, wide_population;
    reg [6:0] stable_next;
    always #5 clk=~clk;
    delta_modulator_core dut (.clk(clk), .reset(reset),
        .comparator_bit(comparator_bit));
    initial begin
        repeat(4) @(negedge clk);
        reset=0;
        repeat(4) @(negedge clk);
        stable_next=dut.next_ones;
        #1 comparator_bit=1;
        #1;
        if (dut.next_ones !== stable_next)
            $fatal(1,"asynchronous comparator reaches measurement arithmetic");
        // Exercise changing input away from active edges. Digital simulation
        // checks structure/accounting, not physical metastability probability.
        for(i=0;i<10000;i=i+1) begin
            @(negedge clk);
            #1 comparator_bit=$random;
            @(posedge clk);
            #1;
            population=0;
            wide_population=0;
            for(j=0;j<64;j=j+1) population=population+dut.history[j];
            for(j=0;j<16;j=j+1) wide_population=wide_population+dut.history[j];
            if(dut.ones_count !== population || dut.ones_count>64)
                $fatal(1,"density history/count inconsistent");
            if(dut.wide_ones_count !== wide_population || dut.wide_ones_count>16)
                $fatal(1,"wide density history/count inconsistent");
            if(dut.sample_strobe && dut.wide_reconstructed_level !==
                (wide_population==16 ? 255 : wide_population*16))
                $fatal(1,"wide output scaling/strobe mismatch");
        end
        $display("PASS registered measurement: no async arithmetic; 10000 consistent history counts");
        $finish;
    end
endmodule
