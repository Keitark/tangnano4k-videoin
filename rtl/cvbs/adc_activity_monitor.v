module adc_activity_monitor #(
    parameter integer WINDOW_BITS = 12,
    parameter integer MIN_SPAN = 12,
    parameter integer USE_SAMPLE_ENABLE = 0
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       sample_enable,
    input  wire [7:0] level,
    output reg        activity,
    output reg  [7:0] reported_min,
    output reg  [7:0] reported_max
);
    wire advance = !USE_SAMPLE_ENABLE || sample_enable;
    reg [WINDOW_BITS-1:0] sample_count;
    reg [7:0] window_min;
    reg [7:0] window_max;

    always @(posedge clk) begin
        if (reset) begin
            sample_count <= {WINDOW_BITS{1'b0}};
            window_min <= 8'hff;
            window_max <= 8'h00;
            activity <= 1'b0;
            reported_min <= 8'h00;
            reported_max <= 8'h00;
        end else if (advance && &sample_count) begin
            activity <= (window_max - window_min) >= MIN_SPAN;
            reported_min <= window_min;
            reported_max <= window_max;
            sample_count <= {WINDOW_BITS{1'b0}};
            window_min <= level;
            window_max <= level;
        end else if (advance) begin
            sample_count <= sample_count + 1'b1;
            if (level < window_min)
                window_min <= level;
            if (level > window_max)
                window_max <= level;
        end
    end
endmodule
