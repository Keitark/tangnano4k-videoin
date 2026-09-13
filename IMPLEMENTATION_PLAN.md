# Tang Nano 4K composite-to-UVC implementation plan

Status: **NTSC-TO-HDMI BENCH CANDIDATE BUILT — current board treated as C6/I5**

## Inventory result

- Proven hardware build target: `GW1NSR-LV4CQN48PC6/I5`.
- Proven programming route: Sipeed/Gowin Programmer 1.9.11.02 build 2518,
  FTDI 2.12.36.20, channel 0, JTAG at 2.5 MHz, volatile SRAM only.
- Existing RTL before this plan: blink, a two-PLL 120/480/60 MHz clock probe,
  and a synthetic UVC payload/header generator.
- Existing USB state: the installed Gowin toolchain contains encrypted USB 1.1
  SoftPHY, USB 2.0 SoftPHY Slim, and USB 2.0 Device Controller IP. No generated
  project-specific USB IP, descriptor ROM, endpoint scheduler, UVC control
  state machine, or USB pin constraints exist in this repository.
- Existing composite state: architecture prose only. There was no capture,
  sync separator, luma/chroma decoder, line buffer, or composite-input pin
  constraint.
- `.pcba-workflow/circuit-review.md` is preserved as the earlier native-HS
  feasibility review. Its C7/HS assumptions are not approval of the current
  C6/full-speed branch or of an analog front end.

## Hard resource and transport boundaries

The installed Gowin C6 device database and completed builds establish:

| Resource | Device total | Existing clock probe |
|---|---:|---:|
| Logic | 4608 | 27 |
| Logic registers | 3456 | 26 |
| BSRAM | 180 Kbit | 0 |
| DSP | 16 | 0 |
| PLL | 2 | 2 |

The two-PLL probe closes place-and-route on C6/I5, but consuming both PLLs for
a 480 MHz SoftPHY does not establish that the vendor permits HS operation at
this speed grade. Native HS therefore remains a C7/I6-or-faster branch.

The current-board transport branch is USB full speed using the installed USB
1.1 SoftPHY and full-speed mode of the device controller. Full-speed
isochronous payload is at most 1023 bytes per 1 ms USB frame before protocol
overhead. Initial modes are deliberately smaller:

| Mode | Raw YUY2 rate | Decision |
|---|---:|---|
| 160x120 @ 10 fps | 384 kB/s | first advertised target |
| 160x120 @ 15 fps | 576 kB/s | raise only after measured margin |
| 320x240 @ 5 fps | 768 kB/s | later experiment |
| 720x480 @ 29.97 fps | 20.72 MB/s | impossible at full speed |

A full frame buffer does not fit in 180 Kbit BSRAM. The data path must be
streaming and line-buffered. A 720-pixel YUY2 line is 1440 bytes; a 160-pixel
YUY2 line is 320 bytes.

## Front-end decision and safety gate

The first laboratory front end follows the Xilinx-style LVDS delta-modulator
topology: terminated CVBS drives LVDS+, while the registered comparator bit
returns from a 1.8 V GPIO through 2 kohm to LVDS-, with 33 pF from LVDS- to
ground. The RC voltage tracks the input; it is not a fixed DSM reference. The
minimal circuit and current pin choices are documented in
`hardware/cvbs_delta_modulator_afe.md`.

Before connection, the terminated source must be shown to remain within the
DS861 input/common-mode limits. Before color RTL is frozen, bench captures must
prove that the loop follows the composite waveform without slope overload and
that digital filtering reconstructs stable luma and 3.579545 MHz burst
amplitude/phase on real NTSC color bars.

The capacitor value remains a measured parameter: start with 33 pF and retain
22/47/56 pF alternatives. The current sync core consumes a logical one-bit
sample only and does not yet implement the registered feedback loop or physical
pins.

## Staged implementation

1. **Sync core — RTL slice complete.** Classify ordinary horizontal and long
   vertical sync-low intervals at 27 MHz. The synthetic NTSC-like test passes,
   and Gowin synthesis succeeds for C6/I5 without a programmable artifact; see
   `evidence/cvbs-sync-core-synthesis-20260829.md`. Protected-input hardware
   proof remains the next gate.
2. **Delta-modulator hardware proof.** Place the LVDS pair and 1.8 V feedback
   GPIO, measure input/common-mode limits, then load a user-approved SRAM
   diagnostic that proves feedback tracking and reconstructs the composite
   waveform before reporting sync/line lock. No color claim.
3. **Full-speed USB shell.** Generate project-local USB 1.1 SoftPHY and device
   controller IP for C6/I5 with endpoint 1 IN isochronous. Synthesize and record
   hierarchical resource/timing usage before assigning USB pins.
4. **Descriptor/enumeration proof.** Implement a minimal UVC 1.1 descriptor ROM
   and control responses for only 160x120 YUY2 @ 10 fps. Verify Windows
   enumeration through a separate USB connector.
5. **Synthetic video proof.** Feed deterministic YUY2 bars through a one-USB-
   frame-at-a-time endpoint scheduler. Verify FID/EOF sequencing, exact frame
   byte count, and host capture before connecting composite data.
6. **Measured digitizer proof — bench check pending.** Capture and digitally reconstruct monochrome
   bars, then color bars. Freeze the R/C, ADC clock, and reconstruction contract
   only after burst phase, luma levels, slope-overload margin, and
   loss-of-signal behavior are measured.
7. **Streaming decoder — RTL/build complete, bench tuning pending.** The C6/I5
   candidate implements line tracking, a burst-locked NCO, square-wave I/Q
   demodulation, RGB conversion, 711-to-640 horizontal resampling, bob
   deinterlacing, two ping-pong line buffers, and 640x480 HDMI. It uses 22%
   logic and 20% BSRAM with zero reported setup/hold violations. Hardware must
   still establish feedback polarity, black level, burst lock, hue, and image
   stability before this stage can be called proven.
8. **Joined UVC proof.** Stream 160x120 YUY2 @ 10 fps for 30 minutes with frame,
   FIFO underflow/overflow, sync-loss, and USB-reset counters. Increase frame
   rate only after a fresh bandwidth receipt.

## Stop conditions

- Do not generate or load an HS image for this C6/I5 baseline.
- Do not assign an LVDS CVBS pin before AFE voltage review and measurement.
- Do not advertise a UVC mode before exact descriptor/control and host capture
  evidence.
- If the color front-end cannot produce stable measured amplitude/phase data,
  stop the LVDS-color branch and request an explicit architecture decision;
  do not hide the failure with synthetic color.
- Any hardware test remains volatile SRAM through the fixed Sipeed Programmer
  route and requires the AGENTS.md read-only gates immediately beforehand.
