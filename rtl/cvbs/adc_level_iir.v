module adc_level_iir #(
    parameter integer FILTER_SHIFT = 5
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       sample_enable,
    input  wire [7:0] level_in,
    output wire [7:0] level_out
);
    localparam integer ACCUM_BITS = 8 + FILTER_SHIFT;

    reg [ACCUM_BITS-1:0] level_accumulator;
    wire [7:0] current_level =
        level_accumulator[ACCUM_BITS-1:FILTER_SHIFT];
    wire [ACCUM_BITS:0] current_level_extended =
        {{(FILTER_SHIFT + 1){1'b0}}, current_level};
    wire [ACCUM_BITS:0] input_level_extended =
        {{(FILTER_SHIFT + 1){1'b0}}, level_in};
    wire [ACCUM_BITS:0] next_accumulator =
        {1'b0, level_accumulator} - current_level_extended +
        input_level_extended;

    always @(posedge clk) begin
        if (reset)
            level_accumulator <= {ACCUM_BITS{1'b0}};
        else if (sample_enable)
            level_accumulator <= next_accumulator[ACCUM_BITS-1:0];
    end

    assign level_out = current_level;
endmodule
