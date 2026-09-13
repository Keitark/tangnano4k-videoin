module adc_loop_stats_monitor #(
    parameter integer WINDOW_BITS = 10
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       bit_sample,
    output reg  [7:0] reported_density,
    output reg  [7:0] reported_transitions
);
    reg [WINDOW_BITS-1:0] sample_count;
    reg [WINDOW_BITS-1:0] high_count;
    reg [WINDOW_BITS-1:0] transition_count;
    reg last_sample;

    always @(posedge clk) begin
        if (reset) begin
            sample_count <= {WINDOW_BITS{1'b0}};
            high_count <= {WINDOW_BITS{1'b0}};
            transition_count <= {WINDOW_BITS{1'b0}};
            last_sample <= 1'b0;
            reported_density <= 8'h00;
            reported_transitions <= 8'h00;
        end else begin
            last_sample <= bit_sample;

            if (&sample_count) begin
                // A 1024-clock window maps directly to an 8-bit code by
                // dropping the two least-significant count bits.
                reported_density <= high_count[WINDOW_BITS-1:2];
                reported_transitions <= transition_count[WINDOW_BITS-1:2];
                sample_count <= {WINDOW_BITS{1'b0}};
                high_count <= {{(WINDOW_BITS-1){1'b0}}, bit_sample};
                transition_count <= {{(WINDOW_BITS-1){1'b0}},
                                     bit_sample ^ last_sample};
            end else begin
                sample_count <= sample_count + 1'b1;
                if (bit_sample)
                    high_count <= high_count + 1'b1;
                if (bit_sample ^ last_sample)
                    transition_count <= transition_count + 1'b1;
            end
        end
    end
endmodule
