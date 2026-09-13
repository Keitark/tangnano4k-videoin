module hdmi_diag_tx (
    input  wire       clk_pixel,
    input  wire       clk_5x_pixel,
    input  wire       resetn,
    input  wire       serial_resetn,
    input  wire [7:0] adc_level_async,
    input  wire       adc_activity_async,
    input  wire       line_locked_async,
    input  wire       sync_low_async,
    input  wire [7:0] reference_density_async,
    input  wire [7:0] sync_threshold_async,
    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);
    reg [9:0] h_count;
    reg [9:0] v_count;
    reg [7:0] level_meta;
    reg [7:0] level_sync;
    reg activity_meta;
    reg activity_sync;
    reg lock_meta;
    reg lock_sync;
    reg low_meta;
    reg low_sync;
    reg [7:0] reference_meta;
    reg [7:0] reference_sync;
    reg [7:0] threshold_meta;
    reg [7:0] threshold_sync;
    reg [7:0] red;
    reg [7:0] green;
    reg [7:0] blue;
    reg [7:0] red_pipe;
    reg [7:0] green_pipe;
    reg [7:0] blue_pipe;
    reg       active_video_pipe;
    reg       hsync_pipe;
    reg       vsync_pipe;

    wire active_video = (h_count < 640) && (v_count < 480);
    wire hsync = ~((h_count >= 656) && (h_count < 752));
    wire vsync = ~((v_count >= 490) && (v_count < 492));
    wire [8:0] bar_limit = {level_sync, 1'b0};
    wire [9:0] reference_bar_limit = {1'b0, reference_sync, 1'b0} + 10'd8;
    wire [9:0] threshold_bar_limit = {1'b0, threshold_sync, 1'b0} + 10'd8;

    always @(posedge clk_pixel) begin
        if (!resetn) begin
            h_count <= 0;
            v_count <= 0;
            level_meta <= 0;
            level_sync <= 0;
            activity_meta <= 0;
            activity_sync <= 0;
            lock_meta <= 0;
            lock_sync <= 0;
            low_meta <= 0;
            low_sync <= 0;
            reference_meta <= 0;
            reference_sync <= 0;
            threshold_meta <= 0;
            threshold_sync <= 0;
            red_pipe <= 0;
            green_pipe <= 0;
            blue_pipe <= 0;
            active_video_pipe <= 0;
            hsync_pipe <= 1;
            vsync_pipe <= 1;
        end else begin
            level_meta <= adc_level_async;
            level_sync <= level_meta;
            activity_meta <= adc_activity_async;
            activity_sync <= activity_meta;
            lock_meta <= line_locked_async;
            lock_sync <= lock_meta;
            low_meta <= sync_low_async;
            low_sync <= low_meta;
            reference_meta <= reference_density_async;
            reference_sync <= reference_meta;
            threshold_meta <= sync_threshold_async;
            threshold_sync <= threshold_meta;
            red_pipe <= red;
            green_pipe <= green;
            blue_pipe <= blue;
            active_video_pipe <= active_video;
            hsync_pipe <= hsync;
            vsync_pipe <= vsync;

            if (h_count == 799) begin
                h_count <= 0;
                if (v_count == 524)
                    v_count <= 0;
                else
                    v_count <= v_count + 1'b1;
            end else begin
                h_count <= h_count + 1'b1;
            end
        end
    end

    always @* begin
        red = 8'h08;
        green = 8'h08;
        blue = 8'h10;

        if (active_video) begin
            // Top status band: red=no activity, yellow=ADC activity,
            // green=stable NTSC-like line timing.
            if (v_count < 64) begin
                if (lock_sync) begin
                    red = 8'h00; green = 8'he0; blue = 8'h20;
                end else if (activity_sync) begin
                    red = 8'he0; green = 8'hb0; blue = 8'h00;
                end else begin
                    red = 8'he0; green = 8'h10; blue = 8'h10;
                end
            end else if ((v_count >= 72) && (v_count < 96)) begin
                // Runtime DSM reference indicator.  Width is 8 + 2*density,
                // covering the complete 0..255 range without clipping.
                if (h_count < reference_bar_limit) begin
                    red = 8'hd0; green = 8'h20; blue = 8'hd0;
                end else begin
                    red = 8'h10; green = 8'h10; blue = 8'h18;
                end
            end else if ((v_count >= 98) && (v_count < 108)) begin
                // Digital sync-separation threshold: cyan, same 8 + 2*code
                // scale as the magenta analog-reference indicator.
                if (h_count < threshold_bar_limit) begin
                    red = 8'h00; green = 8'hd0; blue = 8'hd0;
                end else begin
                    red = 8'h10; green = 8'h10; blue = 8'h18;
                end
            end else if ((v_count >= 112) && (v_count < 208)) begin
                // Reconstructed-level bar. Full width represents code 255.
                if ((h_count < bar_limit) && (h_count < 512)) begin
                    red = level_sync;
                    green = level_sync;
                    blue = 8'hff;
                end else begin
                    red = 8'h10; green = 8'h10; blue = 8'h18;
                end
            end else if ((v_count >= 256) && (v_count < 416)) begin
                // Large grayscale field follows the reconstructed composite
                // level so source changes are visible before image decoding.
                red = level_sync;
                green = level_sync;
                blue = level_sync;
                if ((h_count[5:0] == 0) || (v_count[5:0] == 0)) begin
                    red = red >> 1;
                    green = green >> 1;
                    blue = blue >> 1;
                end
            end else if (v_count >= 448) begin
                if (low_sync) begin
                    red = 8'h00; green = 8'hff; blue = 8'hff;
                end else begin
                    red = 8'h10; green = 8'h20; blue = 8'h28;
                end
            end
        end
    end

    wire [9:0] tmds_blue;
    wire [9:0] tmds_green;
    wire [9:0] tmds_red;

    svo_tmds enc_blue (
        .clk(clk_pixel), .resetn(resetn), .de(active_video_pipe),
        .ctrl({vsync_pipe, hsync_pipe}), .din(blue_pipe), .dout(tmds_blue)
    );
    svo_tmds enc_green (
        .clk(clk_pixel), .resetn(resetn), .de(active_video_pipe),
        .ctrl(2'b00), .din(green_pipe), .dout(tmds_green)
    );
    svo_tmds enc_red (
        .clk(clk_pixel), .resetn(resetn), .de(active_video_pipe),
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
