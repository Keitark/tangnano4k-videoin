module nano4k_cvbs_hdmi_clocks (
    input  wire clk_27m,
    input  wire reset,
    output wire clk_adc_108m,
    output wire clk_sample_13m5,
    output wire clk_tmds_126m,
    output wire clk_pixel_25m2,
    output wire locked
);
    wire adc_lock;
    wire hdmi_lock;
    wire unused_adc_p;
    wire unused_adc_d3;
    wire unused_hdmi_p;
    wire unused_hdmi_d;
    wire unused_hdmi_d3;
    wire gnd = 1'b0;
    wire vcc = 1'b1;

    // 27 MHz * 4 = 108 MHz. ODIV keeps the internal VCO at 864 MHz.
    PLLVR pll_adc (
        .CLKOUT(clk_adc_108m), .LOCK(adc_lock), .CLKOUTP(unused_adc_p),
        .CLKOUTD(clk_sample_13m5), .CLKOUTD3(unused_adc_d3),
        .RESET(reset), .RESET_P(gnd), .CLKIN(clk_27m), .CLKFB(gnd),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0), .VREN(vcc)
    );
    defparam pll_adc.FCLKIN = "27";
    defparam pll_adc.IDIV_SEL = 0;
    defparam pll_adc.FBDIV_SEL = 3;
    defparam pll_adc.ODIV_SEL = 8;
    defparam pll_adc.DYN_IDIV_SEL = "false";
    defparam pll_adc.DYN_FBDIV_SEL = "false";
    defparam pll_adc.DYN_ODIV_SEL = "false";
    defparam pll_adc.DYN_DA_EN = "false";
    defparam pll_adc.PSDA_SEL = "0000";
    defparam pll_adc.DUTYDA_SEL = "1000";
    defparam pll_adc.CLKFB_SEL = "internal";
    defparam pll_adc.CLKOUT_BYPASS = "false";
    defparam pll_adc.CLKOUTD_BYPASS = "false";
    defparam pll_adc.CLKOUTD_SRC = "CLKOUT";
    defparam pll_adc.DYN_SDIV_SEL = 8;
    defparam pll_adc.DEVICE = "GW1NSR-4C";

    // Official Nano 4K HDMI example clock: 126 MHz serial and /5 = 25.2 MHz
    // pixel clock for monitor-friendly 640x480p60 timing.
    PLLVR pll_hdmi (
        .CLKOUT(clk_tmds_126m), .LOCK(hdmi_lock), .CLKOUTP(unused_hdmi_p),
        .CLKOUTD(unused_hdmi_d), .CLKOUTD3(unused_hdmi_d3),
        .RESET(reset), .RESET_P(gnd), .CLKIN(clk_27m), .CLKFB(gnd),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0), .VREN(vcc)
    );
    defparam pll_hdmi.FCLKIN = "27";
    defparam pll_hdmi.IDIV_SEL = 2;
    defparam pll_hdmi.FBDIV_SEL = 13;
    defparam pll_hdmi.ODIV_SEL = 8;
    defparam pll_hdmi.DYN_IDIV_SEL = "false";
    defparam pll_hdmi.DYN_FBDIV_SEL = "false";
    defparam pll_hdmi.DYN_ODIV_SEL = "false";
    defparam pll_hdmi.DYN_DA_EN = "true";
    defparam pll_hdmi.PSDA_SEL = "0000";
    defparam pll_hdmi.DUTYDA_SEL = "1000";
    defparam pll_hdmi.CLKOUT_FT_DIR = 1'b1;
    defparam pll_hdmi.CLKOUTP_FT_DIR = 1'b1;
    defparam pll_hdmi.CLKOUT_DLY_STEP = 0;
    defparam pll_hdmi.CLKOUTP_DLY_STEP = 0;
    defparam pll_hdmi.CLKFB_SEL = "internal";
    defparam pll_hdmi.CLKOUT_BYPASS = "false";
    defparam pll_hdmi.DEVICE = "GW1NSR-4C";

    CLKDIV pixel_div (
        .CLKOUT(clk_pixel_25m2),
        .HCLKIN(clk_tmds_126m),
        .RESETN(hdmi_lock),
        .CALIB(gnd)
    );
    defparam pixel_div.DIV_MODE = "5";
    defparam pixel_div.GSREN = "false";

    assign locked = adc_lock & hdmi_lock;
endmodule
