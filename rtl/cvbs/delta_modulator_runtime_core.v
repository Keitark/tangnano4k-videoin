module delta_modulator_runtime_core #(
    parameter integer INVERT_COMPARATOR = 0,
    parameter integer LEVEL_SHIFT = 2
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       comparator_bit,
    input  wire [7:0] reference_density,
    output reg        feedback_bit,
    output reg  [7:0] reconstructed_level,
    output reg        sample_strobe
);
    reg [63:0] history;
    reg [6:0] ones_count;
    reg [2:0] decimate_count;
    reg [7:0] reference_accumulator;

    wire normalized_bit = comparator_bit ^ INVERT_COMPARATOR[0];
    wire [6:0] next_ones = ones_count - history[63] + normalized_bit;
    wire [13:0] next_scaled_level = {7'b0, next_ones} << LEVEL_SHIFT;
    wire [7:0] next_level = (|next_scaled_level[13:8]) ?
                            8'hff : next_scaled_level[7:0];
    wire [8:0] reference_sum = {1'b0, reference_accumulator} +
                               {1'b0, reference_density};

    always @(posedge clk) begin
        if (reset) begin
            feedback_bit <= 1'b0;
            history <= 64'b0;
            ones_count <= 7'b0;
            decimate_count <= 3'b0;
            reference_accumulator <= 8'b0;
            reconstructed_level <= 8'b0;
            sample_strobe <= 1'b0;
        end else begin
            feedback_bit <= reference_sum[8];
            reference_accumulator <= reference_sum[7:0];
            history <= {history[62:0], normalized_bit};
            ones_count <= next_ones;
            sample_strobe <= 1'b0;

            if (decimate_count == 3'd7) begin
                decimate_count <= 3'd0;
                reconstructed_level <= next_level;
                sample_strobe <= 1'b1;
            end else begin
                decimate_count <= decimate_count + 1'b1;
            end
        end
    end
endmodule
