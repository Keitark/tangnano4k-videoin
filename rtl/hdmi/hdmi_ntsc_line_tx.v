module hdmi_ntsc_line_tx #(
    parameter integer FRAME_BITS = 4,
    parameter integer RUNTIME_PROBE = 0,
    parameter integer FRAME_WIDTH = 128,
    parameter integer COLOR_OUTPUT = 0
) (
    input  wire        clk_pixel,
    input  wire        clk_5x_pixel,
    input  wire        resetn,
    input  wire        serial_resetn,
    input  wire        completed_bank_async,
    input  wire        completed_toggle_async,
    input  wire [1:0]  probe_mode_async,
    output wire        adopted_toggle,
    input wire [79:0]  probe_status,
    output wire        probe_status_request,
    input  wire        field_toggle_async,
    output wire [15:0] frame_rd_addr,
    input  wire [FRAME_BITS-1:0] frame_rd_data,
    input  wire        line_locked_async,
    input  wire        color_locked_async,
    input  wire signed [8:0] hpll_phase_error_async,
    input  wire [9:0]  hpll_period_async,
    input  wire [7:0]  hsync_width_async,
    input  wire [7:0]  black_level_async,
    input  wire [7:0]  luma_level_async,
    output wire        tmds_clk_n,
    output wire        tmds_clk_p,
    output wire [2:0]  tmds_d_n,
    output wire [2:0]  tmds_d_p
);
    reg [9:0] h_count;
    reg [9:0] v_count;
    reg       long_frame;
    reg [4:0] frame_rate_accum;
    reg [1:0] de_pipe;
    reg [1:0] hsync_pipe;
    reg [1:0] vsync_pipe;
    reg bank_meta, bank_sync, active_bank;
    reg line_toggle_meta, line_toggle_sync, line_toggle_seen;
    reg line_activity_seen;
    reg [1:0] mode_meta, mode_sync, active_mode;
    assign adopted_toggle = line_toggle_seen;
    assign probe_status_request = (h_count == 0 && v_count == 0);
    reg field_meta, field_sync, field_seen, field_pending;
    reg lock_meta, lock_sync;
    reg color_meta, color_sync;
    reg signed [8:0] phase_error_meta, phase_error_sync;
    reg [9:0] period_meta, period_sync;
    reg [7:0] sync_width_meta, sync_width_sync;
    reg [7:0] black_level_meta, black_level_sync;
    reg [7:0] luma_level_meta, luma_level_sync;
    reg [7:0] red_pipe, green_pipe, blue_pipe;

    wire active_video = (h_count < 640) && (v_count < 480);
    wire hsync = ~((h_count >= 656) && (h_count < 752));
    wire vsync = ~((v_count >= 490) && (v_count < 492));
    wire [6:0] scaled_y = (v_count < 10'd480) ? v_count[8:2] : 7'd0;
    wire [9:0] scaled_x_full = h_count / (640 / FRAME_WIDTH);
    wire [7:0] scaled_x = (h_count < 10'd640) ?
                          scaled_x_full[7:0] : 8'd0;
    wire [15:0] frame_pixel_offset =
        scaled_y * FRAME_WIDTH + scaled_x;
    assign frame_rd_addr = (active_bank ? FRAME_WIDTH*120 : 16'd0) +
                           frame_pixel_offset;

    wire [7:0] frame_gray = FRAME_BITS == 8 ? frame_rd_data :
                          {frame_rd_data, frame_rd_data};
    // Runtime probe only: avoid black/white clipping in the capture dongle's
    // range conversion for packed measurement nibbles. Picture contrast is
    // applied after memory, not in the ADC or sync path.
    wire [7:0] probe_gray = 8'd32 + {frame_rd_data[3:0],3'b0} +
                                   {frame_rd_data[3:0],2'b0};
    wire [9:0] bright_gray = {2'b0,frame_gray} + {1'b0,frame_gray,1'b0};
    wire [7:0] monochrome_gray = !RUNTIME_PROBE ? frame_gray : active_mode != 0 ?
        probe_gray : (bright_gray > 255 ? 8'd255 : bright_gray[7:0]);
    wire [7:0] color_byte = frame_rd_data;
    wire show_color=COLOR_OUTPUT && (!RUNTIME_PROBE || active_mode==0);
    wire [7:0] frame_red=show_color ? {color_byte[7:5],color_byte[7:5],color_byte[7:6]} : monochrome_gray;
    wire [7:0] frame_green=show_color ? {color_byte[4:2],color_byte[4:2],color_byte[4:3]} : monochrome_gray;
    wire [7:0] frame_blue=show_color ? {4{color_byte[1:0]}} : monochrome_gray;
    reg [7:0] selected_red;
    reg [7:0] selected_green;
    reg [7:0] selected_blue;

    wire signed [11:0] phase_marker_calc = 12'sd320 +
        ($signed(phase_error_sync) <<< 1) + $signed(phase_error_sync);
    wire signed [11:0] period_delta =
        $signed({1'b0, period_sync}) - 12'sd858;
    wire signed [11:0] period_marker_calc = 12'sd320 +
        (period_delta <<< 3);
    wire [9:0] phase_marker = (phase_marker_calc < 0) ? 10'd0 :
        (phase_marker_calc > 12'sd639) ? 10'd639 : phase_marker_calc[9:0];
    wire [9:0] period_marker = (period_marker_calc < 0) ? 10'd0 :
        (period_marker_calc > 12'sd639) ? 10'd639 : period_marker_calc[9:0];
    // Full-range pulse-width telemetry: x=64 is zero samples and each input
    // sample advances two pixels. The complete 8-bit width fits on screen.
    wire [9:0] width_marker = 10'd64 + {sync_width_sync, 1'b0};
    wire [9:0] black_marker = 10'd64 + {black_level_sync, 1'b0};
    wire [9:0] luma_marker = 10'd64 + {luma_level_sync, 1'b0};

    always @* begin
        // Always expose the raw reconstructed line. Lock state is reported by
        // the top status strip; hiding the frame behind a solid red fallback
        // prevents diagnosis while the HPLL is still converging.
        selected_red = frame_red;
        selected_green = frame_green;
        selected_blue = frame_blue;
        if (RUNTIME_PROBE && !line_activity_seen) begin
            selected_red = 0;
            selected_green = 0;
            selected_blue = 0;
        end
        if (!de_pipe[1]) begin
            selected_red = 0;
            selected_green = 0;
            selected_blue = 0;
        end else if (v_count < 8) begin
            // Unconditional HDMI/capture health strip. These seven fixed
            // 80-pixel color blocks do not depend on composite input, line
            // memory, or HPLL state. The final block reports horizontal lock:
            // yellow when locked, dark red while unlocked.
            if (h_count < 10'd80) begin
                selected_red = 8'hff;
                selected_green = 8'hff;
                selected_blue = 8'hff;
            end else if (h_count < 10'd160) begin
                selected_red = 8'hff;
                selected_green = 8'hff;
                selected_blue = 8'h00;
            end else if (h_count < 10'd240) begin
                selected_red = 8'h00;
                selected_green = 8'hff;
                selected_blue = 8'hff;
            end else if (h_count < 10'd320) begin
                selected_red = 8'h00;
                selected_green = 8'hff;
                selected_blue = 8'h00;
            end else if (h_count < 10'd400) begin
                selected_red = 8'hff;
                selected_green = 8'h00;
                selected_blue = 8'hff;
            end else if (h_count < 10'd480) begin
                selected_red = 8'hff;
                selected_green = 8'h00;
                selected_blue = 8'h00;
            end else if (h_count < 10'd560) begin
                selected_red = 8'h00;
                selected_green = 8'h00;
                selected_blue = 8'hff;
            end else if (lock_sync) begin
                selected_red = 8'hff;
                selected_green = 8'hd0;
                selected_blue = 8'h00;
            end else begin
                selected_red = 8'h60;
                selected_green = 8'h00;
                selected_blue = 8'h00;
            end
        end else if (v_count < 16) begin
            // White marker: last accepted phase error. Center is zero;
            // horizontal scale is three pixels per 13.5 MHz sample.
            selected_red = 8'h18;
            selected_green = 8'h18;
            selected_blue = 8'h18;
            if ((h_count >= phase_marker - 2) &&
                (h_count <= phase_marker + 2)) begin
                selected_red = 8'hff;
                selected_green = 8'hff;
                selected_blue = 8'hff;
            end
        end else if (v_count < 24) begin
            // Cyan marker: integral period estimate. Center is 858 samples;
            // horizontal scale is eight pixels per sample.
            selected_red = 8'h10;
            selected_green = 8'h10;
            selected_blue = 8'h10;
            if ((h_count >= period_marker - 2) &&
                (h_count <= period_marker + 2)) begin
                selected_red = 8'h00;
                selected_green = 8'hff;
                selected_blue = 8'hff;
            end
        end else if (v_count < 32) begin
            // Blue means a published BANK was adopted (including diagnostics),
            // not proof that the decoder completed a source line.
            selected_red = line_activity_seen ? 8'h00 : 8'hc0;
            selected_green = 8'h00;
            selected_blue = line_activity_seen ? 8'hd0 : 8'h00;
        end else if (v_count < 40) begin
            // Magenta marker: measured comparator-low pulse width over the
            // full 0..255-sample range, with two pixels per sample.
            selected_red = 8'h10;
            selected_green = 8'h10;
            selected_blue = 8'h10;
            if ((h_count >= width_marker - 2) &&
                (h_count <= width_marker + 2)) begin
                selected_red = 8'hff;
                selected_green = 8'h00;
                selected_blue = 8'hff;
            end
        end else if (v_count < 48) begin
            // Yellow marker: tracked back-porch black level, two pixels/code.
            selected_red = 8'h10;
            selected_green = 8'h10;
            selected_blue = 8'h10;
            if ((h_count >= black_marker - 2) &&
                (h_count <= black_marker + 2)) begin
                selected_red = 8'hff;
                selected_green = 8'hff;
                selected_blue = 8'h00;
            end
        end else if (v_count < 56) begin
            // Green marker: instantaneous filtered luma level.
            selected_red = 8'h10;
            selected_green = 8'h10;
            selected_blue = 8'h10;
            if ((h_count >= luma_marker - 2) &&
                (h_count <= luma_marker + 2)) begin
                selected_red = 8'h00;
                selected_green = 8'hff;
                selected_blue = 8'h00;
            end
        end else if (RUNTIME_PROBE && v_count < 64) begin
            // Green: picture; orange: high/low-nibble raw bytes;
            // magenta: the same packing with known calibration bytes.
            selected_red = active_mode == 0 ? (COLOR_OUTPUT && !color_sync ? 192 : 0) : 255;
            selected_green = active_mode == 0 ? 192 : active_mode == 1 ? 128 : 0;
            selected_blue = active_mode == 2 ? 255 : 0;
        end else if (RUNTIME_PROBE && v_count < 72) begin
            // 48 binary cells, 12 pixels each, MSB first from x=32. Groups:
            // flags[7:0], accepted[7:0], rejected[15:0], valid-prefix words[15:0].
            // Snapshot is handshaken across clocks; never decode live bus bits.
            selected_red=16; selected_green=16; selected_blue=16;
            if(h_count>=32 && h_count<608) begin
                if(probe_status[47-((h_count-32)/12)]) begin
                    selected_red=240; selected_green=240; selected_blue=240;
                end
            end
        end else if (RUNTIME_PROBE && v_count < 80) begin
            // 32 cells of 16 pixels from x=64, MSB first: sampled minimum,
            // maximum, H-pulse count and decoder line-done count (counts mod256).
            selected_red=16; selected_green=16; selected_blue=16;
            if(h_count>=64 && h_count<576 && probe_status[79-((h_count-64)/16)]) begin
                selected_red=240; selected_green=240; selected_blue=240;
            end
        end
    end

    always @(posedge clk_pixel) begin
        if (!resetn) begin
            h_count <= 0;
            v_count <= 0;
            long_frame <= 1'b0;
            frame_rate_accum <= 5'd0;
            de_pipe <= 0;
            hsync_pipe <= 2'b11;
            vsync_pipe <= 2'b11;
            bank_meta <= 0;
            bank_sync <= 0;
            active_bank <= 0;
            line_toggle_meta <= 0;
            line_toggle_sync <= 0;
            line_toggle_seen <= 0;
            line_activity_seen <= 0;
            mode_meta <= 0; mode_sync <= 0; active_mode <= 0;
            field_meta <= 0;
            field_sync <= 0;
            field_seen <= 0;
            field_pending <= 0;
            lock_meta <= 0;
            lock_sync <= 0;
            color_meta <= 0;
            color_sync <= 0;
            phase_error_meta <= 0;
            phase_error_sync <= 0;
            period_meta <= 10'd858;
            period_sync <= 10'd858;
            sync_width_meta <= 8'd64;
            sync_width_sync <= 8'd64;
            black_level_meta <= 8'd0;
            black_level_sync <= 8'd0;
            luma_level_meta <= 8'd0;
            luma_level_sync <= 8'd0;
            red_pipe <= 0;
            green_pipe <= 0;
            blue_pipe <= 0;
        end else begin
            bank_meta <= completed_bank_async;
            mode_meta <= probe_mode_async;
            mode_sync <= mode_meta;
            bank_sync <= bank_meta;
            line_toggle_meta <= completed_toggle_async;
            line_toggle_sync <= line_toggle_meta;
            field_meta <= field_toggle_async;
            field_sync <= field_meta;
            lock_meta <= line_locked_async;
            lock_sync <= lock_meta;
            color_meta <= color_locked_async;
            color_sync <= color_meta;
            phase_error_meta <= hpll_phase_error_async;
            phase_error_sync <= phase_error_meta;
            period_meta <= hpll_period_async;
            period_sync <= period_meta;
            sync_width_meta <= hsync_width_async;
            sync_width_sync <= sync_width_meta;
            black_level_meta <= black_level_async;
            black_level_sync <= black_level_meta;
            luma_level_meta <= luma_level_async;
            luma_level_sync <= luma_level_meta;
            de_pipe <= {de_pipe[0], active_video};
            hsync_pipe <= {hsync_pipe[0], hsync};
            vsync_pipe <= {vsync_pipe[0], vsync};
            red_pipe <= selected_red;
            green_pipe <= selected_green;
            blue_pipe <= selected_blue;

            if (field_sync != field_seen) begin
                field_seen <= field_sync;
                field_pending <= 1'b1;
            end

            if (h_count == 799) begin
                h_count <= 0;
                // Begin VGA vertical blank at each NTSC field. Forty-five VGA
                // blanking lines closely match the NTSC vertical interval;
                // each subsequently completed source line is displayed twice.
                if (field_pending) begin
                    v_count <= 10'd480;
                    field_pending <= 1'b0;
                end else if ((!long_frame && (v_count == 10'd524)) ||
                             ( long_frame && (v_count == 10'd525))) begin
                    v_count <= 0;
                    // Adopt only a fully completed source buffer and only at a
                    // normal HDMI frame boundary. The other bank can then be
                    // overwritten without tearing the displayed field.
                    if (line_toggle_sync != line_toggle_seen) begin
                        line_toggle_seen <= line_toggle_sync;
                        active_bank <= bank_sync;
                        active_mode <= mode_sync;
                        line_activity_seen <= 1'b1;
                    end
                    // The 25.2 MHz pixel clock produces exactly 60.000 Hz
                    // with 525 lines, while NTSC fields are 59.94006 Hz.
                    // Schedule an extra vertical-blank line in 11 of every 21
                    // frames. This keeps HDMI timing continuous and gives an
                    // average 59.94020 Hz without needing a fractional PLL.
                    if (frame_rate_accum >= 5'd10) begin
                        frame_rate_accum <= frame_rate_accum - 5'd10;
                        long_frame <= 1'b1;
                    end else begin
                        frame_rate_accum <= frame_rate_accum + 5'd11;
                        long_frame <= 1'b0;
                    end
                end else begin
                    v_count <= v_count + 1'b1;
                end
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    wire [9:0] tmds_blue;
    wire [9:0] tmds_green;
    wire [9:0] tmds_red;
    svo_tmds enc_blue (
        .clk(clk_pixel), .resetn(resetn), .de(de_pipe[1]),
        .ctrl({vsync_pipe[1], hsync_pipe[1]}),
        .din(blue_pipe), .dout(tmds_blue)
    );
    svo_tmds enc_green (
        .clk(clk_pixel), .resetn(resetn), .de(de_pipe[1]),
        .ctrl(2'b00), .din(green_pipe), .dout(tmds_green)
    );
    svo_tmds enc_red (
        .clk(clk_pixel), .resetn(resetn), .de(de_pipe[1]),
        .ctrl(2'b00), .din(red_pipe), .dout(tmds_red)
    );

    wire [2:0] serial_data;
    wire [2:0] d0 = {tmds_red[0], tmds_green[0], tmds_blue[0]};
    wire [2:0] d1 = {tmds_red[1], tmds_green[1], tmds_blue[1]};
    wire [2:0] d2 = {tmds_red[2], tmds_green[2], tmds_blue[2]};
    wire [2:0] d3 = {tmds_red[3], tmds_green[3], tmds_blue[3]};
    wire [2:0] d4 = {tmds_red[4], tmds_green[4], tmds_blue[4]};
    wire [2:0] d5 = {tmds_red[5], tmds_green[5], tmds_blue[5]};
    wire [2:0] d6 = {tmds_red[6], tmds_green[6], tmds_blue[6]};
    wire [2:0] d7 = {tmds_red[7], tmds_green[7], tmds_blue[7]};
    wire [2:0] d8 = {tmds_red[8], tmds_green[8], tmds_blue[8]};
    wire [2:0] d9 = {tmds_red[9], tmds_green[9], tmds_blue[9]};

    OSER10 serializers [2:0] (
        .Q(serial_data),
        .D0(d0), .D1(d1), .D2(d2), .D3(d3), .D4(d4),
        .D5(d5), .D6(d6), .D7(d7), .D8(d8), .D9(d9),
        .PCLK(clk_pixel), .FCLK(clk_5x_pixel), .RESET(~serial_resetn)
    );
    ELVDS_OBUF output_buffers [3:0] (
        .I({clk_pixel, serial_data}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );
endmodule
