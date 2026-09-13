`timescale 1ns/1ps
module tb_monochrome_recovery;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, hsync = 0;
    reg [7:0] level = 64;
    wire valid, done;
    wire [9:0] x;
    wire [15:0] rgb;
    integer line, pos, pixels = 0, completed = 0;
    integer black_pixels = 0, gray_pixels = 0, white_pixels = 0;
    integer check_brightness = 0;
    integer expect_silence = 0;

    ntsc_color_decoder #(.REQUIRE_FIELD_WINDOW(0), .ENABLE_COLOR(0),
        .TRACK_BLACK(1), .FIXED_BLACK_LEVEL(64)) dut (
        .clk(clk), .reset(reset), .sample_level(level), .hsync_pulse(hsync),
        .vsync_pulse(1'b0), .pixel_valid(valid), .pixel_x(x),
        .pixel_rgb565(rgb), .line_done(done));

    always @(posedge clk) begin
        #1;
        if (!reset) begin
            if (expect_silence && (valid || done))
                $fatal(1, "output without a live line");
            if (valid) begin
                if (x !== pixels[9:0])
                    $fatal(1, "pixel index mismatch got=%0d expected=%0d", x, pixels);
                pixels = pixels + 1;
                if (rgb[15:11] !== rgb[10:6] || rgb[15:11] !== rgb[4:0])
                    $fatal(1, "unequal monochrome channels");
                if (check_brightness) begin
                    if (x >= 50 && x < 150) begin
                        if (rgb[15:11] > 1) $fatal(1, "black is not black");
                        black_pixels = black_pixels + 1;
                    end
                    if (x >= 270 && x < 370) begin
                        if (rgb[15:11] < 9 || rgb[15:11] > 11)
                            $fatal(1, "gray level wrong: %0d", rgb[15:11]);
                        gray_pixels = gray_pixels + 1;
                    end
                    if (x >= 480 && x < 580) begin
                        if (rgb[15:11] < 19 || rgb[15:11] > 21)
                            $fatal(1, "bright level wrong: %0d", rgb[15:11]);
                        white_pixels = white_pixels + 1;
                    end
                end
            end
            if (done) begin
                if (!valid || pixels != 640) $fatal(1, "invalid line completion");
                completed = completed + 1;
            end
        end
    end

    task source_line;
        input integer length;
        begin
            @(negedge clk); hsync = 1; pixels = 0;
            for (pos = 0; pos < length; pos = pos + 1) begin
                @(negedge clk); hsync = 0;
                if (pos < 315) level = 64;
                else if (pos < 552) level = 144;
                else if (pos < 789) level = 224;
                else level = 64;
            end
        end
    endtask

    initial begin
        repeat (8) @(negedge clk);
        reset = 0; expect_silence = 1;
        repeat (5000) @(negedge clk);
        expect_silence = 0; check_brightness = 1;
        for (line = 0; line < 8; line = line + 1) source_line(857);
        if (completed != 8 || pixels != 640) $fatal(1, "missing full lines");
        expect_silence = 1;
        repeat (6000) @(negedge clk);
        expect_silence = 0; check_brightness = 0;
        // A premature line start discards the partial line, then reacquires.
        source_line(200);
        if (completed != 8) $fatal(1, "partial line completed");
        source_line(857);
        if (completed != 9 || pixels != 640) $fatal(1, "reacquisition failed");
        $display("PASS monochrome: lines=%0d black=%0d gray=%0d bright=%0d; indices 0..639; startup/loss silence; partial-line recovery",
                 completed, black_pixels, gray_pixels, white_pixels);
        $finish;
    end
endmodule
