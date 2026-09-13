# Pre-downsampling picture filtering — 2026-09-13

Previous goal turn: progress (verified continuous color and improved filtering).
Current baseline from checkpoint: EF43, three-line320x240 RGB565, all885 frames
valid/color-locked and zero underflows in `20260913_231948`; fine texture and
edge fringing remain. Root AGENTS.md re-read. No relevant memory entry found.

## Evidence-backed next hypothesis

The ADC picture path previously decimated a 16-bit population count to13.5MHz,
giving17 possible codes including saturation. Extra filtering only AFTER
decimation cannot remove noise already folded into the picture band.
Add optional `WIDE_CIC2`: second16-sample moving sum at108MHz, with registered
first-stage count and fixed shift-register tail. This changes only reconstructed
picture samples. Comparator feedback,narrow64-bit sync filter,strobe and clocks
remain unchanged. Three line buffers remain unchanged.

Linear-filter prediction (not a hardware measurement): carrier gain of the
16-tap box is0.59860 at3.579545MHz; cascade gives0.35833. Therefore chroma
amplitude will drop unless compensated later. Additional filter group delay
7.5 ADC clocks plus one pipeline clock=78.70ns. Burst locking must absorb that
fixed delay. Do not claim that extra output precision equals ADC effective bits.

`tb_delta_cic2`:1250 decimated samples checked against independent exact
triangular weights over zero,full-scale and random bit patterns. Every fast
clock also checks unchanged feedback,narrow samples and strobe against legacy.
PASS.

Initial circular-history build `ntsc_three_line320_cic2_c6` was NOT programmed:
15 setup violations,worst-1.646ns at history mux/accumulator. Changed to fixed
tail shift-register and registered input; no timing exceptions were added.

`build/ntsc_three_line320_cic2_shift_c6/impl/pnr/project.fs`, SHA256
`1F3EC284BF058A017B4A9A0CC6D2A684C9C9D20CC962FF6B5D9694787A3D4CA4`:
2939 logic,1590 registers,3 SDPB,2 MULT18X18,setup/hold0. Sipeed gates passed,
SRAM usercode50BA/status3F020/Finished. Log
`build/monochrome_recovery/three_line320_cic2_shift_program.log`.

Added saved-video metric `tools/analyze_picture_quality.py`: fixed left-border
ROI x30..54,y40..329,median high-frequency luma residual RMS across every15th
valid color frame. Baseline EF43=3.630 codes (59 sampled frames). This is NOT
electrical SNR or a resolution test; capture compression/source texture can
contribute. Keep ROI and procedure fixed between trials.

## Hardware result

Capture `20260913_232914`:590/590 valid,color-locked,H-locked,frame-valid;
zero capture failures/underflows. Fixed-border residual RMS1.734 codes.
Repeat capture `20260913_233210`:891/891 same valid/lock status,zero failures
or underflows,RMS1.739 codes. Compared with baseline3.630,this is about52%
less residual RMS in the identical ROI, not a claimed electrical-SNR gain.

Across all1481 frames,the red-object detector finds>5000 red-dominant pixels
per frame;centroid spans approximatelyx100..500,y114..378. Frame-start counters
always advance between captured frames (increments1/2/3 at the30fps capture of
~60fps HDMI),with no repeated counter values. Thus the observed picture is not
a static held image. First/last/representative actual camera images inspected:
clear checkerboard ball,stable straight grid,brick-red/white checks and purple
grid. Fine composite edge fringe remains; no calibrated-color claim is made.

Current RTL regressions: legacy delta core;10000 measurement-CDC count checks;
subcarrier bandwidth;CIC2 exact arithmetic;three-line video1174848 pixel/line-ID
checks across4 fields with0 underflows/0drops/0bad lines. All PASS.
Current/rollback FS hashes rechecked. Matrix and CIC2 physical pin reports differ
only in build path/timestamp,not pin mapping or electrical configuration.
