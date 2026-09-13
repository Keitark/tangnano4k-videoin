`timescale 1ns/1ps
// Exercise the actual top-level HPLL with an ideal sliced sync input.
// -i leaves unrelated analog/PLL/HDMI modules unelaborated; force only the
// sample-domain inputs. This tests digital line timing, not analog capture.
module tb_ntsc_hpll;
    reg clk = 0;
    reg reset = 1;
    reg edge_in = 0;
    integer cycle = 0;
    integer previous_pulse = -1;
    integer pulses = 0;
    integer bad_intervals = 0;
    integer minimum_interval = 100000;
    integer maximum_interval = 0;
    integer gap;
    integer line;
    integer period;
    integer scenario;
    integer locked_observations = 0;
    integer completed_lines = 0;
    integer pixels_this_line = 0;
    integer bad_pixel_lines = 0;
    integer failures = 0;
    always #5 clk = ~clk;

    nano4k_ntsc_hdmi dut (.clk_27m(1'b0), .reset_n(1'b1),
                          .video_p(1'b0), .video_n(1'b0));

    always @(posedge clk) begin
        #1;
        cycle = cycle + 1;
        if (!reset && dut.qualified_lock_seen)
            locked_observations = locked_observations + 1;
        if (!reset && dut.hsync_pulse)
            pixels_this_line = 0;
        if (!reset && dut.decoded_pixel_valid)
            pixels_this_line = pixels_this_line + 1;
        if (!reset && dut.decoded_line_done && previous_pulse >= 0) begin
            completed_lines = completed_lines + 1;
            if (pixels_this_line != 640)
                bad_pixel_lines = bad_pixel_lines + 1;
        end
        if (!reset && dut.hsync_pulse) begin
            pulses = pulses + 1;
            if (previous_pulse >= 0) begin
                gap = cycle - previous_pulse;
                if (gap < minimum_interval) minimum_interval = gap;
                if (gap > maximum_interval) maximum_interval = gap;
                // Source periods 857..859 with bounded jitter: a second
                // pulse near the boundary must never become another line.
                if (gap < 820 || gap > 900) begin
                    bad_intervals = bad_intervals + 1;
                    if (bad_intervals <= 4)
                        $display("BAD line interval=%0d at cycle=%0d", gap, cycle);
                end
            end
            previous_pulse = cycle;
        end
    end

    task drive_interval;
        input integer ticks;
        input integer present;
        begin
            @(negedge clk); edge_in = present;
            @(negedge clk); edge_in = 0;
            repeat (ticks - 2) @(negedge clk);
        end
    endtask

    initial begin
        force dut.clk_sample_13m5 = clk;
        force dut.sample_reset = reset;
        force dut.qualified_sync_rising = edge_in;
        force dut.decoder_level_hold = 8'd100;
        for (scenario = 0; scenario < 3; scenario = scenario + 1) begin
            reset = 1;
            edge_in = 0;
            repeat (4) @(negedge clk);
            previous_pulse = -1;
            pulses = 0;
            bad_intervals = 0;
            locked_observations = 0;
            completed_lines = 0;
            pixels_this_line = 0;
            bad_pixel_lines = 0;
            minimum_interval = 100000;
            maximum_interval = 0;
            reset = 0;
            period = 857 + scenario;
            for (line = 0; line < 140; line = line + 1) begin
                // Three missing lines test flywheel continuity; a temporary
                // phase displacement tests both sides of the wrap boundary.
                if (line == 35) drive_interval(period + 8, 1);
                else if (line == 65) drive_interval(period - 8, 1);
                else drive_interval(period, !(line >= 90 && line < 93));
            end
            $display("period=%0d pulses=%0d min=%0d max=%0d bad=%0d lock_ticks=%0d completed_lines=%0d bad_pixel_lines=%0d",
                     period, pulses, minimum_interval, maximum_interval,
                     bad_intervals, locked_observations, completed_lines,
                     bad_pixel_lines);
            if (bad_intervals != 0 || pulses < 130 || pulses > 140 ||
                locked_observations == 0 || completed_lines < 130 ||
                bad_pixel_lines != 0)
                failures = failures + 1;
        end
        if (failures != 0)
            $fatal(1, "HPLL cadence / complete-picture-line failures: %0d", failures);
        $display("PASS ntsc_hpll cadence, early/late phase, and missing-sync holdover");
        $finish;
    end
endmodule
