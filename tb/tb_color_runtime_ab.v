`timescale 1ns/1ps
module tb_color_runtime_ab;
    reg clk=0, reset=1, enable=0;
    always #5 clk=~clk;
    ntsc_color_decoder #(.ENABLE_COLOR(1),.RUNTIME_COLOR(1)) dut(
        .clk(clk),.reset(reset),.color_enable(enable),.sample_level(8'd64),
        .chroma_level(8'd64),.hsync_pulse(1'b0),.vsync_pulse(1'b0));
    initial begin
        repeat(4) @(negedge clk); reset=0;
        force dut.color_locked=1;
        force dut.y_value=16'sd80;
        force dut.u_value=16'sd24;
        force dut.v_value=16'sd32;
        #1;
        if(dut.red_value!=80 || dut.green_value!=80 || dut.blue_value!=80)
            $fatal(1,"grayscale selection failed");
        enable=1; #1;
        if(dut.red_value!=120 || dut.green_value!=58 || dut.blue_value!=116)
            $fatal(1,"color selection failed");
        force dut.color_locked=0; #1;
        if(dut.red_value!=80 || dut.green_value!=80 || dut.blue_value!=80)
            $fatal(1,"unlocked grayscale fallback failed");
        $display("PASS same-engine runtime grayscale/color and burst-unlocked fallback");
        $finish;
    end
endmodule
