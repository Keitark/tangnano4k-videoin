module lvds_delta_adc_runtime #(
    parameter integer INVERT_COMPARATOR = 0,
    parameter integer LEVEL_SHIFT = 2
) (
    input  wire       clk_adc,
    input  wire       reset,
    input  wire       video_p,
    input  wire       video_n,
    input  wire [7:0] reference_density,
    output wire       feedback_out,
    output wire [7:0] reconstructed_level,
    output wire       sample_strobe
);
    wire comparator_bit;
    wire feedback_bit;

    TLVDS_IBUF input_comparator (
        .O(comparator_bit),
        .I(video_p),
        .IB(video_n)
    );

    delta_modulator_runtime_core #(
        .INVERT_COMPARATOR(INVERT_COMPARATOR),
        .LEVEL_SHIFT(LEVEL_SHIFT)
    ) core (
        .clk(clk_adc),
        .reset(reset),
        .comparator_bit(comparator_bit),
        .reference_density(reference_density),
        .feedback_bit(feedback_bit),
        .reconstructed_level(reconstructed_level),
        .sample_strobe(sample_strobe)
    );

    assign feedback_out = feedback_bit;
endmodule
