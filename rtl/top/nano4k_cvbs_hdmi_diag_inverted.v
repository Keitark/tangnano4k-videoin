module nano4k_cvbs_hdmi_diag_inverted (
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

    always @(posedge clk_pixel_25m2 or negedge clocks_locked) begin
        if (!clocks_locked)
            pixel_reset_pipe <= 8'b0;
        else
            pixel_reset_pipe <= {pixel_reset_pipe[6:0], 1'b1};
    end

    always @(posedge clk_sample_13m5 or negedge clocks_locked) begin
        if (!clocks_locked)
            sample_reset_pipe <= 8'b0;
        else
            sample_reset_pipe <= {sample_reset_pipe[6:0], 1'b1};
    end

    wire adc_reset = ~adc_reset_pipe[7];
    wire sample_reset = ~sample_reset_pipe[7];
    wire pixel_resetn = pixel_reset_pipe[7];

    reg [1:0] serializer_reset_pipe = 2'b0;
    always @(posedge clk_tmds_126m)
        serializer_reset_pipe <= {serializer_reset_pipe[0], pixel_resetn};
    wire serial_resetn = serializer_reset_pipe[1];
    wire [7:0] reconstructed_level;
    wire sample_strobe;

    lvds_delta_adc #(
        .INVERT_COMPARATOR(1)
    ) adc (
        .clk_adc(clk_adc_108m),
        .reset(adc_reset),
        .video_p(video_p),
        .video_n(video_n),
        .feedback_out(adc_feedback),
        .reconstructed_level(reconstructed_level),
        .sample_strobe(sample_strobe)
    );

    wire adc_activity;
    adc_activity_monitor activity_monitor (
        .clk(clk_sample_13m5),
        .reset(sample_reset),
        .level(reconstructed_level),
        .activity(adc_activity)
    );

    wire sync_sample = reconstructed_level > 8'd28;
    wire hsync_pulse;
    wire vsync_pulse;
    wire line_locked;
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
        .reset(sample_reset),
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
        .serial_resetn(serial_resetn),
        .adc_level_async(reconstructed_level),
        .adc_activity_async(adc_activity),
        .line_locked_async(line_locked),
        .sync_low_async(~sync_sample),
        .reference_density_async(8'd0),
        .sync_threshold_async(8'd28),
        .tmds_clk_n(tmds_clk_n),
        .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n),
        .tmds_d_p(tmds_d_p)
    );

    assign led = ~line_locked;
endmodule
