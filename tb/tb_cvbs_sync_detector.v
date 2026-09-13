`timescale 1ns/1ps
module tb_cvbs_sync_detector;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg sync_sample = 1'b1;
    wire hsync_pulse;
    wire vsync_pulse;
    wire line_locked;
    wire [12:0] measured_low_samples;
    wire [12:0] measured_line_samples;
    integer hsync_count = 0;
    integer vsync_count = 0;
    integer index;

    // 27 MHz, matching the Tang Nano 4K board oscillator.
    always #18.518 clk = ~clk;

    cvbs_sync_detector dut (
        .clk(clk),
        .reset(reset),
        .sync_sample(sync_sample),
        .hsync_pulse(hsync_pulse),
        .vsync_pulse(vsync_pulse),
        .line_locked(line_locked),
        .measured_low_samples(measured_low_samples),
        .measured_line_samples(measured_line_samples)
    );

    always @(posedge clk) begin
        if (hsync_pulse)
            hsync_count = hsync_count + 1;
        if (vsync_pulse)
            vsync_count = vsync_count + 1;
    end

    task emit_low_pulse;
        input integer low_samples;
        input integer total_samples;
        begin
            @(negedge clk);
            sync_sample = 1'b0;
            repeat (low_samples) @(posedge clk);
            @(negedge clk);
            sync_sample = 1'b1;
            repeat (total_samples - low_samples) @(posedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset = 1'b0;
        repeat (5) @(posedge clk);

        // Ten NTSC-like lines: 127 low samples in a 1716-sample line.
        for (index = 0; index < 10; index = index + 1)
            emit_low_pulse(127, 1716);

        if (hsync_count != 10)
            $fatal(1, "expected 10 hsync pulses, got %0d", hsync_count);
        if (!line_locked)
            $fatal(1, "line lock did not assert after stable lines");

        // A short picture-content excursion must not look like sync.
        emit_low_pulse(20, 1716);
        if (hsync_count != 10)
            $fatal(1, "short excursion was misclassified as hsync");

        // An NTSC-like vertical serration low interval is classified
        // separately and must not increment the horizontal count.
        emit_low_pulse(730, 900);
        if (vsync_count != 1)
            $fatal(1, "expected one vsync pulse, got %0d", vsync_count);
        if (hsync_count != 10)
            $fatal(1, "vertical pulse was misclassified as hsync");

        $display("PASS cvbs_sync_detector hsync=%0d vsync=%0d", hsync_count, vsync_count);
        $finish;
    end
endmodule
