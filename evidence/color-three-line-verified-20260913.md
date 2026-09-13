# Verified live three-line color — 2026-09-13

## Result and scope

The reduced-parts LVDS front end now produces a clear,stable,recognizable
Boing Ball color image at320x240 RGB565,scaled2x to640x480 HDMI,using three line
banks and no complete-frame buffer. Brick-red/white ball checks and purple grid
are visible in the actual live captures. This meets the current live-color HDMI
goal at this resolution. It is not a calibrated/lossless digitizer: small analog
edge fringes remain. Native FPGA USB-UVC output is NOT claimed by this milestone;
FY HD Video is the external HDMI capture device.

## Loaded bitstream

- `F:/dev/tangnano4k_videoin/build/ntsc_three_line320_cic2_shift_c6/impl/pnr/project.fs`
- SHA256 `1F3EC284BF058A017B4A9A0CC6D2A684C9C9D20CC962FF6B5D9694787A3D4CA4`
- Volatile SRAM,usercode50BA,status3F020,Finished. No flash write.
- Gowin1.9.8, targetGW1NSR-LV4CQN48PC6/I5.
- 2939/4608 logic,1590/3573 registers,3 SDPB,2 MULT18X18,setup/hold violations0.
- Selector `NTSC_RUNTIME_PROBE=line320_cic2`; set a new absolute
  `NTSC_BUILD_ROOT` and invoke Gowin gw_sh on `tools/build_ntsc_hdmi_c6.tcl`.

## Requirement-by-requirement completion audit

| Requirement | Current authoritative evidence |
|---|---|
| Actual decoded Boing Ball,color and clear structure | Camera first/last/representative PNGs in `build/fy_capture_check/20260913_232914` and `20260913_233210`; red/white checkerboard and grid visually resolved,not generated test bars |
| Stable moving picture | 590+891 captured frames,every frame health/status valid,H-locked,color-locked,frame-valid;0 read failures and0 underflows;red-object centroid moves across the screen and frame-start counter always advances |
| Noise improvement without substituting a static/monochrome picture | Same fixed-border residual RMS3.630 before versus1.734/1.739 after;all1481 frames color-selected;red object present in each frame |
| Reduced-parts approach and unchanged wiring | Same TLVDS39/40 input and feedback16; physical pin report unchanged; no electrical/driver/hub/wiring changes made |
| Three-line buffering | Routed report3 SDPB; full-frame store swept; `tb_three_line_video` checks1174848 exact pixels/line IDs,4 fields,zero drops/bad lines/underflows |
| Preserve analog feedback and sync | `tb_delta_cic2` checks each clock against legacy feedback,narrow sync and strobe; only picture reconstruction opts into second pre-decimation sum |
| Required programming safety | `build/monochrome_recovery/three_line320_cic2_shift_program.log`: Sipeed1.9.11.02 build2518 hash0CBB56027B0DED80F92895C979A9B6D727BBC3E7CF000366B8EB07DA71876DD1;A/B oem69.inf,COM8 oem96.inf,all2.12.36.20;UsbMonitor disabled,noFTDI owner,cable discovery,JTAG0100981B,target/timing/hash gates;2.5MHz,SRAM operation16 |
| Rollback preserved | EF43 matrix,D1C6 continuous and88F9 initial three-line FS hashes rechecked unchanged; exact hashes in prior checkpoint/evidence |
| Honest independent evidence | Status parser rejects missing health bar,including earlier black capture; no claim that counters alone prove hue/clarity; current image inspected and limitation retained |

## Tests and viewing

ADC legacy/CDC/bandwidth/CIC2 tests pass; prior CLEAN4 independent NTSC
red/cyan/blue/yellow encoder tests pass. Three-line queue/video tests pass.
Source files used by the current build have not changed since it was built.
Camera capture process completed and released FY HD Video; OBS may open it.

Latest actual screenshot:
`build/fy_capture_check/20260913_233210/last.png`.
30-second recording: same directory,`capture.avi`.
Full filter/results record: `evidence/color-noise-improvement-20260913.md`.

One earlier different build had an unexplained black startup/capture and worked
on exact-image retry. Do not call that a repaired driver/clock fault. Current
bitstream passed both captures. For future programming,retain all AGENTS.md gates
and use the existing verified helper; do not alter drivers or write flash.
