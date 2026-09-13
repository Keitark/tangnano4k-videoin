module adc_level_boxcar #(
    parameter integer TAP_BITS = 4
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       sample_enable,
    input  wire [7:0] level_in,
    output reg  [7:0] level_out
);
    localparam integer TAP_COUNT = 1 << TAP_BITS;
    localparam integer SUM_BITS = 8 + TAP_BITS;

    reg [7:0] history [0:TAP_COUNT-1];
    reg [TAP_BITS-1:0] write_index;
    reg [SUM_BITS-1:0] level_sum;
    integer index;

    wire [SUM_BITS:0] next_sum =
        {1'b0, level_sum} - history[write_index] + level_in;

    always @(posedge clk) begin
        if (reset) begin
            write_index <= {TAP_BITS{1'b0}};
            level_sum <= {SUM_BITS{1'b0}};
            level_out <= 8'h00;
            for (index = 0; index < TAP_COUNT; index = index + 1)
                history[index] <= 8'h00;
        end else if (sample_enable) begin
            history[write_index] <= level_in;
            write_index <= write_index + 1'b1;
            level_sum <= next_sum[SUM_BITS-1:0];
            level_out <= next_sum[SUM_BITS-1:TAP_BITS];
        end
    end
endmodule
