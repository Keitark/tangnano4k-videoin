# Three-line color checkpoint — 2026-09-13 23:21 JST

## Current SRAM / viewing

- Bitstream: `build/ntsc_three_line320_matrix_c6/impl/pnr/project.fs`
- SHA256: `13D61D4FAA485A93035515F8B53ACC04B4F25031083A6CDA1D126F761AF1B7B2`
- Usercode EF43, status3F020, Finished; volatile SRAM only.
- Source: NEO FAMI Boing Ball, same analog wiring.
- Output: continuous color,320x240 RGB565, doubled to640x480 HDMI.
- Three line RAM banks, no full-frame buffer. Health/status strip always present.
- FY HD Video camera released after capture; OBS can open it.

## Evidence

`build/fy_capture_check/20260913_231948/`:885 frames/30s,zero capture failures,
all885 health/status-valid,H-locked,color-locked,frame-valid,color-selected;
zero underflows. `last.png`, `line_color.png`, `capture.avi`, `line_status.json`.
Counters validate transport, not perfect color accuracy. The red/white ball is
now recognizable and the image is substantially cleaner than the initial
green/white noisy color trial. Fine texture, edge fringing and grid hue remain
quality work; do not declare the user's crisp-color goal finished.

Gowin1.9.8 targetGW1NSR-LV4CQN48PC6/I5:2881/4608 logic,1486/3573 registers,
3 SDPB,2 MULT18X18,setup/hold violated endpoints0.
Sipeed1.9.11.02 build2518 at2.5MHz; exact hash and fresh driver/JTAG gates in
`build/monochrome_recovery/three_line320_matrix_program.log`.

## Changes

- Wide-input carrier notch and sinusoidal quadrature mixing,16-sample chroma FIR.
- Corrected V-axis sign under the decoder's negative-cosine burst lock.
- Luma [1,2,1]/4 noise filter; color-confidence hysteresis.
- Standard inverse U/V coefficient approximations; continuous-color wrapper.
- Narrow CDC bound now includes synthesis replicas of held line-tag registers.
- Offline status decoder rejects black/no-health-bar video as invalid.

`CLEAN_CHROMA` opt-in cumulative modes:0 legacy,1 notch/FIR and corrected V,
2 add luma filter,3 add color-lock hysteresis,4 use refined RGB matrix.
Earlier immutable bitstreams preserve each tested configuration.

## Reproduce / rollback

Build selector `NTSC_RUNTIME_PROBE=line320_matrix`, separate `NTSC_BUILD_ROOT`,
run `tools/build_ntsc_hdmi_c6.tcl` with required Gowin gw_sh.
Tests: `tools/test_picture_validation.ps1`, `tools/test_line_status.py`,
`tb_three_line_queue`, `tb_three_line_video`.
Final rerun of picture-validation suite passes, including all CLEAN1/2/3/4
arithmetic and180-line red/cyan/blue/yellow encoder tests; status parser passes.
Program only through `tools/program_verified_sram.ps1` with an absolute build
directory, exact expected FS hash and new evidence log. Follow AGENTS.md.

Previous continuous-color rollback:
`build/ntsc_three_line320_color_c6/impl/pnr/project.fs`,
SHA256 `E9554557A9E6AB814566FA4EC613625953C1CD654FA4CF6162DA10D8171A26BA`,
usercodeD1C6;891/891 valid/color-locked frames,zero underflows.

One hysteresis-build programming/capture produced entirely black video,
including status. Rollback recovered immediately; the exact unchanged trial
worked on one retry. Startup/capture reacquisition remains unexplained—do not
claim a clock/driver/root cause. Do not change drivers or hubs to investigate.
Full chronology: `evidence/color-goal-continuation-20260913.md`.
