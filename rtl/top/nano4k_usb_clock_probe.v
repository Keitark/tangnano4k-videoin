module nano4k_usb_clock_probe (
    input  wire clk_27m,
    input  wire reset_n,
    output wire led
);
    wire clk_120m;
    wire clk_480m;
    wire clk_60m;
    wire clocks_locked;
    reg [25:0] heartbeat;

    nano4k_usb_clocks clocks (
        .clk_27m(clk_27m), .reset(~reset_n),
        .clk_120m(clk_120m), .clk_480m(clk_480m), .clk_60m(clk_60m),
        .locked(clocks_locked)
    );

    always @(posedge clk_60m or negedge clocks_locked) begin
        if (!clocks_locked)
            heartbeat <= 0;
        else
            heartbeat <= heartbeat + 1'b1;
    end

    assign led = ~heartbeat[25];
endmodule

