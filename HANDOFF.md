# Tang Nano 4K Video-to-UVC Handoff

Latest video milestone (2026-09-13): see
`evidence/color-three-line-verified-20260913.md` for the verified live320x240
color HDMI,three-line-buffer SRAM artifact and captures. This does not claim
native FPGA USB-UVC implementation. The programming policy below remains fixed.

Date: 2026-08-29 (Asia/Tokyo)

## Objective

Implement a reduced-parts, color composite-video input device on the Tang Nano
4K that appears to a PC as a USB UVC camera. The preferred input approach uses
the board's LVDS-capable FPGA inputs where electrically practical. The next
session should first establish a resource-feasible architecture, then implement
the smallest independently verifiable stage.

## Verified board and programming path

- Board hardware is operational.
- FPGA identity: `GW1NSR-4C`, JTAG ID `0x0100981B`.
- Required programming application: Sipeed-distributed Gowin Programmer
  `1.9.11.02 build 2518`.
- Programmer CLI SHA-256:
  `0CBB56027B0DED80F92895C979A9B6D727BBC3E7CF000366B8EB07DA71876DD1`.
- JTAG frequency must remain at or below `2.5 MHz`.
- Interface A: `USB Serial Converter A`, `oem69.inf`, FTDI/FTDIBUS
  `2.12.36.20`.
- Interface B: `USB Serial Converter B`, `oem69.inf`, FTDI/FTDIBUS
  `2.12.36.20`.
- Serial child: `USB Serial Port (COM8)`, `oem96.inf`, FTSER2K
  `2.12.36.20`.
- Scheduled task `\UsbMonitor` is disabled because it previously claimed the
  FTDI channel on this workstation.
- The Sipeed Programmer GUI successfully loaded the blink image into volatile
  SRAM and the LED blinked. This confirms the complete FTDI/JTAG programming
  route on this PC.

Do not change these drivers or repeat USB-driver troubleshooting unless fresh,
specific evidence requires it. Do not use Zadig, WinUSB, or openFPGALoader.

## Verified test artifact

- File: `build/blink_c6/impl/pnr/project.fs`
- Target: `GW1NSR-LV4CQN48PC6/I5`
- Size: `1,168,294` bytes
- SHA-256:
  `C4EF22F0DF962E34CBC63C1E02A86701ED517CE917D7E47262F4FA3205D728B8`
- Test mode: volatile SRAM only; no flash write was performed.

## Sipeed Programmer procedure

1. Confirm Windows shows converter A, converter B, and the COM child above.
2. Open the local Sipeed Programmer 1.9.11.02 package.
3. Select `USB Debugger A`, channel `0`, and JTAG frequency `2.5 MHz`.
4. Scan and require `GW1NSR-4C` / `0x0100981B` before loading an image.
5. For temporary tests, choose `SRAM Mode` and `SRAM Program`.
6. Do not select embedded or external flash without explicit authorization.

CLI read-only gates, when needed:

```powershell
programmer_cli.exe --scan-cables F
programmer_cli.exe --cable-index 1 --channel 0 --frequency 2.5MHz --scan
```

## Required next work

1. Read `AGENTS.md` and preserve its programming and troubleshooting policy.
2. Inventory existing HDL, constraints, Gowin project files, USB/HS-core work,
   and any composite-video decoder experiments before editing.
3. Establish the actual Nano 4K resource budget and available USB physical
   interface. Separate what can run inside the FPGA from any unavoidable analog
   input conditioning.
4. Define a staged data path: protected composite input, sampling/front end,
   sync and color decoding, line/frame buffering, pixel formatting, USB UVC
   transport, and Windows enumeration.
5. Select the smallest first hardware milestone with an observable result. A
   suitable sequence is input/sync capture proof, monochrome line proof, color
   decode proof, USB descriptor/enumeration proof, then live UVC frames.
6. Build with Gowin and test through volatile SRAM using the verified Sipeed
   path. Keep each test bounded and preserve exact build/program evidence.

## Completion boundary

The blink result proves only the toolchain and JTAG route. It does not prove
composite capture, color decoding, USB transport, or UVC compliance. Claim each
of those only after its own hardware or host-visible verification.
