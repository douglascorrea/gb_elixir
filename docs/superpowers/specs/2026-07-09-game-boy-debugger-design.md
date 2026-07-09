# Game Boy Debugger Sidebar Design

**Date:** 2026-07-09

**Status:** Approved for implementation

## Purpose

Add an educational debugger to the Phoenix LiveView emulator so a reader can
pause the authoritative Game Boy machine, execute ROM assembly one instruction
at a time, and see how Elixir moves that instruction through the CPU, memory
bus, PPU, timer, serial port, and browser UI.

The debugger must explain both supported boot paths:

- the repository's open boot stub when no boot ROM file is configured; and
- a 256-byte boot ROM loaded from the browser session or `GB_EMU_BOOT_ROM`.

The debugger is a study surface, not a replacement for a cycle-accurate logic
analyzer. A step ends at a CPU instruction boundary (or interrupt/HALT service
boundary). PPU, timer, and serial state still advance by the instruction's exact
T-cycle count.

## Goals

- Attach to and pause the machine that is actually driving the canvas.
- Restart either boot source at `$0000` without changing normal fast-start play.
- Step one instruction, ten instructions, one PPU transition, one scanline, or
  one frame.
- Show decoded assembly, raw bytes, cycles, register/flag deltas, interrupts,
  PPU state, timer state, cartridge banking, and boot-overlay state.
- Make memory the largest debugger surface: show a navigable 256-byte window,
  semantic Game Boy regions, and chronological read/write activity.
- Show the Elixir source path and line that handled each pipeline stage.
- Keep history, payload size, and execution work bounded.
- Preserve the existing 59.7 fps play path and existing ROM-upload behavior.

## Non-goals

- Rewriting the CPU as individual T-cycle or machine-cycle micro-operations.
- Breakpoints, watchpoint expressions, reverse execution, or save states.
- Exposing the complete `%GbEmu.GB{}` struct to LiveView.
- Sending all 64 KiB of address space after every instruction.
- Recording every pixel-level PPU fetch as a top-level trace row.
- Debugging commercial ROMs or redistributing proprietary boot ROMs.

## Runtime architecture

`GbEmu.Emulator` remains the only owner of the authoritative `%GbEmu.GB{}`.
Debugger operations are synchronous `GenServer.call/3` requests so pause,
restart, execution, and snapshot generation are serialized with input and the
real-time frame loop.

`GbEmu.Machine.step_instruction/1` becomes the shared execution primitive:

```text
CPU.step/1
  -> PPU.step/2 using returned T-cycles
  -> Timer.step/2 using returned T-cycles
  -> serial advancement using returned T-cycles
```

`Machine.run_frame/1` delegates to this primitive. A traced debugger step wraps
the same primitive; it does not implement a second emulator.

The emulator has three visible modes:

- `:playing` runs the existing paced frame loop.
- `:paused` keeps the current state still.
- `:debugging` is paused and accepts deterministic debugger commands.

Opening the sidebar and attaching changes the machine from playing to debugging
without resetting it. Closing/detaching can resume ordinary play. The explicit
"Restart from boot" action creates a cold machine from the currently active
game ROM and boot source.

## Boot behavior

### Boot ROM file

A browser-uploaded boot ROM or `GB_EMU_BOOT_ROM` already flows through
`BootRom.load!/1`. Debug restart constructs the machine in cold mode with
`pc=$0000` and `boot_enabled=true`. All executed bytes come from the supplied
file until it writes `$FF50`.

### Open boot stub

Normal play preserves the existing compatibility fast path: `GB.new/2` applies
the canonical post-boot state and starts at `$0100`.

Cold debugger mode executes a corrected three-instruction open stub:

```asm
$0000  JP $00FC
$00FC  LD A,$01
$00FE  LDH ($FF50),A
```

Placing the unmap instruction at `$00FE` makes its next PC `$0100`, matching the
hardware handoff rule. When that open stub unmaps itself, the emulator applies
the documented compatibility register/IO state while preserving the current
PC and allocated memory. The step trace labels this as an Elixir compatibility
handoff so it cannot be mistaken for work performed by Nintendo boot code.

## Debugger data model

A step trace is a compact plain map or struct safe to send to LiveView. It
contains:

- monotonic trace id and step kind (`:instruction`, `:interrupt`, or `:halt`);
- PC before/after, opcode bytes, mnemonic, operands, and T-cycles;
- before/after CPU registers and named flags;
- chronological memory events with operation, address, Game Boy region,
  requested value, old/new value when applicable, and semantic label;
- PPU mode/dot/LY and LCD register deltas;
- timer, interrupt, serial, MBC, and boot-overlay deltas;
- notable events such as scanline render, VBlank, DMA, interrupt dispatch, and
  open-stub compatibility handoff; and
- a source trail containing relative path, exact line, label, and GitHub URL.

Trace history is capped at 200 instruction records. Multi-step commands return
the last 200 records and an explicit total-step count so truncation is visible.

## Tracing and source locations

Memory tracing is enabled only around debugger execution. CPU bus reads and
writes go through `GbEmu.Bus`, which records accesses while the debug trace flag
is active. OAM DMA records an aggregate event plus its affected address range.

The PPU currently accesses VRAM and OAM atomics directly. At a scanline render,
the debugger records grouped PPU read ranges and their purpose (tile map, tile
data, or OAM) instead of producing hundreds of top-level rows. The details stay
expandable in the memory activity panel.

`GbEmu.Debugger.SourceMap` embeds source locations at compile time. CPU opcode
families resolve to the actual matching `exec/2` clause; memory regions resolve
to their `Bus` branch; and machine/PPU/timer stages resolve to their public step
functions. Locations are emitted as repository-relative paths and links to
`https://github.com/douglascorrea/gb_elixir/blob/master/`.

## Snapshot and memory API

LiveView never receives a `%GbEmu.GB{}`. `GbEmu.Debugger.Snapshot` converts the
authoritative state into display-only data:

- CPU registers and flags;
- interrupt state;
- PPU, timer, serial, joypad, cartridge, and boot summaries;
- decoded current/next instruction;
- selected 256-byte memory window; and
- the newest trace plus bounded history.

Memory addresses are validated and normalized to `$0000-$FFFF`. A window starts
on a 16-byte boundary and is clamped so 256 bytes always fit. Region shortcuts
cover Boot/ROM0, ROMX, VRAM, external RAM, WRAM, echo RAM, OAM, IO, HRAM, and
IE. Reads used to construct the UI are peeks and do not enter the trace.

## Debug commands

The integrated debugger supports:

- **Attach**: pause and snapshot current state.
- **Step**: one instruction/interrupt/HALT boundary.
- **Step 10**: ten boundaries, retaining each trace.
- **Next PPU event**: run until mode, LY, or frame count changes.
- **Next scanline**: run until LY or frame count changes.
- **Next frame**: run until frame count changes.
- **Restart from boot**: cold-start the active boot source at `$0000`.
- **Memory navigation**: fetch another 256-byte window without execution.
- **Resume**: detach tracing and return to paced play.

Boundary runners have hard instruction ceilings and return a visible error if
the condition is not reached. Calls use a finite timeout; failures leave the
last confirmed snapshot on screen.

## LiveView and visual design

The existing emulator remains the primary column. A sibling `<aside>` is added
outside `#gameboy`, because that element uses `phx-update="ignore"`.

Desktop layout is a two-column workbench with a sticky, independently scrolling
debugger. Tablet and mobile stack the debugger below the console. The debugger
uses an industrial logic-analyzer aesthetic: graphite panels, phosphor-lime
active values, amber instruction focus, cyan reads, and magenta writes. Assembly
and memory use a monospaced typeface and allow text selection despite the game
surface's existing `select-none` behavior.

The sidebar contains:

1. boot source and debugger state;
2. execution toolbar;
3. current assembly instruction and source link;
4. compact CPU registers and flags;
5. memory explorer occupying the largest section;
6. PPU/timer/interrupt summaries; and
7. a bounded source/trace timeline.

The memory explorer presents a 16x16 byte grid. The PC byte is amber, the stack
location is violet, recent reads are cyan, and writes are magenta. Activity
rows show address, region, value transition, meaning, and source location.

All key controls and panels receive stable DOM ids. The existing global Game
Boy keyboard hook ignores targets inside `[data-debug-ui]`, preventing arrows
and Enter from becoming joypad input while the debugger is being operated.

## LiveView state and updates

Debugger state is represented by compact assigns: attached flag, snapshot,
selected memory address/region, command status, and error. Trace rows use a
LiveView stream. Restart resets the stream; stepping inserts returned rows.

The frame binary continues to bypass assigns and is pushed directly to the
canvas. Debug snapshots are sent only after an explicit command. Normal play
does not stream instruction traces; its existing FPS/frame cadence remains
unchanged.

## Error handling

- Commands with no active emulator return a disabled UI state.
- Debug calls validate command names, step limits, and memory addresses.
- Restart preserves the selected ROM/boot paths and reports file/load errors.
- Timeouts or boundary ceilings return an error without fabricating state.
- ROM selection, upload, and Reset clear stale debugger history.
- Emulator termination returns the existing error/capacity state and disables
  debugger controls.

## Testing strategy

Tests use synthetic ROM binaries and the open boot stub; no proprietary binary
is added.

Core tests cover:

- fast-start behavior remains at `$0100`;
- cold open-stub execution at `$0000`, `$00FC`, `$00FE`, then `$0100`;
- the compatibility handoff is explicit and preserves memory;
- one instruction advances PPU, timer, and serial by the returned cycles;
- disassembly for regular, grouped, immediate, CB-prefixed, interrupt, and HALT
  cases;
- memory reads/writes and region metadata;
- bounded history and boundary ceilings;
- memory-window clamping; and
- source locations point at real repository lines.

GenServer tests cover attach, step, restart, memory navigation, and resume using
`start_supervised!/1` and synchronization instead of sleeps.

LiveView tests use stable ids and `has_element?/2`/`element/2` for the sidebar,
execution controls, disabled state, memory grid, source links, and keyboard
isolation marker. Existing tests are preserved unless the approved UI behavior
intentionally changes their contract.

Final verification is `mix precommit`, followed by a focused local browser
check of attach, cold boot, stepping, memory navigation, mobile stacking, and
resume behavior.

## Documentation

Add `docs/debugger.md`, link it from the documentation index and README, and
update architecture/boot wording that currently implies the open stub executes
during normal fast start. Documentation must clearly distinguish instruction
boundaries from individual T-cycles and describe source-link/version behavior.
