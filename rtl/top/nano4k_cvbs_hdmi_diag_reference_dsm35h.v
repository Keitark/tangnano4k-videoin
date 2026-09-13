module nano4k_cvbs_hdmi_diag_reference_dsm35h (
    input  wire       clk_27m,
    input  wire       reset_n,
    input  wire       video_p,
    input  wire       video_n,
    output wire       adc_feedback,
    output wire       led,
    output wire       tmds_clk_n,
    output wire       tmds_clk_p,
    output wire [2:0] tmds_d_n,
    output wire [2:0] tmds_d_p
);
    nano4k_cvbs_hdmi_diag_feedback_high #(
        .FEEDBACK_MODE(2),
        .REFERENCE_DENSITY(35),
        .REFERENCE_HALF_STEP(1)
    ) u_probe (
        .clk_27m(clk_27m),
        .reset_n(reset_n),
        .video_p(video_p),
        .video_n(video_n),
        .adc_feedback(adc_feedback),
        .led(led),
        .tmds_clk_n(tmds_clk_n),
        .tmds_clk_p(tmds_clk_p),
        .tmds_d_n(tmds_d_n),
        .tmds_d_p(tmds_d_p)
    );
endmodule
