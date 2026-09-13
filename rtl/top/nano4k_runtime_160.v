// 160x120 monochrome resolution trial; source-aligned, startup diagnostics once.
module nano4k_runtime_160 (
    input wire clk_27m, reset_n, video_p, video_n,
    output wire adc_feedback, led, tmds_clk_n, tmds_clk_p,
    output wire [2:0] tmds_d_n, tmds_d_p
);
    nano4k_ntsc_hdmi #(.RUNTIME_PROBE(1), .SOURCE_FIELD_SYNC(1),
                       .PROBE_CYCLE_ONCE(1), .FRAME_WIDTH(160)) core (
        .clk_27m(clk_27m), .reset_n(reset_n), .video_p(video_p), .video_n(video_n),
        .adc_feedback(adc_feedback), .led(led),
        .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p));
endmodule
