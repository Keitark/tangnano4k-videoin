# Tang Nano 4K programming policy

This policy applies to all work in this repository.

## Mandatory programming route

- Build FPGA artifacts with the required Gowin toolchain.
- Program and detect the Tang Nano 4K with the Programmer package distributed
  through Sipeed's Tang programmer archive.
- Prefer the newest locally validated Sipeed archive build. Record the exact
  package version and executable hash in verification evidence.
- Keep the JTAG clock at or below 2.5 MHz.

## No automatic fallback

- Do not switch to openFPGALoader as a workaround or fallback.
- Do not replace interface A with WinUSB, libusbK, or a Zadig-generated driver.
- Do not recommend the successful configuration from another PC as a substitute
  for repairing the Sipeed Programmer path on this PC.
- Do not switch to another programming application unless the user explicitly
  changes this policy.
- If the Sipeed path is blocked, report `BLOCKED` with the exact evidence and
  continue diagnosing that path. Do not silently redefine success around a
  different programmer.

## Bounded work and troubleshooting

- Do not overwork the task or expand into adjacent areas that the user did not
  request. Prefer the shortest action that directly advances the stated goal.
- Keep responses, diagnostics, downloads, and tool calls concise. Reuse already
  established evidence instead of repeatedly rechecking the same facts.
- Change only the interface or subsystem currently in scope. In particular, do
  not disable, restart, remove, or change the driver for interface A, interface
  B, or its COM child merely to test a hypothesis about another interface.
- Before any temporary device-state or driver change, state the exact proposed
  change and obtain explicit user approval. A request to test a programmer does
  not authorize unrelated driver experiments.
- Test one evidence-backed hypothesis at a time. If it fails, restore any
  temporary state immediately and stop; do not cascade into additional repair
  attempts without reporting the result and receiving direction.
- When the user asks to save tokens or stop experimenting, cease exploratory
  work immediately and provide only the minimum status needed.

## Expected Windows device topology

Before programming, Windows must show all of the following for the onboard
BL702 debugger:

- `USB Serial Converter A` using the FTDI/D2XX bus driver for JTAG.
- `USB Serial Converter B` using the FTDI bus driver.
- `USB Serial Port (COMx)` below converter B with VCP enabled.

Interface A must expose an enabled D2XX device interface. The Sipeed Programmer
must be able to open it; cable discovery alone is not sufficient.

## Verification gates

Do not write a bitstream until all read-only gates pass:

1. Record the Sipeed Programmer version and SHA-256.
2. Record the A, B, and COM driver INF names and versions.
3. Confirm that no unrelated process owns the FTDI/D2XX channel.
4. Confirm cable discovery with the Sipeed Programmer.
5. Confirm a JTAG scan returns the expected Tang Nano 4K FPGA identity. The
   previously observed reference is `GW1NSR-4C`, ID `0x0100981B`; treat it as
   an expected value to re-verify, not as proof of the current session.
6. Confirm the bitstream target grade matches the physical FPGA before writing.

For CLI verification with Programmer 1.9.11.x, use the documented FT2CH route:

```powershell
programmer_cli.exe --scan-cables F
programmer_cli.exe --cable-index 1 --channel 0 --frequency 2.5MHz --scan
```

The first command finding `USB Debugger A` is only a cable-discovery result.
The second command must open the channel and return the FPGA identity.

## Driver-change safety

- Limit driver operations to the Tang Nano's exact `VID_0403:PID_6010`
  interfaces and their FTDI COM child.
- Before replacing a driver, verify that its OEM INF is not used by unrelated
  devices, export the complete installed package, and create a hash manifest.
- Do not delete or alter the BL702 debugger firmware unless the user explicitly
  authorizes that separate recovery operation.
- On this workstation, the scheduled task `\UsbMonitor` was shown to claim the
  FTDI channel. Keep it disabled during programming diagnosis. This is a
  workstation-specific conflict, not a general Tang Nano requirement.

## Evidence and completion

A Device Manager `OK` status, two converter names, a COM port, or a successful
cable list is not sufficient by itself. The programming path is complete only
after the Sipeed Programmer opens interface A, identifies the FPGA over JTAG,
and a user-approved matching bitstream is successfully written and verified.
