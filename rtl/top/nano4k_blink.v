module nano4k_blink (
    input  wire clk_27m,
    output wire led
);
    reg [23:0] counter = 24'd0;

    always @(posedge clk_27m)
        counter <= counter + 1'b1;

    // The onboard LED is active-low. Bit 23 gives a visible period of
    // approximately 0.62 seconds from the 27 MHz board oscillator.
    assign led = ~counter[23];
endmodule
