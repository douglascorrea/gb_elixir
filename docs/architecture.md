# Architecture

## The one-sentence version

Every browser visitor gets their own Game Boy: a GenServer that executes
70,224 emulated clock cycles ~60 times a second and streams the resulting
160x144 frames to a LiveView, which pushes them onto a `<canvas>`.

## Process model

```
Browser tab
│  canvas drawing + keydown/keyup            (JS hook, no game logic)
│
│  LiveView websocket
▼
GbEmuWeb.EmulatorLive          one LiveView process per visitor
│  push_event("frame", ...)  ▲   handle_event("joypad", ...)
▼                            │
GbEmu.Emulator                 one GenServer per visitor (linked to the LV)
│  self-ticks with Process.send_after
▼
GbEmu.Machine.run_frame/1      pure function: (gb) -> {gb, frame_binary}
```

There is no global emulator: `EmulatorLive.mount/3` starts a linked
`GbEmu.Emulator`, so when the visitor leaves, the LiveView dies and takes
the emulator with it. Two tabs = two independent Game Boys.

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

`GbEmu.Machine.run_frame/1` loops until 70,224 T-cycles have elapsed
(the exact duration of one DMG video frame at 4.194304 MHz):

1. `CPU.step/1` services a pending interrupt or executes one instruction,
   returning how many T-cycles it consumed (4–24).
2. `PPU.step/2` advances the LCD state machine by that many cycles. When a
   scanline's drawing period ends it renders that line into a 160-byte
   binary; when line 144 is reached it concatenates all lines into a
   23,040-byte frame and raises the VBlank interrupt.
3. `Timer.step/2` advances DIV/TIMA and raises the timer interrupt on
   overflow.

The finished frame is a binary of 2-bit shades (one byte per pixel,
values 0–3). Color is applied client-side, which keeps the payload small.

## Real-time pacing

`GbEmu.Emulator` ticks itself with `Process.send_after`. It tracks an
absolute `next_frame_at` deadline in microseconds (16,742 µs per frame —
the true 59.73 Hz frame duration) instead of sleeping a fixed interval, so
scheduling jitter doesn't accumulate drift. If the emulator falls behind
by more than 5 frames the deadline is clamped rather than trying to catch
up with a burst.

## Boot sequence

On reset the machine starts with `pc = 0x0000` and the 256-byte DMG boot
ROM region mapped over addresses `$0000-$00FF`. The public repository uses
`GbEmu.BootRom.minimal/0`, an open stub that writes `$01` to `$FF50` and jumps
to the cartridge entrypoint at `$0100`.

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

Without `GB_EMU_BOOT_ROM`, the emulator intentionally skips those proprietary
startup bytes. See [roms.md](roms.md) for the project policy.
