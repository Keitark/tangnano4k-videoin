# Minimal CVBS LVDS delta-modulator front end

> Historical initial topology. The later working NEO FAMI setup added AC
> coupling and input bias, so the direct-coupled schematic below is not the
> complete verified wiring. See the current README milestone and check the
> actual circuit/pin mapping before making hardware changes.

Status: **LAB PROTOTYPE / MEASUREMENT REQUIRED**

This is the reduced-parts closed-loop ADC discussed in the referenced
"Passive DAC explanation" conversation. It is a delta modulator, not a
fixed DSM reference and not a conventional delta-sigma ADC.

## Schematic

```text
Composite / yellow RCA center o----+-------- P7 pin 6
                                    |          package pin 39
                                   R1 75R      LVDS+
                                    |
Yellow RCA shell o------------------+-------- P6 pin 20 (GND)


P6 pin 13 ---------------- R2 2k ----+-------- P7 pin 7
package pin 16                         |          package pin 40
1.8 V feedback GPIO                   C1          LVDS-
                                       33pF
                                        |
                                       GND
```

External ADC parts: two resistors and one capacitor.

| Ref | Initial value | Purpose |
|---|---:|---|
| R1 | 75 ohm, 1%, 0.25 W | Composite-video termination |
| R2 | 2 kohm | One-bit GPIO feedback resistor |
| C1 | 33 pF C0G/NP0 | Feedback integrator capacitor |

Provide footprints or sockets for 22 pF, 33 pF, 47 pF, and 56 pF. Start with
33 pF for the color-bandwidth experiment. Keep the R2/C1/LVDS- wiring extremely
short. Do not enable the FPGA's internal 100-ohm differential termination.

## FPGA loop

```text
CVBS -> LVDS+    LVDS comparator bit -> register -> 1.8 V GPIO
          ^                                      |
          |                                      2 kohm
          +------------- LVDS- <----+------------+
                                    |
                                  33 pF
                                    |
                                   GND
```

The registered comparator bit is returned directly to the feedback GPIO. The
RC voltage follows the input waveform. The bit density is then digitally
filtered/decimated to reconstruct a multi-bit composite sample stream.

Conceptual RTL:

```verilog
wire adc_bit_raw;
reg  adc_bit;

TLVDS_IBUF u_adc_cmp (
    .O  (adc_bit_raw),
    .I  (video_p),
    .IB (video_n)
);

always @(posedge adc_clk)
    adc_bit <= adc_bit_raw;

assign adc_feedback = adc_bit;
```

Invert the returned bit only if measurement proves that the loop runs away
instead of tracking the input.

## Pin assignment

| Function | Header pin | Package pin/domain |
|---|---:|---|
| Composite / LVDS+ | P7 pin 6 | 39, `IOT26A`, Bank 1 |
| RC feedback / LVDS- | P7 pin 7 | 40, `IOT26B`, Bank 1 |
| Registered feedback GPIO | P6 pin 13 | 16, `IOB6A`, Bank 3 at 1.8 V |
| Ground | P6 pin 20 | GND |

Disconnect the camera ribbon/module because all three signal pins share camera
nets on the board.

## Safety and bring-up

1. With the FPGA disconnected, terminate the source with 75 ohms and confirm
   that the composite input remains between 0 V and 2.15 V.
2. Confirm the feedback GPIO is configured as `LVCMOS18`, not 3.3 V.
3. Begin with a conservative ADC clock (108 MHz candidate) and a 33 pF C0G
   capacitor. Clock legality and timing must pass for the exact C6/I5 target.
4. Power the Tang Nano before the video source and remove the video signal
   before powering the Tang Nano down.
5. First verify that the RC node follows the composite waveform and that the
   one-bit density changes. Only then add reconstruction, sync, luma, burst,
   and chroma processing.

This is an experimental port of an LVDS delta-modulator technique to Gowin;
it is not a vendor-qualified ADC mode. Hardware tests use volatile SRAM only
and remain subject to all `AGENTS.md` programming gates.
