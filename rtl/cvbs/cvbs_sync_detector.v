module cvbs_sync_detector #(
    parameter integer COUNTER_WIDTH = 13,
    parameter integer HSYNC_MIN_SAMPLES = 100,
    parameter integer HSYNC_MAX_SAMPLES = 180,
    parameter integer VSYNC_MIN_SAMPLES = 540,
    parameter integer LINE_MIN_SAMPLES = 1600,
    parameter integer LINE_MAX_SAMPLES = 1850,
    parameter integer LOCK_LINES = 8
) (
    input  wire                         clk,
    input  wire                         reset,
    input  wire                         sync_sample,
    output reg                          hsync_pulse,
    output reg                          vsync_pulse,
    output reg                          line_locked,
    output reg  [COUNTER_WIDTH-1:0]     measured_low_samples,
    output reg  [COUNTER_WIDTH-1:0]     measured_line_samples
);
    reg sync_meta;
    reg sync_in;
    reg sync_previous;
    reg [COUNTER_WIDTH-1:0] low_count;
    reg [COUNTER_WIDTH-1:0] line_count;
    reg [3:0] stable_line_count;
    reg seen_hsync;

    wire sync_rising = sync_in & ~sync_previous;

    // The analog front end must make sync_sample low only when CVBS is below
    // its sync-separation threshold. The two registers contain metastability
    // before pulse widths are measured in this clock domain.
    always @(posedge clk) begin
        if (reset) begin
            sync_meta <= 1'b1;
            sync_in <= 1'b1;
            sync_previous <= 1'b1;
            low_count <= {COUNTER_WIDTH{1'b0}};
            line_count <= {COUNTER_WIDTH{1'b0}};
            stable_line_count <= 4'd0;
            seen_hsync <= 1'b0;
            hsync_pulse <= 1'b0;
            vsync_pulse <= 1'b0;
            line_locked <= 1'b0;
            measured_low_samples <= {COUNTER_WIDTH{1'b0}};
            measured_line_samples <= {COUNTER_WIDTH{1'b0}};
        end else begin
            sync_meta <= sync_sample;
            sync_in <= sync_meta;
            sync_previous <= sync_in;
            hsync_pulse <= 1'b0;
            vsync_pulse <= 1'b0;

            if (!sync_in) begin
                if (low_count != {COUNTER_WIDTH{1'b1}})
                    low_count <= low_count + 1'b1;
            end else begin
                low_count <= {COUNTER_WIDTH{1'b0}};
            end

            if (line_count != {COUNTER_WIDTH{1'b1}})
                line_count <= line_count + 1'b1;

            if (sync_rising) begin
                measured_low_samples <= low_count;

                if (low_count >= VSYNC_MIN_SAMPLES) begin
                    vsync_pulse <= 1'b1;
                end else if ((low_count >= HSYNC_MIN_SAMPLES) &&
                             (low_count <= HSYNC_MAX_SAMPLES)) begin
                    hsync_pulse <= 1'b1;
                    measured_line_samples <= line_count;
                    line_count <= {COUNTER_WIDTH{1'b0}};

                    if (!seen_hsync) begin
                        seen_hsync <= 1'b1;
                        stable_line_count <= 4'd0;
                    end else if ((line_count >= LINE_MIN_SAMPLES) &&
                                 (line_count <= LINE_MAX_SAMPLES)) begin
                        if (stable_line_count < LOCK_LINES)
                            stable_line_count <= stable_line_count + 1'b1;
                        if (stable_line_count >= LOCK_LINES - 1)
                            line_locked <= 1'b1;
                    end else begin
                        stable_line_count <= 4'd0;
                        line_locked <= 1'b0;
                    end
                end
            end

            // Drop lock if ordinary horizontal sync has been absent for more
            // than two maximum line periods. Vertical-sync classification is
            // still reported independently during this interval.
            if (line_count > (LINE_MAX_SAMPLES * 2)) begin
                stable_line_count <= 4'd0;
                line_locked <= 1'b0;
                seen_hsync <= 1'b0;
            end
        end
    end
endmodule
