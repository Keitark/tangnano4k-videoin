module nano4k_usb_clocks (
    input  wire clk_27m,
    input  wire reset,
    output wire clk_120m,
    output wire clk_480m,
    output wire clk_60m,
    output wire locked
);
    wire pll_a_lock;
    wire pll_b_lock;
    wire pll_a_reset = reset;
    wire pll_b_reset = reset | ~pll_a_lock;
    wire unused_a_p;
    wire unused_a_d;
    wire unused_a_d3;
    wire unused_b_p;
    wire unused_b_d3;
    wire gnd = 1'b0;
    wire vcc = 1'b1;

    // 27 MHz * 40 / 9 = 120 MHz. ODIV keeps the internal VCO at 960 MHz.
    PLLVR pll_27_to_120 (
        .CLKOUT(clk_120m), .LOCK(pll_a_lock), .CLKOUTP(unused_a_p),
        .CLKOUTD(unused_a_d), .CLKOUTD3(unused_a_d3),
        .RESET(pll_a_reset), .RESET_P(gnd), .CLKIN(clk_27m), .CLKFB(gnd),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0), .VREN(vcc)
    );
    defparam pll_27_to_120.FCLKIN = "27";
    defparam pll_27_to_120.IDIV_SEL = 8;
    defparam pll_27_to_120.FBDIV_SEL = 39;
    defparam pll_27_to_120.ODIV_SEL = 8;
    defparam pll_27_to_120.DYN_IDIV_SEL = "false";
    defparam pll_27_to_120.DYN_FBDIV_SEL = "false";
    defparam pll_27_to_120.DYN_ODIV_SEL = "false";
    defparam pll_27_to_120.DYN_DA_EN = "false";
    defparam pll_27_to_120.PSDA_SEL = "0000";
    defparam pll_27_to_120.DUTYDA_SEL = "1000";
    defparam pll_27_to_120.CLKFB_SEL = "internal";
    defparam pll_27_to_120.CLKOUT_BYPASS = "false";
    defparam pll_27_to_120.CLKOUTD_BYPASS = "false";
    defparam pll_27_to_120.DEVICE = "GW1NSR-4C";

    // 120 MHz * 4 = 480 MHz; CLKOUTD / 8 supplies the UTMI 60 MHz clock.
    PLLVR pll_120_to_480 (
        .CLKOUT(clk_480m), .LOCK(pll_b_lock), .CLKOUTP(unused_b_p),
        .CLKOUTD(clk_60m), .CLKOUTD3(unused_b_d3),
        .RESET(pll_b_reset), .RESET_P(gnd), .CLKIN(clk_120m), .CLKFB(gnd),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0), .VREN(vcc)
    );
    defparam pll_120_to_480.FCLKIN = "120";
    defparam pll_120_to_480.IDIV_SEL = 0;
    defparam pll_120_to_480.FBDIV_SEL = 3;
    defparam pll_120_to_480.ODIV_SEL = 2;
    defparam pll_120_to_480.DYN_IDIV_SEL = "false";
    defparam pll_120_to_480.DYN_FBDIV_SEL = "false";
    defparam pll_120_to_480.DYN_ODIV_SEL = "false";
    defparam pll_120_to_480.DYN_DA_EN = "false";
    defparam pll_120_to_480.PSDA_SEL = "0000";
    defparam pll_120_to_480.DUTYDA_SEL = "1000";
    defparam pll_120_to_480.DYN_SDIV_SEL = 8;
    defparam pll_120_to_480.CLKOUTD_SRC = "CLKOUT";
    defparam pll_120_to_480.CLKFB_SEL = "internal";
    defparam pll_120_to_480.CLKOUT_BYPASS = "false";
    defparam pll_120_to_480.CLKOUTD_BYPASS = "false";
    defparam pll_120_to_480.DEVICE = "GW1NSR-4C";

    assign locked = pll_a_lock & pll_b_lock;
endmodule
