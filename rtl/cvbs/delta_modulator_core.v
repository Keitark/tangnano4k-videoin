module delta_modulator_core #(
    parameter integer INVERT_COMPARATOR = 0,
    parameter integer FORCE_FEEDBACK = 0,
    parameter integer FORCED_FEEDBACK_VALUE = 0,
    parameter integer USE_REFERENCE_DSM = 0,
    parameter integer REFERENCE_DENSITY = 0,
    parameter integer REFERENCE_HALF_STEP = 0,
    parameter integer LEVEL_SHIFT = 2,
    parameter integer WIDE_CIC2 = 0
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       comparator_bit,
    output reg        feedback_bit,
    output reg  [7:0] reconstructed_level,
    output reg  [7:0] wide_reconstructed_level,
    output reg        sample_strobe
);
    reg [63:0] history;
    reg [6:0] ones_count;
    reg [4:0] wide_ones_count;
    // Optional second moving sum BEFORE downsampling. The original 16-bit
    // box count remains unchanged for rollback and analog feedback is untouched.
    reg [4:0] wide_counts[0:15];
    reg [8:0] wide_sum;
    integer wi;
    reg [2:0] decimate_count;
    reg [7:0] reference_accumulator;
    reg reference_half_phase;
    // The asynchronous comparator must never feed a counter carry chain.
    // Keep feedback latency unchanged, but let the measurement bit settle
    // through two registers before using the same bit for history and count.
    reg measurement_meta;
    reg measurement_bit;
    wire normalized_bit = comparator_bit ^ INVERT_COMPARATOR[0];
    wire [6:0] next_ones = ones_count - history[63] + measurement_bit;
    wire [4:0] next_wide_ones = wide_ones_count - history[15] + measurement_bit;
    // Fixed tail avoids a 16:1 mux on the 108MHz accumulator path. Use the
    // registered first-stage count to avoid cascading both stages' carry chains.
    wire [8:0] next_wide_sum=wide_sum-wide_counts[15]+wide_ones_count;
    wire [13:0] next_scaled_level = {7'b0, next_ones} << LEVEL_SHIFT;
    wire [7:0] next_level = (|next_scaled_level[13:8]) ?
                            8'hff : next_scaled_level[7:0];
    wire [8:0] reference_sum = {1'b0, reference_accumulator} +
                               REFERENCE_DENSITY[7:0] +
                               (REFERENCE_HALF_STEP[0] &
                                reference_half_phase);

    always @(posedge clk) begin
        if (reset) begin
            feedback_bit <= 1'b0;
            measurement_meta <= 1'b0;
            measurement_bit <= 1'b0;
            history <= 64'b0;
            ones_count <= 7'b0;
            wide_ones_count <= 0;
            wide_sum<=0;
            for(wi=0;wi<16;wi=wi+1) wide_counts[wi]<=0;
            wide_reconstructed_level <= 0;
            decimate_count <= 3'b0;
            reference_accumulator <= 8'b0;
            reference_half_phase <= 1'b0;
            reconstructed_level <= 8'b0;
            sample_strobe <= 1'b0;
        end else begin
            measurement_meta <= normalized_bit;
            measurement_bit <= measurement_meta;
            // Normalize the comparator polarity before both driving the
            // external one-bit DAC and estimating its density.  The default
            // preserves the original loop; the inverted diagnostic variant
            // tests the opposite LVDS/comparator polarity on hardware.
            feedback_bit <= FORCE_FEEDBACK ?
                            FORCED_FEEDBACK_VALUE[0] :
                            (USE_REFERENCE_DSM ? reference_sum[8] :
                             normalized_bit);
            reference_accumulator <= reference_sum[7:0];
            reference_half_phase <= ~reference_half_phase;
            history <= {history[62:0], measurement_bit};
            ones_count <= next_ones;
            wide_ones_count <= next_wide_ones;
            wide_counts[0]<=wide_ones_count;
            for(wi=1;wi<16;wi=wi+1) wide_counts[wi]<=wide_counts[wi-1];
            wide_sum<=next_wide_sum;
            sample_strobe <= 1'b0;

            if (decimate_count == 3'd7) begin
                decimate_count <= 3'd0;
                reconstructed_level <= next_level;
                // Separate 16-sample picture estimate; retain the original
                // 64-sample output for sync. Both use the same settled bit.
                wide_reconstructed_level <= WIDE_CIC2 ?
                    (next_wide_sum[8] ? 8'hff : next_wide_sum[7:0]) :
                    (next_wide_ones[4] ? 8'hff : {next_wide_ones[3:0],4'b0});
                sample_strobe <= 1'b1;

            end else begin
                decimate_count <= decimate_count + 1'b1;
            end
        end
    end
endmodule
