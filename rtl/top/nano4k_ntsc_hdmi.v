module nano4k_ntsc_hdmi #(
    parameter integer SYNC_THRESHOLD = 46,
    parameter integer SOURCE_FIELD_SYNC = 0,
    parameter integer RUNTIME_PROBE = 0,
    parameter integer PROBE_CYCLE_ONCE = 0,
    parameter integer FRAME_WIDTH = 128,
    parameter integer WIDE_PICTURE = 0,
    parameter integer BURST_PROBE = 0,
    parameter integer COLOR_OUTPUT = 0,
    parameter integer COLOR_DECODE = COLOR_OUTPUT,
    parameter integer RUNTIME_COLOR = 0,
    parameter integer LINE_OUTPUT = 0,
    parameter integer LINE_WIDTH = 320,
    parameter integer CLEAN_CHROMA = 0,
    parameter integer WIDE_CIC2 = 0,
    parameter integer RAW_SNAPSHOT = 0
) (
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
    reg [7:0] serial_reset_pipe;

    always @(posedge clk_adc_108m or negedge clocks_locked) begin
        if (!clocks_locked) adc_reset_pipe <= 0;
        else adc_reset_pipe <= {adc_reset_pipe[6:0], 1'b1};
    end
    always @(posedge clk_sample_13m5 or negedge clocks_locked) begin
        if (!clocks_locked) sample_reset_pipe <= 0;
        else sample_reset_pipe <= {sample_reset_pipe[6:0], 1'b1};
    end
    always @(posedge clk_pixel_25m2 or negedge clocks_locked) begin
        if (!clocks_locked) pixel_reset_pipe <= 0;
        else pixel_reset_pipe <= {pixel_reset_pipe[6:0], 1'b1};
    end
    always @(posedge clk_tmds_126m or negedge clocks_locked) begin
        if (!clocks_locked) serial_reset_pipe <= 0;
        else serial_reset_pipe <= {serial_reset_pipe[6:0], 1'b1};
    end

    wire adc_reset = ~adc_reset_pipe[7];
    wire sample_reset = ~sample_reset_pipe[7];
    wire pixel_resetn = pixel_reset_pipe[7];
    wire serial_resetn = serial_reset_pipe[7];

    wire [7:0] reconstructed_level;
    wire [7:0] wide_reconstructed_level;
    // Split the reconstructed composite signal into independent processing
    // paths: a narrow-band sync path and a coherent picture-level path.
    wire [7:0] sync_filtered_level;
    wire sample_strobe;
    reg sample_clock_adc_d;
    reg [7:0] decoder_level_hold;
    reg [7:0] burst_level_hold;
    lvds_delta_adc #(.WIDE_CIC2(WIDE_CIC2)) adc (
        .clk_adc(clk_adc_108m),
        .reset(adc_reset),
        .video_p(video_p),
        .video_n(video_n),
        .feedback_out(adc_feedback),
        .reconstructed_level(reconstructed_level),
        .wide_reconstructed_level(wide_reconstructed_level),
        .sample_strobe(sample_strobe)
    );

    // After registering the ADC measurement input, the 2026-09-13 snapshot
    // shows sync near code 28 and porch near 64 (HDMI ramp-calibrated).
    // Center 46 gives hysteresis 38/54 between those measured levels.
    adc_level_iir #(
        // 1/16 is the bounded midpoint between the over-smoothed 1/64 test
        // and the noise-sensitive 1/8 test.
        .FILTER_SHIFT(4)
    ) sync_level_filter (
        .clk(clk_adc_108m),
        .reset(adc_reset),
        .sample_enable(sample_strobe),
        .level_in(reconstructed_level),
        .level_out(sync_filtered_level)
    );

    // Coherent 108 MHz -> 13.5 MHz multi-bit transfer. Capture the filtered
    // byte on the slow clock's falling edge as observed in the ADC domain, so
    // it remains stable for half a slow-clock period before decoder sampling.
    always @(posedge clk_adc_108m) begin
        if (adc_reset) begin
            sample_clock_adc_d <= 1'b0;
            decoder_level_hold <= 8'b0;
            burst_level_hold <= 8'b0;
        end else begin
            sample_clock_adc_d <= clk_sample_13m5;
            if (sample_clock_adc_d && !clk_sample_13m5) begin
                decoder_level_hold <= WIDE_PICTURE ? wide_reconstructed_level : reconstructed_level;
                burst_level_hold <= wide_reconstructed_level;
            end
        end
    end

    localparam [7:0] SYNC_FALL_THRESHOLD = SYNC_THRESHOLD[7:0] - 8'd8;
    localparam [7:0] SYNC_RISE_THRESHOLD = SYNC_THRESHOLD[7:0] + 8'd8;
    reg sync_sample;
    reg [7:0] slicer_level;
    reg slicer_below_fall;
    reg slicer_above_rise;

    always @(posedge clk_adc_108m) begin
        if (adc_reset) begin
            sync_sample <= 1'b1;
            slicer_level <= 8'b0;
            slicer_below_fall <= 1'b0;
            slicer_above_rise <= 1'b0;
        end else if (sample_strobe) begin
            slicer_level <= sync_filtered_level;
            slicer_below_fall <= slicer_level < SYNC_FALL_THRESHOLD;
            slicer_above_rise <= slicer_level > SYNC_RISE_THRESHOLD;
            if (sync_sample && slicer_below_fall)
                sync_sample <= 1'b0;
            else if (!sync_sample && slicer_above_rise)
                sync_sample <= 1'b1;
        end
    end

    // Reject another rising edge for 700 sample clocks (about 51.9 us). The
    // lower sync-only threshold, rather than a later guard, now removes active
    // picture crossings while preserving the nominal 63.56 us transition.
    // histogramming showed that this removes the false half-line transition
    // while retaining the cluster around the 63.56 us NTSC line period.
    reg sync_meta;
    reg sync_in;
    reg sync_previous;
    reg [7:0] sync_low_width;
    reg [7:0] last_sync_low_width;
    reg [9:0] edge_guard_count;
    // Horizontal digital PLL. Phase and period are Q10.4 sample counts so the
    // integral path can trim the 858-sample NTSC line period fractionally.
    localparam [13:0] HPLL_PERIOD_INITIAL_Q4 = 14'd13728; // 858 * 16
    localparam [13:0] HPLL_PERIOD_MIN_Q4 = 14'd13440;     // 840 * 16
    localparam [13:0] HPLL_PERIOD_MAX_Q4 = 14'd14016;     // 876 * 16
    localparam [13:0] HPLL_EARLY_WINDOW_Q4 = 14'd12960;   // 810 * 16
    localparam [13:0] HPLL_LATE_WINDOW_Q4 = 14'd768;      //  48 * 16
    localparam [9:0] HPLL_ACQUIRE_MIN = 10'd820;
    localparam [9:0] HPLL_ACQUIRE_MAX = 10'd900;
    reg [13:0] line_phase_q4;
    reg [13:0] line_period_q4;
    reg line_clock_running;
    reg acquisition_armed;
    reg acquisition_interval_seen;
    reg [4:0] hpll_lock_score;
    reg [4:0] hpll_miss_count;
    reg hsync_pulse;
    reg qualified_lock_seen;
    reg signed [8:0] hpll_last_error_samples;
    wire sync_rising = sync_in & ~sync_previous;
    // The filtered sync path is independent from the coherent picture path.
    // Pulse width remains telemetry-only because the reduced front end can
    // shorten or merge the apparent low interval; interval/phase qualification
    // and the flywheel HPLL decide whether an edge can steer line timing.
    wire qualified_sync_rising = sync_rising;
    wire source_field_pulse;
    wire vsync_pulse = SOURCE_FIELD_SYNC ? source_field_pulse : 1'b0;
    ntsc_field_sync field_detector (
        .clk(clk_sample_13m5), .reset(sample_reset),
        .sync_in(sync_in), .field_pulse(source_field_pulse));

    wire signed [14:0] hpll_phase_signed_q4 =
        $signed({1'b0, line_phase_q4});
    wire signed [14:0] hpll_period_signed_q4 =
        $signed({1'b0, line_period_q4});
    // An edge just before the next wrap is early (negative error); an edge
    // just after the previous wrap is late (positive error).
    wire signed [14:0] hpll_phase_error_q4 =
        (line_phase_q4 < (line_period_q4 >> 1)) ?
        hpll_phase_signed_q4 :
        (hpll_phase_signed_q4 - hpll_period_signed_q4);
    // Cadence acquisition supplies the correct line family. Qualified edges
    // steer phase gently with Kp = 1/4, while the period loop retains the
    // gentle Ki = 1/128 gain so threshold jitter cannot drive its estimate.
    wire signed [15:0] hpll_period_candidate_q4 =
        $signed({1'b0, line_period_q4}) +
        (hpll_phase_error_q4 >>> 7);
    wire [14:0] hpll_abs_phase_error_q4 = hpll_phase_error_q4[14] ?
        -hpll_phase_error_q4 : hpll_phase_error_q4;
    wire hpll_edge_in_window =
        (line_phase_q4 >= HPLL_EARLY_WINDOW_Q4) ||
        (line_phase_q4 <= HPLL_LATE_WINDOW_Q4);
    wire hpll_accept_edge = qualified_sync_rising &&
        (edge_guard_count >= 10'd760) &&
        (edge_guard_count <= 10'd950) &&
        hpll_edge_in_window && (hpll_abs_phase_error_q4 <= 15'd384);
    // Keep the shift in a signed expression. Combining >>> with the unsigned
    // phase register changes negative corrections into logical right shifts.
    wire signed [14:0] hpll_phase_correction_q4 =
        hpll_accept_edge ? (hpll_phase_error_q4 >>> 2) : 15'sd0;
    wire signed [15:0] hpll_phase_next_q4 =
        $signed({2'b00, line_phase_q4}) + 16'sd16 -
        $signed({hpll_phase_correction_q4[14], hpll_phase_correction_q4});
    wire signed [15:0] hpll_phase_wrapped_q4 =
        hpll_phase_next_q4 - $signed({2'b00, line_period_q4});

    always @(posedge clk_sample_13m5) begin
        if (sample_reset) begin
            sync_meta <= 1'b1;
            sync_in <= 1'b1;
            sync_previous <= 1'b1;
            sync_low_width <= 8'b0;
            last_sync_low_width <= 8'b0;
            edge_guard_count <= 10'b0;
            line_phase_q4 <= 14'b0;
            line_period_q4 <= HPLL_PERIOD_INITIAL_Q4;
            line_clock_running <= 1'b0;
            acquisition_armed <= 1'b0;
            acquisition_interval_seen <= 1'b0;
            hpll_lock_score <= 5'b0;
            hpll_miss_count <= 5'b0;
            hsync_pulse <= 1'b0;
            qualified_lock_seen <= 1'b0;
            hpll_last_error_samples <= 9'sd0;
        end else begin
            sync_meta <= sync_sample;
            sync_in <= sync_meta;
            sync_previous <= sync_in;
            hsync_pulse <= 1'b0;

            if (!sync_in) begin
                if (!(&sync_low_width))
                    sync_low_width <= sync_low_width + 1'b1;
            end else if (sync_rising) begin
                // Always expose the observed width for hardware diagnosis;
                // qualification below still decides whether it can steer the
                // HPLL.
                last_sync_low_width <= sync_low_width;
                sync_low_width <= 8'b0;
            end

            if (!line_clock_running) begin
                // Acquisition needs three rising edges with two consecutive
                // NTSC-like intervals. Short picture transitions between them
                // are ignored, so one arbitrary edge cannot start the HPLL.
                if (!acquisition_armed) begin
                    edge_guard_count <= 10'b0;
                    if (qualified_sync_rising) begin
                        acquisition_armed <= 1'b1;
                        acquisition_interval_seen <= 1'b0;
                    end
                end else begin
                    if (!(&edge_guard_count))
                        edge_guard_count <= edge_guard_count + 1'b1;

                    if (qualified_sync_rising &&
                        (edge_guard_count >= HPLL_ACQUIRE_MIN) &&
                        (edge_guard_count <= HPLL_ACQUIRE_MAX)) begin
                        edge_guard_count <= 10'b0;
                        if (acquisition_interval_seen) begin
                            hsync_pulse <= 1'b1;
                            line_phase_q4 <= 14'b0;
                            line_period_q4 <= HPLL_PERIOD_INITIAL_Q4;
                            line_clock_running <= 1'b1;
                            acquisition_armed <= 1'b0;
                            acquisition_interval_seen <= 1'b0;
                            hpll_lock_score <= 5'd0;
                            hpll_miss_count <= 5'd0;
                            qualified_lock_seen <= 1'b0;
                        end else begin
                            acquisition_interval_seen <= 1'b1;
                        end
                    end else if (edge_guard_count > HPLL_ACQUIRE_MAX) begin
                        // A late edge can immediately become the first edge of
                        // a new cadence trial; otherwise wait for one.
                        acquisition_armed <= qualified_sync_rising;
                        acquisition_interval_seen <= 1'b0;
                        edge_guard_count <= 10'b0;
                    end
                end
            end else begin
                if (!(&edge_guard_count))
                    edge_guard_count <= edge_guard_count + 1'b1;

                // The oscillator is the sole line-start source after initial
                // acquisition. Measured edges steer phase/period, never emit
                // a second line start next to a predicted boundary. Advance
                // through missing-edge bookkeeping as well as normal cycles.
                if (hpll_phase_next_q4 >= $signed({2'b00, line_period_q4})) begin
                    hsync_pulse <= 1'b1;
                    line_phase_q4 <= hpll_phase_wrapped_q4[13:0];
                end else begin
                    line_phase_q4 <= hpll_phase_next_q4[13:0];
                end

                // Flywheel through as many as fifteen missing sync edges. The
                // predicted line clock continues; fold the interval guard by
                // one estimated period so a valid edge on the following line
                // can phase-correct the HPLL. The measured period is stable at
                // 857..858 samples, so a bounded 16-line holdover prevents
                // sparse comparator misses from forcing constant reacquisition.
                if (edge_guard_count > 10'd950) begin
                    if (hpll_miss_count < 5'd15) begin
                        edge_guard_count <= edge_guard_count -
                                            line_period_q4[13:4];
                        hpll_miss_count <= hpll_miss_count + 1'b1;
                    end else begin
                        line_clock_running <= 1'b0;
                        edge_guard_count <= 10'b0;
                        line_phase_q4 <= 14'b0;
                        line_period_q4 <= HPLL_PERIOD_INITIAL_Q4;
                        acquisition_armed <= 1'b0;
                        acquisition_interval_seen <= 1'b0;
                        hpll_lock_score <= 5'b0;
                        hpll_miss_count <= 5'b0;
                        qualified_lock_seen <= 1'b0;
                        hpll_last_error_samples <= 9'sd0;
                    end
                end else if (hpll_accept_edge) begin
                    edge_guard_count <= 10'b0;
                    hpll_miss_count <= 5'd0;
                    hpll_last_error_samples <= hpll_phase_error_q4[12:4];
                    if (hpll_period_candidate_q4 <
                        $signed({1'b0, HPLL_PERIOD_MIN_Q4}))
                        line_period_q4 <= HPLL_PERIOD_MIN_Q4;
                    else if (hpll_period_candidate_q4 >
                             $signed({1'b0, HPLL_PERIOD_MAX_Q4}))
                        line_period_q4 <= HPLL_PERIOD_MAX_Q4;
                    else
                        line_period_q4 <= hpll_period_candidate_q4[13:0];

                    // Region-based confidence: the camera-free hardware
                    // capture places over 91% of accepted edges within +/-16
                    // samples. Accumulate those edges and use hysteresis so an
                    // occasional valid edge in the outer +/-24 region does not
                    // erase horizontal lock.
                    if (hpll_abs_phase_error_q4 <= 15'd256) begin
                        if (hpll_lock_score < 5'd16)
                            hpll_lock_score <= hpll_lock_score + 1'b1;
                        if (hpll_lock_score >= 5'd7)
                            qualified_lock_seen <= 1'b1;
                    end else if (hpll_abs_phase_error_q4 >= 15'd384) begin
                        hpll_lock_score <= 5'd0;
                        qualified_lock_seen <= 1'b0;
                    end else begin
                        if (hpll_lock_score != 0)
                            hpll_lock_score <= hpll_lock_score - 1'b1;
                        if (hpll_lock_score <= 5'd2)
                            qualified_lock_seen <= 1'b0;
                    end
                end

                if (&edge_guard_count) begin
                    hpll_lock_score <= 5'd0;
                    qualified_lock_seen <= 1'b0;
                end
            end
        end
    end

    wire decoded_pixel_valid;
    wire [9:0] decoded_pixel_x;
    wire [15:0] decoded_pixel_rgb565;
    wire decoded_line_done;
    wire decoded_field_toggle;
    wire color_locked;
    wire [7:0] debug_black_level;
    wire [7:0] debug_luma_level;
    reg [26:0] color_mode_timer;
    reg color_mode_requested, color_mode_active;
    reg [7:0] field_min, field_max, field_h_count, field_line_count;
    reg [31:0] source_field_status;
    always @(posedge clk_sample_13m5) begin
        if(sample_reset) begin
            color_mode_timer<=0; color_mode_requested<=0; color_mode_active<=0;
            field_min<=255; field_max<=0; field_h_count<=0; field_line_count<=0;
            source_field_status<=0;
        end else begin
            if(color_mode_timer==27'd67499999) begin
                color_mode_timer<=0; color_mode_requested<=~color_mode_requested;
            end else color_mode_timer<=color_mode_timer+1'b1;
            if(decoder_level_hold<field_min) field_min<=decoder_level_hold;
            if(decoder_level_hold>field_max) field_max<=decoder_level_hold;
            if(hsync_pulse) field_h_count<=field_h_count+1'b1;
            if(decoded_line_done) field_line_count<=field_line_count+1'b1;
            if(vsync_pulse) begin
                color_mode_active<=color_mode_requested;
                source_field_status<={field_min,field_max,field_h_count,field_line_count};
                field_min<=255; field_max<=0; field_h_count<=0; field_line_count<=0;
            end
        end
    end
    // First hardware gate: prove horizontal monochrome reconstruction without
    // depending on the still-unqualified vertical or burst detectors.
    ntsc_color_decoder #(
        .REQUIRE_FIELD_WINDOW(0),
        .ENABLE_COLOR(COLOR_DECODE),
        .RUNTIME_COLOR(RUNTIME_COLOR),
        .CLEAN_CHROMA(CLEAN_CHROMA),
        .RAW_LEVEL_OUTPUT(0),
        .LUMA_GAIN_SHIFT(COLOR_OUTPUT ? 1 : 0),
        .SPLIT_CHROMA(COLOR_OUTPUT), .PHASE_QUALIFIED(COLOR_OUTPUT),
        .BURST_START(COLOR_OUTPUT ? 0 : 7), .BURST_END(COLOR_OUTPUT ? 32 : 38),
        .TRACK_BLACK(1)
    ) decoder (
        .clk(clk_sample_13m5),
        .color_enable(color_mode_active),
        .reset(sample_reset),
        // The 64-sample density estimate is coherently held for this clock;
        // avoid the additional 1/16 ADC-domain IIR so picture bandwidth is
        // not reduced to roughly 130 kHz.
        .sample_level(decoder_level_hold),
        .chroma_level(burst_level_hold),
        .hsync_pulse(hsync_pulse),
        .vsync_pulse(vsync_pulse),
        .pixel_valid(decoded_pixel_valid),
        .pixel_x(decoded_pixel_x),
        .pixel_rgb565(decoded_pixel_rgb565),
        .line_done(decoded_line_done),
        .field_toggle(decoded_field_toggle),
        .color_locked(color_locked),
        .debug_black_level(debug_black_level),
        .debug_luma_level(debug_luma_level)
    );

    // Source vertical sync anchors 240 capture lines after 16 blanking lines.
    // Keep the old unanchored 262/263 cadence only as an explicit fallback.
    // HDMI timing stays independent; only the source memory origin changes.
    localparam integer FRAME_PIXELS = FRAME_WIDTH * 120;
    localparam integer CAPTURE_STEP = 640 / FRAME_WIDTH;
    reg [8:0] capture_field_line;
    reg capture_long_field;
    reg [2:0] capture_x_phase;
    reg [7:0] capture_x_index;
    reg write_frame_bank;
    reg completed_bank;
    wire completed_toggle;
    reg completed_toggle_reg;
    reg source_field_seen;
    reg runtime_field_boundary;

    always @(posedge clk_sample_13m5) begin
        if (sample_reset) begin
            capture_field_line <= 9'd0;
            capture_long_field <= 1'b0;
            capture_x_phase <= 3'd0;
            capture_x_index <= 7'd0;
            write_frame_bank <= 1'b0;
            completed_bank <= 1'b0;
            completed_toggle_reg <= 1'b0;
            source_field_seen <= 1'b0;
            runtime_field_boundary <= 0;
        end else begin
            if (vsync_pulse) begin
                runtime_field_boundary <= ~runtime_field_boundary;
                capture_field_line <= 0;
                capture_x_phase <= 0;
                capture_x_index <= 0;
                source_field_seen <= 1;
                if (source_field_seen && capture_field_line >= 9'd256) begin
                    completed_bank <= write_frame_bank;
                    completed_toggle_reg <= ~completed_toggle_reg;
                    write_frame_bank <= ~write_frame_bank;
                end
            end else if (hsync_pulse) begin
                capture_x_phase <= 3'd0;
                capture_x_index <= 7'd0;
                if (!SOURCE_FIELD_SYNC && ((!capture_long_field &&
                     (capture_field_line == 9'd261)) ||
                    ( capture_long_field &&
                     (capture_field_line == 9'd262)))) begin
                    capture_field_line <= 9'd0;
                    capture_long_field <= ~capture_long_field;
                    runtime_field_boundary <= ~runtime_field_boundary;
                    completed_bank <= write_frame_bank;
                    completed_toggle_reg <= ~completed_toggle_reg;
                    write_frame_bank <= ~write_frame_bank;
                end else if (!(&capture_field_line)) begin
                    capture_field_line <= capture_field_line + 1'b1;
                end
            end else if (decoded_pixel_valid) begin
                if (capture_x_phase == CAPTURE_STEP-1) begin
                    capture_x_phase <= 3'd0;
                    if (capture_x_index != FRAME_WIDTH-1)
                        capture_x_index <= capture_x_index + 1'b1;
                end else begin
                    capture_x_phase <= capture_x_phase + 1'b1;
                end
            end
        end
    end

    assign completed_toggle = completed_toggle_reg;
    wire frame_wr_en = decoded_pixel_valid &&
                       !hsync_pulse && !vsync_pulse &&
                       (SOURCE_FIELD_SYNC ?
                           (source_field_seen && capture_field_line >= 9'd16 &&
                            capture_field_line < 9'd256) :
                           (capture_field_line < 9'd240)) &&
                       !capture_field_line[0] &&
                       (capture_x_phase == 3'd0);
    wire [8:0] capture_active_line = capture_field_line - 9'd16;
    wire [7:0] capture_y = SOURCE_FIELD_SYNC ? capture_active_line[8:1] :
                                             capture_field_line[8:1];
    wire [15:0] capture_pixel_offset =
        capture_y * FRAME_WIDTH + capture_x_index;
    wire [15:0] frame_wr_addr =
        (write_frame_bank ? FRAME_PIXELS : 16'd0) + capture_pixel_offset;
    wire [15:0] frame_rd_addr;
    localparam integer FRAME_BITS = (RAW_SNAPSHOT || COLOR_OUTPUT) ? 8 : 4;
    wire [FRAME_BITS-1:0] frame_rd_data;

    // Diagnostic snapshot: 15,360 consecutive 13.5MHz samples, independent
    // of sync, black tracking and picture decoding. Wait ~155ms after reset,
    // then freeze the entire buffer before HDMI adopts it. Each displayed
    // 5x4 block is one raw 8-bit density estimate in row-major time order.
    reg [20:0] raw_settle;
    reg [13:0] raw_index;
    reg raw_done;
    wire raw_write = (&raw_settle) && !raw_done;
    wire probe_wr_en, probe_bank, probe_toggle, adopted_toggle;
    wire [15:0] probe_wr_addr;
    wire [FRAME_BITS-1:0] probe_wr_data;
    wire [7:0] color_pixel = {decoded_pixel_rgb565[15:13],
                              decoded_pixel_rgb565[10:8],decoded_pixel_rgb565[4:3]};
    wire [1:0] probe_mode;
    wire [79:0] probe_status_source, probe_status_display;
    wire [7:0] probe_picture_flags;
    assign probe_status_source[79:48]=source_field_status;
    assign probe_status_source[47:40]={COLOR_DECODE && (!RUNTIME_COLOR || color_mode_active),probe_picture_flags[6:0]};
    wire probe_status_request;
    wire frame_status_request, line_status_request;
    assign probe_status_request=LINE_OUTPUT ? line_status_request : frame_status_request;
    generate if (RUNTIME_PROBE) begin : runtime_probe
        runtime_video_probe #(.CYCLE_ONCE(PROBE_CYCLE_ONCE),
                              .BANK_PIXELS(FRAME_PIXELS), .NIBBLE_RAW(BURST_PROBE),
                              .DATA_BITS(FRAME_BITS)) controller (
            .clk(clk_sample_13m5), .reset(sample_reset),
            .raw_level(BURST_PROBE ? burst_level_hold : decoder_level_hold), .picture_wr_en(frame_wr_en),
            .picture_addr(capture_pixel_offset[14:0]),
            .picture_data(COLOR_OUTPUT ? color_pixel : {4'b0,decoded_pixel_rgb565[15:12]}),
            // Every boundary, including a short/broken field, terminates the
            // validation attempt. The controller, not the H counter, qualifies it.
            .picture_frame_toggle(runtime_field_boundary),
            .adopted_toggle_async(adopted_toggle), .wr_en(probe_wr_en),
            .wr_addr(probe_wr_addr), .wr_data(probe_wr_data),
            .published_bank(probe_bank), .published_toggle(probe_toggle),
            .published_mode(probe_mode),
            .last_picture_words(probe_status_source[15:0]),
            .rejected_pictures(probe_status_source[31:16]),
            .accepted_pictures(probe_status_source[39:32]),
            .last_picture_flags(probe_picture_flags));
    end else begin : no_runtime_probe
        assign probe_wr_en=0;
        assign probe_wr_addr=0;
        assign probe_wr_data=0;
        assign probe_bank=0;
        assign probe_toggle=0;
        assign probe_mode=0;
        assign probe_status_source[39:0]=0;
        assign probe_picture_flags=0;
    end endgenerate
    video_status_snapshot #(.WIDTH(80)) status_snapshot (
        .src_clk(clk_sample_13m5), .src_reset(sample_reset), .src_data(probe_status_source),
        .dst_clk(clk_pixel_25m2), .dst_reset(!pixel_resetn),
        .dst_request(probe_status_request), .dst_data(probe_status_display));
    always @(posedge clk_sample_13m5) begin
        if (sample_reset) begin
            raw_settle <= 0;
            raw_index <= 0;
            raw_done <= 0;
        end else if (!(&raw_settle)) begin
            raw_settle <= raw_settle + 1'b1;
        end else if (!raw_done) begin
            if (raw_index == 14'd15359) raw_done <= 1'b1;
            else raw_index <= raw_index + 1'b1;
        end
    end

    wire [7:0] selected_store_byte = RUNTIME_PROBE ? probe_wr_data :
        RAW_SNAPSHOT == 2 ? raw_index[7:0] : RAW_SNAPSHOT ? decoder_level_hold :
        COLOR_OUTPUT ? color_pixel : {4'b0,decoded_pixel_rgb565[15:12]};
    ntsc_lowres_frame_store #(
        .DATA_BITS(FRAME_BITS), .DEPTH(RAW_SNAPSHOT ? 15360 : 2*FRAME_PIXELS)
    ) frame_store (
        .wr_clk(clk_sample_13m5),
        .wr_en(RUNTIME_PROBE ? probe_wr_en : RAW_SNAPSHOT ? raw_write : frame_wr_en),
        .wr_addr(RUNTIME_PROBE ? probe_wr_addr : RAW_SNAPSHOT ? {2'b00, raw_index} : frame_wr_addr),
        .wr_data(selected_store_byte[FRAME_BITS-1:0]),
        .rd_clk(clk_pixel_25m2),
        .rd_addr(frame_rd_addr),
        .rd_data(frame_rd_data)
    );

    wire frame_clk_n, frame_clk_p, line_clk_n, line_clk_p;
    wire [2:0] frame_d_n, frame_d_p, line_d_n, line_d_p;
    hdmi_ntsc_line_tx #(.FRAME_BITS(FRAME_BITS), .RUNTIME_PROBE(RUNTIME_PROBE),
                        .FRAME_WIDTH(FRAME_WIDTH), .COLOR_OUTPUT(COLOR_OUTPUT)) hdmi (
        .clk_pixel(clk_pixel_25m2),
        .clk_5x_pixel(clk_tmds_126m),
        .resetn(pixel_resetn),
        .serial_resetn(serial_resetn),
        .completed_bank_async(RUNTIME_PROBE ? probe_bank : RAW_SNAPSHOT ? 1'b0 : completed_bank),
        .completed_toggle_async(RUNTIME_PROBE ? probe_toggle : RAW_SNAPSHOT ? raw_done : completed_toggle),
        .probe_mode_async(probe_mode), .adopted_toggle(adopted_toggle),
        .probe_status(probe_status_display), .probe_status_request(frame_status_request),
        // Keep VGA vertical timing free-running until composite vertical-sync
        // qualification is proven; false field toggles otherwise hold HDMI in
        // vertical blanking and produce an all-black capture.
        .field_toggle_async(1'b0),
        .frame_rd_addr(frame_rd_addr),
        .frame_rd_data(frame_rd_data),
        .line_locked_async(qualified_lock_seen),
        // Color decoding is intentionally disabled in this monochrome gate.
        .color_locked_async(COLOR_OUTPUT ? color_locked : 1'b0),
        .hpll_phase_error_async(hpll_last_error_samples),
        .hpll_period_async(line_period_q4[13:4]),
        .hsync_width_async(last_sync_low_width),
        .black_level_async(debug_black_level),
        .luma_level_async(debug_luma_level),
        .tmds_clk_n(frame_clk_n),
        .tmds_clk_p(frame_clk_p),
        .tmds_d_n(frame_d_n),
        .tmds_d_p(frame_d_p)
    );

    assign tmds_clk_n=LINE_OUTPUT ? line_clk_n : frame_clk_n;
    assign tmds_clk_p=LINE_OUTPUT ? line_clk_p : frame_clk_p;
    assign tmds_d_n=LINE_OUTPUT ? line_d_n : frame_d_n;
    assign tmds_d_p=LINE_OUTPUT ? line_d_p : frame_d_p;
    generate if(LINE_OUTPUT) begin : streaming
        reg [7:0] field_id;
        always @(posedge clk_sample_13m5)
            if(sample_reset) field_id<=0; else if(vsync_pulse) field_id<=field_id+1'b1;
        wire line_start=source_field_seen && hsync_pulse &&
            capture_field_line>=15 && capture_field_line<255 && !vsync_pulse;
        wire line_window=source_field_seen && capture_field_line>=16 && capture_field_line<256;
        wire [8:0] source_line_index=capture_field_line-9'd15;
        wire [9:0] line_write_addr=decoded_pixel_x/(640/LINE_WIDTH);
        wire [2:0] ready;
        wire [47:0] tags;
        wire [15:0] read_data, drops, bad, underflows;
        wire [7:0] frames;
        wire take, release_bank;
        wire [1:0] take_bank, release_index, read_bank;
        wire [9:0] read_addr;
        ntsc_three_line_queue #(.WIDTH(LINE_WIDTH)) queue (
            .wr_clk(clk_sample_13m5), .wr_reset(sample_reset), .wr_start(line_start),
            .wr_field(field_id), .wr_line(source_line_index[7:0]),
            .wr_en(line_window && decoded_pixel_valid && (decoded_pixel_x%(640/LINE_WIDTH)==0) && !hsync_pulse && !vsync_pulse),
            .wr_end(line_window && decoded_line_done), .wr_addr(line_write_addr),
            .wr_data(decoded_pixel_rgb565), .dropped_lines(drops), .bad_lines(bad),
            .rd_clk(clk_pixel_25m2), .rd_reset(!pixel_resetn),
            .rd_take(take), .rd_release(release_bank), .rd_take_bank(take_bank),
            .rd_release_bank(release_index), .rd_bank(read_bank), .rd_addr(read_addr),
            .rd_data(read_data), .rd_ready(ready), .rd_tags(tags));
        hdmi_three_line_tx #(.WIDTH(LINE_WIDTH)) transmitter (
            .clk_pixel(clk_pixel_25m2), .clk_5x_pixel(clk_tmds_126m),
            .resetn(pixel_resetn), .serial_resetn(serial_resetn),
            .ready(ready), .tags(tags), .line_data(read_data),
            .take(take), .release_bank(release_bank), .take_bank(take_bank),
            .release_index(release_index), .read_bank(read_bank), .read_addr(read_addr),
            .lock_async(qualified_lock_seen), .color_async(color_locked),
            .source_status(probe_status_display), .status_request(line_status_request),
            .underflows(underflows), .started_frames(frames),
            .tmds_clk_n(line_clk_n), .tmds_clk_p(line_clk_p),
            .tmds_d_n(line_d_n), .tmds_d_p(line_d_p));
    end else begin : no_streaming
        assign line_status_request=0;
        assign line_clk_n=0; assign line_clk_p=0;
        assign line_d_n=0; assign line_d_p=0;
    end endgenerate

    assign led = ~qualified_lock_seen;
endmodule
