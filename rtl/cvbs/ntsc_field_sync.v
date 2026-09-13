// Field marker from broad low sync intervals, clocked at 13.5MHz.
// Accept both half-line serrations and the longer pulses from 240p consoles.
// One marker per field; an indefinitely low/disconnected input is not a field.
module ntsc_field_sync (
    input wire clk, reset, sync_in,
    output reg field_pulse
);
    reg [10:0] low_count;
    reg [17:0] field_age;
    always @(posedge clk) begin
        if (reset) begin
            low_count <= 0;
            field_age <= 18'h3ffff;
            field_pulse <= 0;
        end else begin
            field_pulse <= 0;
            if (!(&field_age)) field_age <= field_age + 1'b1;
            if (!sync_in) begin
                if (!(&low_count)) low_count <= low_count + 1'b1;
            end else begin
                low_count <= 0;
                if ((low_count >= 11'd200) && (low_count <= 11'd1000) &&
                    (field_age >= 18'd180000)) begin
                    field_pulse <= 1;
                    field_age <= 0;
                end
            end
        end
    end
endmodule
