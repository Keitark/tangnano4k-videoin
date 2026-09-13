`timescale 1ns/1ps
module tb_delta_modulator_core;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg comparator_bit = 1'b0;
    wire feedback_bit;
    wire [7:0] reconstructed_level;
    wire sample_strobe;
    wire inverted_feedback_bit;
    wire [7:0] inverted_level;
    wire inverted_strobe;
    wire forced_high_feedback_bit;
    wire [7:0] forced_high_level;
    wire forced_high_strobe;
    integer i;

    always #5 clk = ~clk;

    delta_modulator_core dut (
        .clk(clk),
        .reset(reset),
        .comparator_bit(comparator_bit),
        .feedback_bit(feedback_bit),
        .reconstructed_level(reconstructed_level),
        .sample_strobe(sample_strobe)
    );

    delta_modulator_core #(
        .INVERT_COMPARATOR(1)
    ) inverted_dut (
        .clk(clk),
        .reset(reset),
        .comparator_bit(comparator_bit),
        .feedback_bit(inverted_feedback_bit),
        .reconstructed_level(inverted_level),
        .sample_strobe(inverted_strobe)
    );

    delta_modulator_core #(
        .FORCE_FEEDBACK(1),
        .FORCED_FEEDBACK_VALUE(1)
    ) forced_high_dut (
        .clk(clk),
        .reset(reset),
        .comparator_bit(comparator_bit),
        .feedback_bit(forced_high_feedback_bit),
        .reconstructed_level(forced_high_level),
        .sample_strobe(forced_high_strobe)
    );

    task drive_quarter_density;
        input integer cycles;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(negedge clk);
                comparator_bit = ((i & 3) == 0);
            end
        end
    endtask

    task drive_three_quarter_density;
        input integer cycles;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(negedge clk);
                comparator_bit = ((i & 3) != 0);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        reset = 1'b0;

        @(negedge clk);
        comparator_bit = 1'b1;
        @(posedge clk);
        #1;
        if (feedback_bit !== 1'b1)
            $fatal(1, "registered feedback did not follow comparator");
        if (inverted_feedback_bit !== 1'b0)
            $fatal(1, "inverted feedback did not oppose comparator");
        if (forced_high_feedback_bit !== 1'b1)
            $fatal(1, "forced-high feedback was not high");

        @(negedge clk);
        comparator_bit = 1'b0;
        @(posedge clk);
        #1;
        if (forced_high_feedback_bit !== 1'b1)
            $fatal(1, "forced-high feedback followed comparator low");

        drive_quarter_density(1024);
        repeat (8) @(posedge clk);
        if ((reconstructed_level < 8'd56) ||
            (reconstructed_level > 8'd72))
            $fatal(1, "quarter-density level out of range: %0d",
                   reconstructed_level);

        drive_three_quarter_density(1024);
        repeat (8) @(posedge clk);
        if ((reconstructed_level < 8'd184) ||
            (reconstructed_level > 8'd200))
            $fatal(1, "three-quarter-density level out of range: %0d",
                   reconstructed_level);
        if ((inverted_level < 8'd56) || (inverted_level > 8'd72))
            $fatal(1, "inverted quarter-density level out of range: %0d",
                   inverted_level);

        $display("PASS delta_modulator_core level=%0d inverted=%0d",
                 reconstructed_level, inverted_level);
        $finish;
    end
endmodule
