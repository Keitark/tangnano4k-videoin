module nano4k_cvbs_hdmi_closed_loop_sweep (
    input  wire       clk_27m,
    input  wire       reset_n,
    input  wire       video_p,
    input  wire       video_n,
    output wire       adc_feedback,
    output wire       led,
    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);
    wire clk_adc_108m;
    wire clk_sample_13m5;
    wire clk_tmds_126m;
    wire clk_pixel_25m2;
    wire clocks_locked;

    nano4k_cvbs_hdmi_clocks clocks (
        .clk_27m(clk_27m),
        .reset(~reset_n),
        .clk_adc_108m(clk_adc_108m),
        .clk_sample_13m5(clk_sample_13m5),
        .clk_tmds_126m(clk_tmds_126m),
        .clk_pixel_25m2(clk_pixel_25m2),
        .locked(clocks_locked)
    );

    reg [7:0] adc_reset_pipe;
    reg [7:0] pixel_reset_pipe;

    always @(posedge clk_adc_108m or negedge clocks_locked) begin
        if (!clocks_locked)
            adc_reset_pipe <= 8'b0;
        else
            adc_reset_pipe <= {adc_reset_pipe[6:0], 1'b1};
    end

    always @(posedge clk_pixel_25m2 or negedge clocks_locked) begin
        if (!clocks_locked)
            pixel_reset_pipe <= 8'b0;
        else
            pixel_reset_pipe <= {pixel_reset_pipe[6:0], 1'b1};
    end

    wire adc_reset = ~adc_reset_pipe[7];
    wire pixel_resetn = pixel_reset_pipe[7];

    reg [1:0] serializer_reset_pipe = 2'b0;
    always @(posedge clk_tmds_126m)
        serializer_reset_pipe <= {serializer_reset_pipe[0], pixel_resetn};
    wire serializer_resetn = serializer_reset_pipe[1];

    wire [7:0] reconstructed_level;
    wire [7:0] filtered_level;
    wire sample_strobe;

    // Original closed-loop topology: the normalized comparator bit is driven
    // directly back through pin 16 and the external 2 kohm / capacitor node.
    lvds_delta_adc #(
        .INVERT_COMPARATOR(0),
        .USE_REFERENCE_DSM(0)
    ) adc (
        .clk_adc(clk_adc_108m),
        .reset(adc_reset),
        .video_p(video_p),
        .video_n(video_n),
        .feedback_out(adc_feedback),
        .reconstructed_level(reconstructed_level),
        .sample_strobe(sample_strobe)
    );

    // Apply a first-order 1/64 low-pass to consecutive 13.5 MHz density
    // estimates.  Its approximately 4.7 us time constant is the strongest
    // smoothing test that still responds within one NTSC horizontal-sync
    // pulse.  The original 108 MHz comparator loop remains untouched.
    adc_level_iir #(
        .FILTER_SHIFT(6)
    ) level_filter (
        .clk(clk_adc_108m),
        .reset(adc_reset),
        .sample_enable(sample_strobe),
        .level_in(reconstructed_level),
        .level_out(filtered_level)
    );

    wire adc_activity;
    adc_activity_monitor #(
        .USE_SAMPLE_ENABLE(1)
    ) activity_monitor (
        .clk(clk_adc_108m),
        .reset(adc_reset),
        .sample_enable(sample_strobe),
        .level(filtered_level),
        .activity(adc_activity)
    );

    wire search_locked = 1'b0;
    reg sync_sample;
    reg [7:0] slicer_level;
    reg slicer_below_fall;
    reg slicer_above_rise;

    reg sync_probe_meta;
    reg sync_probe_in;
    reg sync_probe_previous;
    reg [11:0] probe_period_count;
    reg probe_debounce_done;
    reg period_event;
    reg period_code_valid;
    reg [7:0] period_code;
    reg [20:0] center_dwell;
    reg center_dwell_msb_previous;
    reg center_reset_pulse;
    reg [7:0] hysteresis_fall_threshold;
    reg [7:0] hysteresis_rise_threshold;
    reg [7:0] period_histogram_bin;
    reg [7:0] period_histogram_low;
    reg [7:0] period_histogram_high;
    reg [7:0] center_hit_count;
    reg [7:0] reported_center;
    reg [7:0] reported_center_hits;
    wire probe_sync_rising = sync_probe_in & ~sync_probe_previous;

    // Hysteretic sync slicer. Once low, the reconstructed level must cross
    // the upper threshold before another rising edge can be reported.
    always @(posedge clk_adc_108m) begin
        if (adc_reset | center_reset_pulse) begin
            sync_sample <= 1'b1;
            slicer_level <= 8'b0;
            slicer_below_fall <= 1'b0;
            slicer_above_rise <= 1'b0;
        end else if (sample_strobe) begin
            slicer_level <= filtered_level;
            slicer_below_fall <= slicer_level < hysteresis_fall_threshold;
            slicer_above_rise <= slicer_level > hysteresis_rise_threshold;
            if (sync_sample && slicer_below_fall)
                sync_sample <= 1'b0;
            else if (!sync_sample && slicer_above_rise)
                sync_sample <= 1'b1;
        end
    end

    // Independent line-period probe. Crossings closer than 700 samples
    // (51.9 us) are rejected. The previous 400-sample guard admitted a strong
    // false edge near half the 63.56 us NTSC line period. Each accepted interval
    // is reported directly; pulse width is not part of this diagnostic.
    always @(posedge clk_adc_108m) begin
        if (adc_reset | center_reset_pulse) begin
            sync_probe_meta <= 1'b1;
            sync_probe_in <= 1'b1;
            sync_probe_previous <= 1'b1;
            probe_period_count <= 12'b0;
            probe_debounce_done <= 1'b0;
            period_event <= 1'b0;
            period_code_valid <= 1'b0;
            period_code <= 8'b0;
        end else if (sample_strobe) begin
            sync_probe_meta <= sync_sample;
            sync_probe_in <= sync_probe_meta;
            sync_probe_previous <= sync_probe_in;
            probe_debounce_done <= probe_period_count >= 12'd700;
            period_event <= 1'b0;

            if (!(&probe_period_count))
                probe_period_count <= probe_period_count + 1'b1;

            if (probe_sync_rising && probe_debounce_done) begin
                // Encode interval/8. NTSC's nominal 857.5 samples maps to
                // code 107. Intervals above the encodable range are excluded
                // from the histogram rather than folded into the top bin.
                period_event <= 1'b1;
                period_code_valid <= !probe_period_count[11];
                period_code <= probe_period_count[10:3];
                probe_period_count <= 12'b0;
            end
        end
    end

    // Sweep hysteresis centers 16 through 240 in steps of two. Each 19.4 ms
    // dwell counts only intervals in codes 104..110, bracketing NTSC's nominal
    // 857.5-sample line at code 107. HDMI cyan reports the completed threshold
    // center and magenta reports its hit count. A clean center should approach
    // the roughly 305 lines present in one dwell (the counter saturates at 255).
    always @(posedge clk_adc_108m) begin
        if (adc_reset) begin
            center_dwell <= 21'b0;
            center_dwell_msb_previous <= 1'b0;
            center_reset_pulse <= 1'b1;
            hysteresis_fall_threshold <= 8'd8;
            hysteresis_rise_threshold <= 8'd24;
            period_histogram_bin <= 8'd16;
            period_histogram_low <= 8'd104;
            period_histogram_high <= 8'd110;
            center_hit_count <= 8'b0;
            reported_center <= 8'd16;
            reported_center_hits <= 8'b0;
        end else begin
            center_dwell <= center_dwell + 1'b1;
            center_dwell_msb_previous <= center_dwell[20];
            center_reset_pulse <= 1'b0;

            if (!center_reset_pulse && sample_strobe && period_event &&
                period_code_valid &&
                (period_code >= period_histogram_low) &&
                (period_code <= period_histogram_high) &&
                !(&center_hit_count))
                center_hit_count <= center_hit_count + 1'b1;

            if (center_dwell[20] && !center_dwell_msb_previous) begin
                reported_center <= period_histogram_bin;
                reported_center_hits <= center_hit_count;
                center_hit_count <= 8'b0;
                if (period_histogram_bin == 8'd240) begin
                    period_histogram_bin <= 8'd16;
                    hysteresis_fall_threshold <= 8'd8;
                    hysteresis_rise_threshold <= 8'd24;
                end else begin
                    period_histogram_bin <= period_histogram_bin + 8'd2;
                    hysteresis_fall_threshold <=
                        hysteresis_fall_threshold + 8'd2;
                    hysteresis_rise_threshold <=
                        hysteresis_rise_threshold + 8'd2;
                end
                center_reset_pulse <= 1'b1;
            end
        end
    end

    hdmi_diag_tx hdmi (
        .clk_pixel(clk_pixel_25m2),
        .clk_5x_pixel(clk_tmds_126m),
        .resetn(pixel_resetn),
        .serial_resetn(serializer_resetn),
        .adc_level_async(filtered_level),
        .adc_activity_async(adc_activity),
        // This period-distribution diagnostic intentionally does not assert
        // line lock.
        .line_locked_async(search_locked),
        .sync_low_async(~sync_sample),
        // Magenta reports nominal-period hits; cyan reports threshold center.
        .reference_density_async(reported_center_hits),
        .sync_threshold_async(reported_center),
        .tmds_clk_n(tmds_clk_n),
        .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n),
        .tmds_d_p(tmds_d_p)
    );

    assign led = ~search_locked;
endmodule
