# Integrated debugger

The LiveView debugger pauses the same server-side Game Boy that drives the
canvas. It can execute the active ROM one instruction boundary at a time while
showing the CPU, PPU, timer, memory bus, boot overlay, and the Elixir source
that handled each stage.

> [!IMPORTANT]
> A debugger **Step** is one CPU instruction, interrupt-service, or idle-HALT
> boundary. It is not one individual T-cycle. The PPU, timer, and serial port
> still advance by the exact number of T-cycles consumed by that boundary.

Use only ROMs and boot-ROM files that you are legally allowed to use. The
debugger does not include, download, or bypass the rights for commercial ROMs
or proprietary BIOS files. See [ROM, BIOS, and trademark policy](roms.md).

## First run

1. Upload a lawful `.gb` or `.gbc` file, or select a local ROM.
2. Select **Attach**. This pauses the current machine without resetting it.
3. Select **Step**, **×10**, **PPU**, **Line**, or **Frame** to advance it.
4. Select **Resume** to detach the debugger and return to paced frame updates.

The ordinary Pause button is disabled while the debugger is attached. This
prevents a second control path from resuming the machine behind the debugger.

## Attach, Boot, and Reset are different

| Action | What it does |
| --- | --- |
| **Attach** | Cancels the paced frame timer and snapshots the machine exactly where normal play stopped. It does not reload the ROM or change the PC. |
| Debugger **Boot** | Rebuilds the active ROM and active boot source in cold mode, clears trace history, and stops at `$0000`. |
| Page **Reset** or ROM reload | Leaves debugging, clears its UI/history, and follows the normal startup path described below. |
| **Resume** | Detaches tracing and starts one paced frame-timer chain from the current machine state. |

### Built-in open stub

Normal play does **not** execute the built-in open stub. For the minimal boot
source, the normal fast path directly applies the documented post-boot
compatibility registers and I/O state, disables the boot overlay, and begins at
the cartridge entrypoint `$0100`.

Debugger **Boot** deliberately chooses the cold path so the stub can be studied
as three real SM83 instructions:

```asm
$0000  JP   $00FC
$00FC  LD   A,$01
$00FE  LDH  ($FF50),A
```

After the third step, the write to `$FF50` unmaps the boot overlay and the PC is
`$0100`. Because this is the open stub rather than a DMG BIOS, the bus also
applies the documented post-boot compatibility state while preserving the
current PC and allocated memory. The trace calls this out as a compatibility
handoff.

### User-supplied boot ROM

A lawful 256-byte boot-ROM file remains mapped over `$0000-$00FF` and executes
from `$0000`. This is true on a normal load and after debugger **Boot**. The
debugger never substitutes or simulates that file's instruction sequence.

The sidebar's boot label has three parts: source kind (`MINIMAL` or `FILE`),
startup request (`FAST` for a normal load or `COLD` for debugger Boot), and
whether the overlay is still mapped. The fast compatibility shortcut applies
only to the minimal source; a file source still executes even when the label
shows the normal `FAST` request.

## Execution controls

| Control | Boundary condition |
| --- | --- |
| **Step** | Execute one instruction, interrupt-service, or idle-HALT boundary. |
| **×10** | Execute ten boundaries and retain each resulting trace. |
| **PPU** | Execute whole instruction boundaries until PPU mode, LY, or frame count changes. |
| **Line** | Execute whole instruction boundaries until LY or frame count changes. |
| **Frame** | Execute whole instruction boundaries until frame count changes. |
| **Boot** | Cold-restart the active game ROM and boot source at `$0000`. |
| **Resume** | Detach and return to normal ~59.7 fps pacing. |

PPU, line, and frame commands have hard instruction ceilings and finite call
deadlines. If a condition cannot be reached, the UI shows an error instead of
running without a bound. Instructions that completed before a timeout remain
authoritative; the next successful snapshot reconciles the visible timeline.

## Reading the sidebar

### Instruction and CPU

The instruction panel shows the next assembly instruction at the current PC,
its raw opcode bytes, and a link to the exact `GbEmu.CPU` clause that will
interpret it. The register file shows A, F, B, C, D, E, H, L, SP, PC, the Z/N/H/C
flags, IME, and HALT state. Registers changed by the newest boundary receive an
amber highlight and show `before→current`; changed flags show `0→1` or `1→0`.

### Memory explorer

The memory panel is a 16x16 view of a 256-byte window. Enter a hexadecimal
address such as `C000`, `$C000`, or `0xC000` and select **Read**. Navigation uses
non-tracing peeks: it does not execute an instruction or add artificial bus
reads to the trace.

Region shortcuts jump directly to **BOOT/ROM0** (`$0000`), **ROMX** (`$4000`),
**VRAM** (`$8000`), **ERAM** (`$A000`), **WRAM** (`$C000`), **ECHO** (`$E000`),
**OAM** (`$FE00`), **IO** (`$FF00`), **HRAM** (`$FF80`), or **IE** (`$FFFF`).
The IE shortcut displays the final `$FF00-$FFFF` window so the one-byte IE
register remains visible with its surrounding I/O/HRAM context.

The requested address is aligned to a 16-byte boundary. Near the end of the
address space it is clamped to `$FF00`, so the complete 256-byte window always
fits inside `$0000-$FFFF`.

| Color or marker | Meaning |
| --- | --- |
| Amber cell | Current program counter (PC) |
| Violet underline | Current stack pointer (SP), when it falls inside the window |
| Cyan cell/activity | Read by the most recently executed boundary |
| Magenta cell/activity | Written by the most recently executed boundary |
| Phosphor-lime values | Active register/debugger values |

The activity list shows the latest boundary's final 16 bus events with address,
region, semantic label, value or transition, and source line. PPU fetches are
grouped into meaningful ranges, and OAM DMA is represented as one aggregate
transfer rather than hundreds of noisy byte rows.

### Peripheral clocks

The peripheral panel shows PPU mode, LY/LYC, dot and frame counters; DIV/TIMA
and interrupt flags; and current boot-overlay, MBC, and ROM-bank state. These
values are a boundary snapshot, not a continuously sampled waveform.

### Source trail and execution history

Each trace records the interpreted mnemonic, PC before/after, consumed T-cycles,
register/flag changes, memory activity, peripheral changes, notable events, and
a source trail through the CPU, memory bus, machine, PPU, and timer as relevant.

The sidebar links are generated from compile-time source selectors. They use
repository-relative paths, positive line numbers, and GitHub URLs on the
`master` branch. They are exact for the source revision used to build the
running application. If `master` moves after a deployment, use the displayed
path and line against that deployment's commit instead of assuming the latest
branch still has identical line numbers.

## Bounds and payload safety

- The execution timeline and emulator history keep the latest 200 traces.
- Multi-boundary commands report total work internally, but only the latest 200
  trace records are retained and sent to LiveView.
- Each snapshot contains one 256-byte memory window, not the full 64 KiB bus.
- Memory activity shown in the sidebar is limited to the newest 16 events.
- Normal play does not enable instruction tracing or send debugger snapshots.
- LiveView receives projected maps only; it never receives the authoritative
  `%GbEmu.GB{}` machine or its `:atomics` references.

These limits keep the study surface useful without making normal frame pacing
or LiveView payload size grow with play time.

## Code reading map

| Module | Role |
| --- | --- |
| `GbEmu.Emulator` | Owns the authoritative machine, serializes debug calls, pauses/resumes pacing, and retains bounded history. |
| `GbEmu.Debugger` | Executes boundary commands and builds instruction traces. |
| `GbEmu.Debugger.Disassembler` | Decodes the current SM83 opcode without tracing preview reads. |
| `GbEmu.Debugger.Snapshot` | Projects display-safe CPU, PPU, memory, boot, and history data. |
| `GbEmu.Debugger.SourceMap` | Resolves interpreter selectors to repository paths and exact source lines at compile time. |
| `GbEmu.Machine` | Advances CPU, PPU, timer, and serial state for one instruction boundary. |
| `GbEmu.CPU` | Services interrupts/HALT or interprets the current SM83 instruction. |
| `GbEmu.Bus` | Maps reads/writes, records semantic memory activity, banking, DMA, and boot handoff. |
| `GbEmu.PPU` | Advances LCD timing and records grouped scanline memory ranges. |
| `GbEmuWeb.EmulatorLive` | Converts explicit UI events into serialized debugger calls and streams confirmed snapshots. |
| `GbEmuWeb.DebuggerComponents` | Renders the stateless responsive debugger workbench. |

For the broader runtime path, continue with [architecture.md](architecture.md),
[cpu.md](cpu.md), [memory.md](memory.md), [ppu.md](ppu.md), and
[frontend.md](frontend.md).
