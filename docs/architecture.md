# Architecture

## The one-sentence version

Each admitted browser session with a loaded ROM gets its own Game Boy: a
GenServer that executes 70,224 emulated clock cycles ~60 times a second and
streams the resulting 160x144 frames to a LiveView, which pushes them onto a
`<canvas>`. Sessions without a ROM keep the emulator controls disabled.

## Process model

```
Browser tab
│  canvas drawing + keydown/keyup            (JS hook, no game logic)
│
│  LiveView websocket
▼
GbEmuWeb.EmulatorLive          one LiveView process per visitor
│  push_event("frame", ...)  ▲   handle_event("joypad" / "debug_*", ...)
▼                            │
GbEmu.EmulatorSessions         admission + subscriber/worker monitors
▼
GbEmu.EmulatorSupervisor       DynamicSupervisor
▼
GbEmu.Emulator                 one authoritative GenServer per visitor
│  self-ticks with Process.send_after
▼
GbEmu.Machine.run_frame/1      state transition: (gb) -> {gb, frame_binary}
```

There is no global machine state. `EmulatorLive.mount/3` asks
`GbEmu.EmulatorSessions` to admit and start a worker under the dynamic
supervisor. The session manager monitors both the LiveView subscriber and the
worker; when the visitor leaves it terminates that worker. Two tabs = two
independent Game Boys, subject to the configured admission limit.

## The machine state: one struct, threaded everywhere

All hardware state lives in a single `GbEmu.GB` struct (`lib/gb_emu/gb.ex`):
CPU registers, cartridge/MBC banking state, LCD registers, timer counters,
joypad bits, PPU internals. Every emulation step is a pure function
`gb -> gb` (or `gb -> {gb, extra}`).

The key performance decision: **bulk memory is not in the struct**. VRAM,
WRAM, OAM, HRAM and cartridge RAM are `:atomics` arrays (mutable,
off-heap). The struct only holds their references, so the millions of
per-instruction struct updates never copy memory contents — only the small
register fields change. Two other tricks:

- The ROM is an immutable Elixir binary; reads are `:binary.at/2`, which is
  O(1) and copy-free.
- Tile pixel decoding uses a 65,536-entry lookup table in
  `:persistent_term` (`GbEmu.GB.decode_table/0`) that maps any 2-byte tile
  row directly to its 8 pixel color indices.

Result: ~4.6 ms of CPU time per emulated frame, well inside the 16.7 ms
real-time budget.

## Anatomy of one frame

`GbEmu.Machine.run_frame/1` loops over `Machine.step_instruction/1` until 70,224
T-cycles have elapsed
(the exact duration of one DMG video frame at 4.194304 MHz):

1. `CPU.step/1` services a pending interrupt or executes one instruction,
   returning how many T-cycles it consumed (4–24).
2. `PPU.step/2` advances the LCD state machine by that many cycles. When a
   scanline's drawing period ends it renders that line into a 160-byte
   binary; when line 144 is reached it concatenates all lines into a
   23,040-byte frame and raises the VBlank interrupt.
3. `Timer.step/2` advances DIV/TIMA and raises the timer interrupt on
   overflow.
4. The serial state advances by the same T-cycle count.

The finished frame is a binary of 2-bit shades (one byte per pixel,
values 0–3). Color is applied client-side, which keeps the payload small.

## Real-time pacing

`GbEmu.Emulator` ticks itself with `Process.send_after`. Each timer has a unique
token, and replacing/cancelling a timer invalidates stale messages so pause,
debug attach, resume, and ROM reload cannot create duplicate frame chains. The
emulator tracks an absolute `next_frame_at` deadline in microseconds (16,742 µs
per frame — the true 59.73 Hz frame duration) instead of sleeping a fixed
interval, so scheduling jitter doesn't accumulate drift. If it falls behind by
more than 5 frames, the deadline is clamped rather than trying to catch up with
a burst.

## Debugger execution

The integrated debugger does not run a second emulator. `Attach` makes a
synchronous call to the authoritative `GbEmu.Emulator` GenServer, cancels its
frame timer, and snapshots the same `%GbEmu.GB{}` that was driving the canvas.
All debugger commands execute at that serialization point.

`GbEmu.Debugger.step/1` wraps the same `Machine.step_instruction/1` primitive
used by normal frames. A boundary is one interpreted instruction, interrupt
service, or idle-HALT step; the PPU, timer, and serial port advance by the
returned T-cycle count. PPU/scanline/frame controls repeat whole boundaries
until their condition changes, subject to instruction ceilings and finite
deadlines.

Trace capture is enabled only during explicit debugger commands. A projected
snapshot contains CPU/peripheral summaries, one aligned 256-byte memory window,
the latest trace, and at most 200 history rows. LiveView never receives the
machine struct or its mutable `:atomics` references. See
[debugger.md](debugger.md) for the UI workflow and source mapping.

## Boot paths

`GbEmu.BootRom` provides either the built-in open stub (`:minimal`) or a lawful
user-supplied 256-byte file (`:file`). The normal-load and debugger-restart paths
are intentionally different.

### Normal load and page Reset

With the minimal source, normal play uses `boot_mode: :fast`. It does **not**
execute the stub: `GbEmu.GB.new/3` applies the documented post-boot register and
I/O compatibility state directly, disables the overlay, and begins at `$0100`.

With a file source, the fast shortcut does not apply. The file remains mapped
over `$0000-$00FF`, the machine begins at `$0000`, and its own bytes execute.

### Debugger Boot

The debugger's **Boot** command reconstructs the active game ROM and boot source
with `boot_mode: :cold`, clears history, and stops at `$0000`. The open stub can
therefore be followed as:

1. `$0000`: `JP $00FC`
2. `$00FC`: `LD A,$01`
3. `$00FE`: `LDH ($FF50),A`

The third instruction unmaps the overlay and hands off at `$0100`. For the open
stub only, the `$FF50` write also applies post-boot compatibility state while
preserving the current PC and memory. A file source instead follows its own
boot sequence without that minimal-stub handoff.

Users who have a legally obtained DMG boot ROM can set `GB_EMU_BOOT_ROM` to a
local file. With a real boot ROM, the emulated startup path is the hardware path:

1. Clears VRAM, initializes audio registers and the background palette.
2. Decompresses the Nintendo logo *from the cartridge header* into VRAM
   and scrolls it down while playing the "po-ling" chime (audio writes are
   accepted but not synthesized).
3. Compares the cartridge logo against its own copy and checksums the
   header — a mismatch locks up, just like a real DMG.
4. Writes `$01` to `$FF50`, which unmaps the boot ROM
   (`GbEmu.Bus` flips `boot_enabled` to `false`) and execution falls
   through to the cartridge entry point at `$0100`.

Without a file source, the project never ships or reconstructs those proprietary
startup bytes. See [roms.md](roms.md) for the project policy.
