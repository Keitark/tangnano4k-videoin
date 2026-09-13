module nano4k_cvbs_hdmi_auto_cal (
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
    reg [7:0] sample_reset_pipe;
    reg [7:0] pixel_reset_pipe;

    always @(posedge clk_adc_108m or negedge clocks_locked) begin
        if (!clocks_locked)
            adc_reset_pipe <= 8'b0;
        else
            adc_reset_pipe <= {adc_reset_pipe[6:0], 1'b1};
    end

    always @(posedge clk_sample_13m5 or negedge clocks_locked) begin
        if (!clocks_locked)
            sample_reset_pipe <= 8'b0;
        else
            sample_reset_pipe <= {sample_reset_pipe[6:0], 1'b1};
    end

    always @(posedge clk_pixel_25m2 or negedge clocks_locked) begin
        if (!clocks_locked)
            pixel_reset_pipe <= 8'b0;
        else
            pixel_reset_pipe <= {pixel_reset_pipe[6:0], 1'b1};
    end

    wire adc_reset = ~adc_reset_pipe[7];
    wire sample_reset = ~sample_reset_pipe[7];
    wire pixel_resetn = pixel_reset_pipe[7];

    reg [1:0] serializer_reset_pipe = 2'b0;
    always @(posedge clk_tmds_126m)
        serializer_reset_pipe <= {serializer_reset_pipe[0], pixel_resetn};
    wire serializer_resetn = serializer_reset_pipe[1];

    localparam [1:0] CAL_REFERENCE = 2'd0;
    localparam [1:0] SETTLE_REFERENCE = 2'd1;
    localparam [1:0] SEARCH_SYNC = 2'd2;
    localparam [1:0] SYNC_LOCKED = 2'd3;

    reg [1:0] calibration_state;
    reg [7:0] reference_density_sample;
    reg [7:0] sync_threshold;
    reg [13:0] reference_dwell;
    reg [17:0] threshold_dwell;
    reg stable_activity;
    reg stable_lock;
    reg activity_reset_pulse;
    reg sync_reset_pulse;

    wire [7:0] reconstructed_level;
    wire adc_activity;
    wire line_locked;

    // Reference search: reset the activity window for every code, ignore its
    // first half, then require activity to stay high throughout the second
    // half.  This selects the first stable code rather than a partial edge.
    always @(posedge clk_sample_13m5) begin
        if (sample_reset) begin
            calibration_state <= CAL_REFERENCE;
            reference_density_sample <= 8'd128;
            sync_threshold <= 8'd0;
            reference_dwell <= 14'b0;
            threshold_dwell <= 18'b0;
            stable_activity <= 1'b1;
            stable_lock <= 1'b1;
            activity_reset_pulse <= 1'b1;
            sync_reset_pulse <= 1'b1;
        end else begin
            activity_reset_pulse <= 1'b0;
            sync_reset_pulse <= 1'b0;

            case (calibration_state)
                CAL_REFERENCE: begin
                    reference_dwell <= reference_dwell + 1'b1;
                    if (reference_dwell[13] && !adc_activity)
                        stable_activity <= 1'b0;

                    if (&reference_dwell) begin
                        reference_dwell <= 14'b0;
                        if ((stable_activity && adc_activity) ||
                            (reference_density_sample == 8'hff)) begin
                            calibration_state <= SETTLE_REFERENCE;
                            stable_activity <= 1'b1;
                            activity_reset_pulse <= 1'b1;
                        end else begin
                            reference_density_sample <=
                                reference_density_sample + 1'b1;
                            stable_activity <= 1'b1;
                            activity_reset_pulse <= 1'b1;
                        end
                    end
                end

                SETTLE_REFERENCE: begin
                    reference_dwell <= reference_dwell + 1'b1;
                    if (&reference_dwell) begin
                        reference_dwell <= 14'b0;
                        threshold_dwell <= 18'b0;
                        sync_threshold <= 8'd0;
                        stable_lock <= 1'b1;
                        sync_reset_pulse <= 1'b1;
                        calibration_state <= SEARCH_SYNC;
                    end
                end

                SEARCH_SYNC: begin
                    threshold_dwell <= threshold_dwell + 1'b1;
                    // A transient detector assertion is not sufficient.  The
                    // candidate must remain locked throughout the latter half
                    // of the dwell before it is accepted.
                    if (threshold_dwell[17] && !line_locked)
                        stable_lock <= 1'b0;

                    if (&threshold_dwell) begin
                        threshold_dwell <= 18'b0;
                        if (stable_lock && line_locked) begin
                            calibration_state <= SYNC_LOCKED;
                        end else begin
                            sync_threshold <= sync_threshold + 1'b1;
                            stable_lock <= 1'b1;
                            sync_reset_pulse <= 1'b1;
                        end
                    end
                end

                default: begin
                    // Hold both calibrated values after line lock.
                    calibration_state <= SYNC_LOCKED;
                end
            endcase
        end
    end

    // Apply the sample-domain reference through a two-stage ADC-domain
    // synchronizer. Changes are millisecond-spaced, so transients settle long
    // before the activity decision window.
    reg [7:0] reference_meta_adc;
    reg [7:0] reference_sync_adc;
    always @(posedge clk_adc_108m) begin
        if (adc_reset) begin
            reference_meta_adc <= 8'd128;
            reference_sync_adc <= 8'd128;
        end else begin
            reference_meta_adc <= reference_density_sample;
            reference_sync_adc <= reference_meta_adc;
        end
    end

    wire sample_strobe;
    lvds_delta_adc_runtime adc (
        .clk_adc(clk_adc_108m),
        .reset(adc_reset),
        .video_p(video_p),
        .video_n(video_n),
        .reference_density(reference_sync_adc),
        .feedback_out(adc_feedback),
        .reconstructed_level(reconstructed_level),
        .sample_strobe(sample_strobe)
    );

    adc_activity_monitor activity_monitor (
        .clk(clk_sample_13m5),
        .reset(sample_reset | activity_reset_pulse),
        .level(reconstructed_level),
        .activity(adc_activity)
    );

    wire sync_sample = reconstructed_level > sync_threshold;
    wire hsync_pulse;
    wire vsync_pulse;
    wire [11:0] measured_low_samples;
    wire [11:0] measured_line_samples;

    cvbs_sync_detector #(
        .COUNTER_WIDTH(12),
        .HSYNC_MIN_SAMPLES(50),
        .HSYNC_MAX_SAMPLES(80),
        .VSYNC_MIN_SAMPLES(250),
        .LINE_MIN_SAMPLES(840),
        .LINE_MAX_SAMPLES(875),
        .LOCK_LINES(8)
    ) sync_detector (
        .clk(clk_sample_13m5),
        .reset(sample_reset | sync_reset_pulse),
        .sync_sample(sync_sample),
        .hsync_pulse(hsync_pulse),
        .vsync_pulse(vsync_pulse),
        .line_locked(line_locked),
        .measured_low_samples(measured_low_samples),
        .measured_line_samples(measured_line_samples)
    );

    hdmi_diag_tx hdmi (
        .clk_pixel(clk_pixel_25m2),
        .clk_5x_pixel(clk_tmds_126m),
        .resetn(pixel_resetn),
        .serial_resetn(serializer_resetn),
        .adc_level_async(reconstructed_level),
        .adc_activity_async(adc_activity),
        .line_locked_async(line_locked),
        .sync_low_async(~sync_sample),
        .reference_density_async(reference_sync_adc),
        .sync_threshold_async(sync_threshold),
        .tmds_clk_n(tmds_clk_n),
        .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n),
        .tmds_d_p(tmds_d_p)
    );

    assign led = ~line_locked;
endmodule
