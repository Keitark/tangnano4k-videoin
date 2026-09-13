// Control experiment: exact RGB332 color memory/output path, but chroma muted.
// Keep the trial's 2x luma gain, timing and split-input reconstruction unchanged.
module nano4k_color_transport_gray (
    input wire clk_27m, reset_n, video_p, video_n,
    output wire adc_feedback, led, tmds_clk_n, tmds_clk_p,
    output wire [2:0] tmds_d_n, tmds_d_p
);
    nano4k_ntsc_hdmi #(.RUNTIME_PROBE(1), .PROBE_CYCLE_ONCE(1),
        .SOURCE_FIELD_SYNC(1), .FRAME_WIDTH(80), .COLOR_OUTPUT(1), .COLOR_DECODE(0)) core (
        .clk_27m(clk_27m), .reset_n(reset_n), .video_p(video_p), .video_n(video_n),
        .adc_feedback(adc_feedback), .led(led),
        .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p));
endmodule
