`timescale 1ns/1ps
module tb_raw_snapshot;
    reg clk = 0, reset = 1;
    reg [7:0] level = 8'ha5;
    integer i;
    always #5 clk = ~clk;
    nano4k_ntsc_hdmi #(.RAW_SNAPSHOT(1)) dut (
        .clk_27m(1'b0), .reset_n(1'b1), .video_p(1'b0), .video_n(1'b0));
    initial begin
        force dut.clk_sample_13m5 = clk;
        force dut.sample_reset = reset;
        force dut.decoder_level_hold = level;
        repeat (4) @(negedge clk);
        reset = 0;
        // Skip only the startup wait; use actual write counter and BSRAM RTL.
        force dut.raw_settle = 21'h1fffff;
        repeat (15360) @(negedge clk);
        if (!dut.raw_done) $fatal(1, "snapshot not complete");
        for (i=0; i<15360; i=i+1)
            if (dut.frame_store.frame_memory[i] !== 8'ha5)
                $fatal(1, "snapshot data/address/width error at %0d", i);
        level = 8'h5a;
        repeat (100) @(negedge clk);
        for (i=0; i<15360; i=i+1)
            if (dut.frame_store.frame_memory[i] !== 8'ha5)
                $fatal(1, "snapshot changed after completion");
        $display("PASS raw snapshot: all 15360 bytes written, full 8-bit data, frozen after completion");
        $finish;
    end
endmodule
