module lvds_delta_adc #(
    parameter integer INVERT_COMPARATOR = 0,
    parameter integer FORCE_FEEDBACK = 0,
    parameter integer FORCED_FEEDBACK_VALUE = 0,
    parameter integer USE_REFERENCE_DSM = 0,
    parameter integer REFERENCE_DENSITY = 0,
    parameter integer REFERENCE_HALF_STEP = 0,
    parameter integer LEVEL_SHIFT = 2,
    parameter integer WIDE_CIC2 = 0
) (
    input  wire       clk_adc,
    input  wire       reset,
    input  wire       video_p,
    input  wire       video_n,
    output wire       feedback_out,
    output wire [7:0] reconstructed_level,
    output wire [7:0] wide_reconstructed_level,
    output wire       sample_strobe
);
    wire comparator_bit;
    wire feedback_bit;

    // Non-terminated true-LVDS input. External feedback is not an LVDS
    // transmission line, so the optional 100-ohm termination stays disabled.
    TLVDS_IBUF input_comparator (
        .O(comparator_bit),
        .I(video_p),
        .IB(video_n)
    );

    delta_modulator_core #(
        .INVERT_COMPARATOR(INVERT_COMPARATOR),
        .FORCE_FEEDBACK(FORCE_FEEDBACK),
        .FORCED_FEEDBACK_VALUE(FORCED_FEEDBACK_VALUE),
        .USE_REFERENCE_DSM(USE_REFERENCE_DSM),
        .REFERENCE_DENSITY(REFERENCE_DENSITY),
        .REFERENCE_HALF_STEP(REFERENCE_HALF_STEP),
        .LEVEL_SHIFT(LEVEL_SHIFT), .WIDE_CIC2(WIDE_CIC2)
    ) core (
        .clk(clk_adc),
        .reset(reset),
        .comparator_bit(comparator_bit),
        .feedback_bit(feedback_bit),
        .reconstructed_level(reconstructed_level),
        .wide_reconstructed_level(wide_reconstructed_level),
        .sample_strobe(sample_strobe)
    );

    assign feedback_out = feedback_bit;
endmodule
