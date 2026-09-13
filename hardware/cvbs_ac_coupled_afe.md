# Working AC-coupled CVBS front end

Documentation revision: September 14, 2026. **LAB PROTOTYPE / USER-REPORTED
ASSEMBLY**. This describes the NEO FAMI wiring used during the live color HDMI
milestone, not a new electrical modification. The fitted C2 value of 33 pF was
explicitly confirmed by the owner on this date. Other nominal values follow
the bench/session wiring record; tolerances, manufacturers and voltage ratings
of the salvaged parts have not been independently inventoried.

## Circuit and component list

```text
                                     board 3.3 V
                                          |
                                      R2 33 kohm
                                          |
RCA center ---+---- (+ C1 4.7 uF -) -------+---- VIDEO_BIAS ---- pin 39 (+)
             |                            |
         R1 75 ohm                    R3 10 kohm
             |                            |
RCA shell ---+----------------------------+------------------- GND

pin 16 (1.8 V output) ---- R4 2 kohm ----+---- FEEDBACK ------- pin 40 (-)
                                       |
                                    C2 33 pF
                                       |
                                      GND
```

The `+` and `-` beside pins 39 and 40 are **comparator input designations**,
not power connections. They do not mean pin 40 should be grounded.

| Ref | Nominal value | End A | End B | Function |
|---|---|---|---|---|
| R1 | 75 ohm | RCA center / CVBS_RAW | GND | Terminate the video cable before AC coupling |
| C1 | 4.7 uF electrolytic | **Positive: CVBS_RAW** | **Negative: VIDEO_BIAS** | Block the recorded source's DC offset |
| R2 | 33 kohm | Board 3.3 V | VIDEO_BIAS | Upper bias-divider resistor |
| R3 | 10 kohm | VIDEO_BIAS | GND | Lower bias-divider resistor |
| R4 | 2 kohm | FPGA package pin 16 | FEEDBACK | Drive the RC node from the feedback GPIO |
| C2 | **33 pF**, non-polarized | FEEDBACK | GND | Smooth one-bit feedback; owner-confirmed fitted capacitance |

Total added analog passives: **4 resistors + 2 capacitors**. Board components,
cables/connectors and power supplies are not counted. No external ADC,
comparator IC or composite-video-decoder IC is used. C2 is 33 **pF**, not
33 nF or 33 uF. No exact part-number BOM or sourcing recommendation is implied.

## Exact node checklist

- **CVBS_RAW:** RCA center, R1 top, C1 positive terminal only.
- **VIDEO_BIAS:** C1 negative terminal, R2 bottom, R3 top, FPGA pin 39.
- **FEEDBACK:** R4 output end, C2 top, FPGA pin 40.
- **GPIO_FEEDBACK:** FPGA pin 16 and R4 input end.
- **3V3:** board's labeled 3.3 V supply and R2 top. Do not use 5 V.
- **GND:** RCA shell, R1 bottom, R3 bottom, C2 bottom and board ground.

There is **no wire directly connecting VIDEO_BIAS and FEEDBACK**, and neither
is directly shorted to ground. The intended unloaded VIDEO_BIAS is about
`3.3 V x 10k / (33k + 10k) = 0.767 V`. Its instantaneous voltage includes
the AC video waveform; the calculated DC value is not a safety limit.

## Pin map and voltage domains

| Function | Package pin | Board-header reference | FPGA configuration |
|---|---|---|---|
| VIDEO_BIAS / video_p | 39 | P7 pin 6 | Positive side of TLVDS_IBUF; LVDS25, no pull |
| FEEDBACK / video_n | 40 | P7 pin 7 | Negative side of the same differential receiver |
| GPIO_FEEDBACK / adc_feedback | 16 | P6 pin 13 | LVCMOS18 output, nominal 0/1.8 V |
| Common ground | GND | P6 pin 20 | Board ground |
| Bias supply | Not a signal pin | Board pad/header labeled 3.3 V | R2 supply only |

Pin numbers 39/40/16 are the FPGA package numbering. Header numbering is a
different system; establish orientation from the actual board and check
continuity before wiring. Header references are inherited from the project
board mapping; this documentation update did not physically re-probe them.
Disconnect the camera module/ribbon because the signals share camera nets.

The source checks are [nano4k_ntsc_hdmi.cst](../constraints/nano4k_ntsc_hdmi.cst)
and [lvds_delta_adc.v](../rtl/cvbs/lvds_delta_adc.v). `LVDS25` is an I/O-standard
name, **not an instruction to force either analog input to 2.5 V**. Leave the
internal 100-ohm differential termination disabled. The board bias divider
and feedback output deliberately use different supplies: 3.3 V and 1.8 V.

## Why the coupling capacitor faces this way

The recorded NEO FAMI source had approximately 2.1 V DC on the source side,
whereas the biased FPGA input was around 0.78 V. This explains **C1 positive
toward the source** in this assembly. These are historical bench readings,
not measurements made during this documentation update.

Do not generalize that polarity to every NTSC device. A different source, or
a different power sequence, can change the voltage across C1. Verify polarity
and the actual capacitor's rating across relevant states; this record does not
establish a safe reverse-voltage allowance. No capacitor is an overvoltage
clamp, and AC coupling can still transmit startup transients.

## How the FPGA uses it

1. The LVDS receiver compares VIDEO_BIAS against FEEDBACK.
2. At 108 MHz, one register captures the comparison and drives package pin 16.
3. R4/C2 turn that GPIO pulse stream into a voltage that tracks the input.
4. Separate measurement registers feed digital moving sums. The current
   picture path cascades two 16-sample sums before 8:1 downsampling to
   13.5 MSamples/s; the separate sync path uses a 64-sample moving window.
5. NTSC sync, burst and brightness/color processing feed three line buffers
   and the HDMI output.

An appropriate description is **RC-feedback one-bit oversampling ADC**, or
the **simple sigma-delta approach** used in Lattice's direct-input reference
topology. The passive RC is not an ideal integrator; no textbook noise-shaping,
effective-bit or calibrated accuracy claim follows from the name. The earlier
document's categorical distinction from sigma-delta is historical terminology.
See [Lattice FPGA-RD-02047, Figure 5.1](https://www.latticesemi.com/view_document?document_id=35762).

## Power, layout and bring-up boundaries

| State | What must not be assumed |
|---|---|
| Board off | An active source must not drive the FPGA; isolate/remove the signal before powering down |
| Power-up / no SRAM design | Feedback is not established; pin voltages do not prove an ADC or a fault |
| Reset / clocks unlocked | The running HDL's normal tracking behavior is not available |
| Known matching design running | Check input activity and video, but also verify analog peaks/common-mode independently |
| Rewiring | Power off both source and board first; do not solder live circuitry |

- **[TARGET]** Keep R4, C2, pin 40 and the local ground return close together;
  minimize the feedback loop and exposed lead length.
- **[TARGET]** Bring RCA shield to the termination/bias ground. Secure exposed
  joints so movement cannot short adjacent nodes.
- **[TBD-MEASURE]** Actual input extrema, LVDS common-mode/differential range,
  overshoot, effective node capacitance, feedback delay, rail noise and
  startup/shutdown transients. Multimeter averages cannot establish these.
- **[TBD-MEASURE]** Exact capacitor voltage ratings, fitted resistor tolerances,
  and behavior with sources other than this NEO FAMI. There is no added
  dedicated ESD or overvoltage protection in the recorded six-part network.

The nominal divider current is only `3.3 V / 43 kohm`, about 77 uA. This is
not a whole-board power budget. Input ratings must be checked against the
applicable Gowin datasheet and the actual board's powered/unpowered state;
successful video alone does not certify analog safety.

Board reference: [Sipeed Tang Nano 4K hardware documentation](https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-4K/Nano-4K.html).
Device reference: [Gowin GW1NSR documentation listing, DS861](https://www.gowinsemi.com/en/document/main/database/400/?order=ASC&page=1&support_search=&type=released).

Programming remains subject to [AGENTS.md](../AGENTS.md): matching C6/I5
target, verified Sipeed route at or below 2.5 MHz, SRAM only. This update did
not program a device, change a driver, or change physical wiring.

## Evidence and reproducibility limits

The [live-color milestone](../evidence/color-three-line-verified-20260913.md)
records the demonstrated output and exact artifact hash. This circuit record
combines the session wiring description, owner-confirmed 33 pF value, and
HDL/constraint pin checks. No native EDA netlist, component MPN inventory,
electrical-rule-check pass, or new oscilloscope capture is supplied. Treat it
as documented experimental wiring, not a released production schematic.
