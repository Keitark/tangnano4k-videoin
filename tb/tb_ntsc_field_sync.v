`timescale 1ns/1ps
module tb_ntsc_field_sync;
    reg clk=0, reset=1, sync_in=1;
    wire pulse;
    integer pulses=0, i;
    always #5 clk=~clk;
    ntsc_field_sync dut(.clk(clk),.reset(reset),.sync_in(sync_in),.field_pulse(pulse));
    always @(negedge clk) if(pulse) pulses=pulses+1;
    task interval;
        input integer low_length, total_length;
        begin
            @(negedge clk); sync_in=0;
            repeat(low_length) @(negedge clk);
            sync_in=1;
            repeat(total_length-low_length-1) @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk); reset=0;
        for(i=0;i<20;i=i+1) interval(64,858);
        if(pulses!=0) $fatal(1,"horizontal pulses mistaken for field");
        interval(350,429); interval(350,429); interval(350,429);
        if(pulses!=1) $fatal(1,"serration burst must emit one marker");
        for(i=0;i<261;i=i+1) interval(64,858);
        interval(760,858); interval(760,858); interval(760,858);
        if(pulses!=2) $fatal(1,"240p broad pulse field missing/duplicated");
        repeat(230000) @(negedge clk);
        interval(4000,4100);
        if(pulses!=2) $fatal(1,"stuck low mistaken for field");
        $display("PASS field sync: H rejection, serrations, 240p, holdoff, stuck-low rejection");
        $finish;
    end
endmodule
