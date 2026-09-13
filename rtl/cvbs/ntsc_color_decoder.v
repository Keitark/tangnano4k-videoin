module ntsc_color_decoder #(
    parameter [23:0] NCO_STEP = 24'h43e0f8,
    parameter [23:0] HUE_OFFSET = 24'h000000,
    parameter integer ACTIVE_START = 78,
    parameter integer ACTIVE_SAMPLES = 711,
    parameter integer REQUIRE_FIELD_WINDOW = 1,
    parameter integer ENABLE_COLOR = 1,
    parameter integer RAW_LEVEL_OUTPUT = 0,
    parameter integer TRACK_BLACK = 0,
    parameter integer FIXED_BLACK_LEVEL = 185,
    parameter integer LUMA_GAIN_SHIFT = 0,
    parameter integer LUMA_FILTER_SHIFT = 2,
    parameter integer SPLIT_CHROMA = 0,
    parameter integer PHASE_QUALIFIED = 0,
    parameter integer RUNTIME_COLOR = 0,
    parameter integer CLEAN_CHROMA = 0,
    parameter integer BURST_START = 7,
    parameter integer BURST_END = 38
) (
    input  wire        clk,
    input  wire        color_enable,
    input  wire        reset,
    input  wire [7:0]  sample_level,
    input  wire [7:0]  chroma_level,
    input  wire        hsync_pulse,
    input  wire        vsync_pulse,
    output reg         pixel_valid,
    output reg  [9:0]  pixel_x,
    output reg  [15:0] pixel_rgb565,
    output reg         line_done,
    output reg         field_toggle,
    output reg         color_locked,
    output wire [7:0]  debug_black_level,
    output wire [7:0]  debug_luma_level
);
    reg [10:0] line_position;
    reg line_active;
    reg [9:0] output_count;
    reg [7:0] sample_level_reg;
    reg [7:0] chroma_d0, chroma_d1, chroma_d2, chroma_d3;
    reg [8:0] field_line;
    reg [10:0] horizontal_accum;
    reg [23:0] phase_accum;
    reg [23:0] phase_offset;
    // [16,3,16]/35 has its notch near the NTSC carrier at Fs=13.5MHz.
    // Wide-path luma retains detail that the 64-sample density window removes.
    wire [13:0] notch_sum={chroma_d0,4'b0}+{chroma_d2,4'b0}+
                            {5'b0,chroma_d1,1'b0}+{6'b0,chroma_d1};
    wire signed [12:0] notch_y_q4={notch_sum,4'b0}/18'd35;
    wire signed [13:0] notch_chroma_q4=$signed({1'b0,chroma_d1,4'b0})-notch_y_q4;
    reg signed [12:0] clean_y_delay[0:8];
    // Optional binomial LPF suppresses near-Nyquist density noise, which the
    // carrier notch alone passes. Center delay remains eight sample clocks.
    wire signed [14:0] clean_y_sum=$signed(clean_y_delay[6])+
        ($signed(clean_y_delay[7])<<<1)+$signed(clean_y_delay[8]);
    wire signed [12:0] clean_y_smooth=clean_y_sum>>>2;
    integer yi;
    always @(posedge clk) begin
        if(reset) begin
            for(yi=0;yi<9;yi=yi+1) clean_y_delay[yi]<=FIXED_BLACK_LEVEL*16;
        end else begin
            clean_y_delay[0]<=notch_y_q4;
            for(yi=1;yi<9;yi=yi+1) clean_y_delay[yi]<=clean_y_delay[yi-1];
        end
    end

    reg signed [12:0] black_q4;
    reg signed [12:0] luma_q4;
    reg signed [15:0] i_filter;
    reg signed [15:0] q_filter;
    reg signed [19:0] burst_i;
    reg signed [19:0] burst_q;
    reg [3:0] color_score;

    wire signed [12:0] sample_q4 = $signed({1'b0, sample_level_reg, 4'b0000});
    wire signed [13:0] luma_error = sample_q4 - luma_q4;
    wire signed [13:0] black_error = sample_q4 - black_q4;
    wire signed [12:0] chroma_sample_q4 = SPLIT_CHROMA ?
        $signed({1'b0,chroma_d3,4'b0}) : sample_q4;
    wire signed [13:0] chroma_q4 = chroma_sample_q4 - luma_q4;
    wire [23:0] reference_phase = phase_accum + phase_offset + HUE_OFFSET;
    wire [1:0] reference_quadrant = reference_phase[23:22];
    wire cos_positive = (reference_quadrant == 2'd0) ||
                        (reference_quadrant == 2'd3);
    wire sin_positive = (reference_quadrant == 2'd0) ||
                        (reference_quadrant == 2'd1);
    wire signed [14:0] clean_mix_i,clean_mix_q;
    wire signed [15:0] clean_i,clean_q;
    generate if(CLEAN_CHROMA) begin : cleaned_chroma
        ntsc_chroma_fir filter(.clk(clk),.reset(reset),.chroma_q4(notch_chroma_q4),
            .phase(reference_phase),.mix_i(clean_mix_i),.mix_q(clean_mix_q),
            .filtered_i(clean_i),.filtered_q(clean_q));
    end else begin : no_cleaned_chroma
        assign clean_mix_i=0; assign clean_mix_q=0;
        assign clean_i=0; assign clean_q=0;
    end endgenerate
    wire signed [14:0] mix_i = CLEAN_CHROMA ? clean_mix_i : cos_positive ? chroma_q4 : -chroma_q4;
    wire signed [14:0] mix_q = CLEAN_CHROMA ? clean_mix_q : sin_positive ? chroma_q4 : -chroma_q4;
    wire signed [16:0] i_error = mix_i - i_filter;
    wire signed [16:0] q_error = mix_q - q_filter;
    wire signed [13:0] luma_next =
        $signed({luma_q4[12], luma_q4}) +
        (luma_error >>> LUMA_FILTER_SHIFT);
    wire signed [13:0] black_next =
        $signed({black_q4[12], black_q4}) + (black_error >>> 4);
    wire signed [16:0] i_filter_next =
        $signed({i_filter[15], i_filter}) + (i_error >>> 2);
    wire signed [16:0] q_filter_next =
        $signed({q_filter[15], q_filter}) + (q_error >>> 2);

    wire active_line = !REQUIRE_FIELD_WINDOW ||
                       ((field_line >= 9'd20) && (field_line < 9'd260));
    wire active_sample = line_active && active_line &&
                         (line_position >= ACTIVE_START) &&
                         (line_position < ACTIVE_START + ACTIVE_SAMPLES);
    wire [11:0] next_horizontal_accum = horizontal_accum + 11'd640;
    localparam [10:0] ACTIVE_SAMPLES_11 = ACTIVE_SAMPLES;
    wire [11:0] horizontal_remainder = next_horizontal_accum -
                                       {1'b0, ACTIVE_SAMPLES_11};

    // Input convention: sync below black, brighter picture above black.
    // This is the same polarity used by the top-level sync slicer.
    wire signed [15:0] luma_above_black = (CLEAN_CHROMA>=2 ? clean_y_smooth :
        CLEAN_CHROMA ? clean_y_delay[7] : luma_q4) - black_q4;
    assign debug_black_level = black_q4[12] ? 8'h00 : black_q4[11:4];
    assign debug_luma_level = luma_q4[12] ? 8'h00 : luma_q4[11:4];
    // The coherent 64-sample density path spans most of the 8-bit range.
    // Convert its Q4 difference back to an 8-bit value at unity gain so the
    // luminance detail is preserved instead of clipping to black and white.
    wire signed [15:0] y_value = luma_above_black >>> (4 - LUMA_GAIN_SHIFT);
    wire signed [15:0] u_value = (CLEAN_CHROMA ? clean_i : i_filter) >>> (SPLIT_CHROMA ? 2 : 3);
    // NTSC C=U*sin(theta)+V*cos(theta), burst=-U. With our burst locked
    // to negative cosine, the sine mixer measures -V, not +V.
    wire signed [15:0] v_value = (CLEAN_CHROMA ? -clean_q : q_filter) >>> (SPLIT_CHROMA ? 2 : 3);
    wire use_color = ENABLE_COLOR && color_locked && (!RUNTIME_COLOR || color_enable);
    // Standard inverse YUV matrix, shift/add approximations:
    // R=Y+1.140625V; G=Y-.390625U-.578125V; B=Y+2.03125U.
    // Keep the previous coarse matrix in earlier trial modes for reproducibility.
    wire signed [15:0] matrix_r=y_value+v_value+(v_value>>>3)+(v_value>>>6);
    wire signed [15:0] matrix_g=y_value-
        ((u_value>>>2)+(u_value>>>3)+(u_value>>>6))-
        ((v_value>>>1)+(v_value>>>4)+(v_value>>>6));
    wire signed [15:0] matrix_b=y_value+(u_value<<<1)+(u_value>>>5);
    wire signed [15:0] red_value = use_color ?
        (CLEAN_CHROMA>=4 ? matrix_r : y_value + v_value + (v_value >>> 2)) : y_value;
    wire signed [15:0] green_value = use_color ?
        (CLEAN_CHROMA>=4 ? matrix_g : y_value - (u_value >>> 2) - (v_value >>> 1)) : y_value;
    wire signed [15:0] blue_value = use_color ?
        (CLEAN_CHROMA>=4 ? matrix_b : y_value + u_value + (u_value >>> 1)) : y_value;

    function [7:0] clamp_u8;
        input signed [15:0] value;
        begin
            if (value < 0)
                clamp_u8 = 8'h00;
            else if (value > 255)
                clamp_u8 = 8'hff;
            else
                clamp_u8 = value[7:0];
        end
    endfunction

    wire [7:0] red_u8 = clamp_u8(red_value);
    wire [7:0] green_u8 = clamp_u8(green_value);
    wire [7:0] blue_u8 = clamp_u8(blue_value);
    // Equal 5-bit channel quantization prevents very dark monochrome values
    // from appearing green solely because RGB565 has one extra green bit.
    wire [15:0] monochrome_rgb565 =
        {red_u8[7:3], red_u8[7:3], 1'b0, red_u8[7:3]};
    // Raw diagnostics preserve the same polarity as the processed path.
    wire [7:0] raw_normalized_level = sample_level_reg;
    wire [15:0] raw_level_rgb565 =
        {raw_normalized_level[7:3], raw_normalized_level[7:3], 1'b0,
         raw_normalized_level[7:3]};
    wire [20:0] burst_magnitude =
        (burst_i[19] ? -burst_i : burst_i) +
        (burst_q[19] ? -burst_q : burst_q);
    wire [19:0] abs_burst_i = burst_i[19] ? -burst_i : burst_i;
    wire [19:0] abs_burst_q = burst_q[19] ? -burst_q : burst_q;
    wire burst_phase_good = burst_i[19] && (abs_burst_q <= (abs_burst_i >> 2));
    wire [23:0] phase_step = abs_burst_q > (abs_burst_i >> 2) ? 24'h100000 :
                            abs_burst_q > (abs_burst_i >> 4) ? 24'h040000 : 24'h010000;

    always @(posedge clk) begin
        if (reset) begin
            line_position <= 0;
            line_active <= 0;
            output_count <= 0;
            sample_level_reg <= 0;
            chroma_d0<=0; chroma_d1<=0; chroma_d2<=0; chroma_d3<=0;
            field_line <= 0;
            horizontal_accum <= 0;
            phase_accum <= 0;
            phase_offset <= 0;
            black_q4 <= FIXED_BLACK_LEVEL * 16;
            luma_q4 <= FIXED_BLACK_LEVEL * 16;
            i_filter <= 0;
            q_filter <= 0;
            burst_i <= 0;
            burst_q <= 0;
            color_score <= 0;
            pixel_valid <= 0;
            pixel_x <= 0;
            pixel_rgb565 <= 0;
            line_done <= 0;
            field_toggle <= 0;
            color_locked <= 0;
        end else begin
            // Register the multi-bit reconstruction at the slow-clock boundary
            // before it feeds the decoder's arithmetic.
            sample_level_reg <= sample_level;
            // Compensate the three13.5MHz-sample group-delay difference of
            // the16- and64-sample108MHz reconstruction windows.
            chroma_d0<=chroma_level; chroma_d1<=chroma_d0;
            chroma_d2<=chroma_d1; chroma_d3<=chroma_d2;
            phase_accum <= phase_accum + NCO_STEP;
            // A line is armed only by hsync and cannot wrap into another
            // active window when sync disappears.
            if (line_active) begin
                if (line_position < ACTIVE_START + ACTIVE_SAMPLES - 1)
                    line_position <= line_position + 1'b1;
                else
                    line_active <= 1'b0;
            end
            pixel_valid <= 1'b0;
            line_done <= 1'b0;

            // A low-pass estimate supplies luminance; the residual carries the
            // 3.58 MHz chroma component for the quadrature mixers.
            luma_q4 <= luma_next[12:0];
            i_filter <= i_filter_next[15:0];
            q_filter <= q_filter_next[15:0];

            if (vsync_pulse) begin
                field_line <= 0;
                field_toggle <= ~field_toggle;
            end

            if (hsync_pulse) begin
                line_position <= 0;
                line_active <= 1'b1;
                output_count <= 0;
                if (!vsync_pulse)
                    field_line <= field_line + 1'b1;
                horizontal_accum <= 0;
                pixel_x <= 0;
                burst_i <= 0;
                burst_q <= 0;
                i_filter <= 0;
                q_filter <= 0;
            end else if (line_active) begin
                // Burst window begins after the breezeway and ends before the
                // quiet back-porch black-level measurement window.
                if ((line_position >= BURST_START) &&
                    (line_position < BURST_END)) begin
                    burst_i <= burst_i + mix_i;
                    burst_q <= burst_q + mix_q;
                end

                if (TRACK_BLACK && (line_position >= 11'd43) &&
                    (line_position < 11'd63))
                    black_q4 <= black_next[12:0];

                if (line_position == BURST_END+1) begin
                    if (burst_magnitude > 21'd1200) begin
                        if ((!PHASE_QUALIFIED || burst_phase_good) && color_score != 4'hf)
                            color_score <= color_score + 1'b1;
                        else if(PHASE_QUALIFIED && !burst_phase_good && color_score!=0)
                            color_score <= color_score - 1'b1;

                        // Lock the local oscillator to the burst quadrature.
                        // A positive in-phase result is a 180-degree ambiguity.
                        if (!burst_i[19])
                            phase_offset <= phase_offset + 24'h800000;
                        else if(PHASE_QUALIFIED && burst_q > 20'sd96)
                            phase_offset <= phase_offset + phase_step;
                        else if(PHASE_QUALIFIED && burst_q < -20'sd96)
                            phase_offset <= phase_offset - phase_step;
                        else if (burst_q > 20'sd96)
                            phase_offset <= phase_offset - 24'h010000;
                        else if (burst_q < -20'sd96)
                            phase_offset <= phase_offset + 24'h010000;
                    end else if (color_score != 0) begin
                        color_score <= color_score - 1'b1;
                    end
                    if(CLEAN_CHROMA>=3) begin
                        // Hysteresis: isolated phase outliers must not turn a
                        // whole line gray. Sustained absent/bad burst still
                        // decays the score and disables color within 16 lines.
                        if(color_score<=2) color_locked<=0;
                        else if(color_score>=10 && burst_phase_good && burst_magnitude>1200)
                            color_locked<=1;
                    end else begin
                        color_locked <= (color_score >= 4'd7) &&
                            (!PHASE_QUALIFIED || (burst_phase_good && burst_magnitude > 1200));
                    end
                end

                if (active_sample) begin
                    if (next_horizontal_accum >= ACTIVE_SAMPLES) begin
                        horizontal_accum <= horizontal_remainder[10:0];
                        pixel_valid <= 1'b1;
                        pixel_x <= output_count;
                        pixel_rgb565 <= RAW_LEVEL_OUTPUT ? raw_level_rgb565 :
                            (use_color ?
                             {red_u8[7:3], green_u8[7:2], blue_u8[7:3]} :
                             monochrome_rgb565);
                        if (output_count == 10'd639) begin
                            line_done <= 1'b1;
                            line_active <= 1'b0;
                        end else begin
                            output_count <= output_count + 1'b1;
                        end
                    end else begin
                        horizontal_accum <= next_horizontal_accum[10:0];
                    end
                end
            end
        end
    end
endmodule
