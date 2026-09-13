module nano4k_line320_matrix (
    input wire clk_27m, reset_n, video_p, video_n,
    output wire adc_feedback, led, tmds_clk_n, tmds_clk_p,
    output wire [2:0] tmds_d_n, tmds_d_p
);
    nano4k_ntsc_hdmi #(.SOURCE_FIELD_SYNC(1), .COLOR_OUTPUT(1), .CLEAN_CHROMA(4),
        .RUNTIME_COLOR(0), .LINE_OUTPUT(1), .LINE_WIDTH(320)) core (
        .clk_27m(clk_27m), .reset_n(reset_n), .video_p(video_p), .video_n(video_n),
        .adc_feedback(adc_feedback), .led(led),
        .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p));
endmodule
