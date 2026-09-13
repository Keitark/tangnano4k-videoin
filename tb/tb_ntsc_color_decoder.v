`timescale 1ns/1ps
module tb_ntsc_color_decoder;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg [7:0] sample_level = 8'd43;
    reg hsync_pulse = 1'b0;
    reg vsync_pulse = 1'b0;
    wire pixel_valid;
    wire [9:0] pixel_x;
    wire [15:0] pixel_rgb565;
    wire line_done;
    wire field_toggle;
    wire color_locked;

    reg [23:0] source_phase;
    integer line_number;
    integer position;
    integer output_pixels;
    integer completed_lines;

    always #37.037 clk = ~clk;

    ntsc_color_decoder dut (
        .clk(clk), .reset(reset), .sample_level(sample_level),
        .hsync_pulse(hsync_pulse), .vsync_pulse(vsync_pulse),
        .pixel_valid(pixel_valid), .pixel_x(pixel_x),
        .pixel_rgb565(pixel_rgb565), .line_done(line_done),
        .field_toggle(field_toggle), .color_locked(color_locked)
    );

    always @(posedge clk) begin
        source_phase <= source_phase + 24'h43e0f8;
        if (pixel_valid)
            output_pixels <= output_pixels + 1;
        if (line_done)
            completed_lines <= completed_lines + 1;
    end

    task drive_line;
        begin
            @(negedge clk);
            hsync_pulse = 1'b1;
            sample_level = 8'd0;
            @(negedge clk);
            hsync_pulse = 1'b0;
            sample_level = 8'd43;

            for (position = 0; position < 857; position = position + 1) begin
                @(negedge clk);
                if ((position >= 7) && (position < 38)) begin
                    // Synthetic 3.579545 MHz burst, phase-coherent with the
                    // decoder's nominal NCO.
                    sample_level = source_phase[23] ? 8'd25 : 8'd61;
                end else if ((position >= 78) && (position < 789)) begin
                    // Active video with luma plus a phase-coherent color term.
                    sample_level = source_phase[23] ? 8'd82 : 8'd112;
                end else begin
                    sample_level = 8'd43;
                end
            end
        end
    endtask

    initial begin
        source_phase = 0;
        output_pixels = 0;
        completed_lines = 0;
        repeat (8) @(posedge clk);
        reset = 1'b0;

        @(negedge clk);
        vsync_pulse = 1'b1;
        @(negedge clk);
        vsync_pulse = 1'b0;

        for (line_number = 0; line_number < 36;
             line_number = line_number + 1)
            drive_line;

        repeat (20) @(posedge clk);

        if (!field_toggle)
            $fatal(1, "field toggle was not produced");
        if (!color_locked)
            $fatal(1, "burst detector did not reach color lock");
        if (completed_lines < 12)
            $fatal(1, "too few active lines completed: %0d", completed_lines);
        if (output_pixels != completed_lines * 640)
            $fatal(1, "pixel count mismatch: pixels=%0d lines=%0d",
                   output_pixels, completed_lines);

        $display("PASS ntsc_color_decoder pixels=%0d lines=%0d rgb565=%h",
                 output_pixels, completed_lines, pixel_rgb565);
        $finish;
    end
endmodule
