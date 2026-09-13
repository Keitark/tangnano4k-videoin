`timescale 1ns/1ps
// Diagnostic only: synthetic levels are illustrative, not measured voltages.
// Board primitives are left unelaborated with iverilog -i.
module tb_monochrome_audit;
    reg clk = 0;
    always #5 clk = ~clk;
    reg adc_clk = 0;
    always #0.625 adc_clk = ~adc_clk;
    reg [2:0] adc_div = 0;
    always @(posedge adc_clk) adc_div <= adc_div + 1'b1;
    wire sample_tick = (adc_div == 0);
    reg reset = 1;
    reg hsync = 0;
    reg [7:0] level = 100;
    reg [7:0] composite = 110;
    wire valid, done;
    wire [9:0] x;
    wire [15:0] rgb;
    integer polarity, line, pos, source_pos;
    integer bright_count, bright_sum, residual_pixels, residual_done;
    integer edges_default = 0, edges_lower = 0;
    integer mode = 0;

    ntsc_color_decoder #(.REQUIRE_FIELD_WINDOW(0), .ENABLE_COLOR(0),
        .TRACK_BLACK(1)) decoder (
        .clk(clk), .reset(reset), .sample_level(level), .hsync_pulse(hsync),
        .vsync_pulse(1'b0), .pixel_valid(valid), .pixel_x(x),
        .pixel_rgb565(rgb), .line_done(done));

    nano4k_ntsc_hdmi default_slicer (.clk_27m(1'b0), .reset_n(1'b1),
                                   .video_p(1'b0), .video_n(1'b0));
    nano4k_ntsc_hdmi #(.SYNC_THRESHOLD(75)) lower_slicer (
        .clk_27m(1'b0), .reset_n(1'b1), .video_p(1'b0), .video_n(1'b0));

    always @(posedge clk) begin
        #1;
        if (!reset && mode == 1 && valid && x >= 400 && x < 600) begin
            bright_sum = bright_sum + rgb[15:11];
            bright_count = bright_count + 1;
        end
        if (!reset && mode == 2) begin
            if (valid) residual_pixels = residual_pixels + 1;
            if (done) residual_done = residual_done + 1;
        end
        if (!reset && mode == 3) begin
            if (default_slicer.sync_rising) edges_default = edges_default + 1;
            if (lower_slicer.sync_rising) edges_lower = edges_lower + 1;
        end
    end

    initial begin
        force default_slicer.clk_adc_108m = adc_clk;
        force default_slicer.clk_sample_13m5 = clk;
        force default_slicer.adc_reset = reset;
        force default_slicer.sample_reset = reset;
        force default_slicer.reconstructed_level = composite;
        force default_slicer.sample_strobe = sample_tick;
        force lower_slicer.clk_adc_108m = adc_clk;
        force lower_slicer.clk_sample_13m5 = clk;
        force lower_slicer.adc_reset = reset;
        force lower_slicer.sample_reset = reset;
        force lower_slicer.reconstructed_level = composite;
        force lower_slicer.sample_strobe = sample_tick;

        // Identical ideal line timing, first normal then inverted amplitude.
        for (polarity = 0; polarity < 2; polarity = polarity + 1) begin
            reset = 1; mode = 0; hsync = 0;
            repeat (8) @(negedge clk);
            reset = 0; bright_count = 0; bright_sum = 0;
            for (line = 0; line < 12; line = line + 1) begin
                mode = (line >= 4) ? 1 : 0;
                for (pos = 0; pos < 858; pos = pos + 1) begin
                    @(negedge clk);
                    hsync = (pos == 0);
                    level = (pos >= 78 && pos < 789) ? 200 : 100;
                    if (polarity) level = 255 - level;
                end
            end
            $display("polarity=%0d bright_region_pixels=%0d mean_red5=%0d",
                     polarity, bright_count, bright_sum / bright_count);
        end

        // No sync, long enough for the decoder's line-position counter to wrap.
        @(negedge clk); hsync = 0; mode = 0;
        repeat (1000) @(negedge clk);
        residual_pixels = 0; residual_done = 0; mode = 2;
        repeat (6000) @(negedge clk);
        $display("after_sync_loss pixels=%0d line_done_pulses=%0d",
                 residual_pixels, residual_done);

        reset = 1; mode = 0;
        repeat (8) @(negedge clk);
        reset = 0; mode = 3;
        for (line = 0; line < 30; line = line + 1)
            for (source_pos = 0; source_pos < 858; source_pos = source_pos + 1) begin
                @(negedge clk);
                composite = (source_pos < 63) ? 40 : 110;
            end
        $display("valid_dark_composite rising_edges_default148=%0d comparison75=%0d",
                 edges_default, edges_lower);
        $display("AUDIT COMPLETE: observations only, production HDL unchanged");
        $finish;
    end
endmodule
