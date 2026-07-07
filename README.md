<p align="center">
  <img src="priv/static/images/logo.svg" width="96" alt="GbEmu logo" />
</p>

# Game Boy on the BEAM

A study-oriented Nintendo Game Boy (DMG) emulator written in pure Elixir with a
Phoenix LiveView front end. The emulator runs server-side on the BEAM; the
browser draws a 160x144 canvas and sends button events back over LiveView.

> [!IMPORTANT]
> This repository is for emulator study, hardware documentation practice, and
> lawful homebrew experimentation. It does not include game ROMs or proprietary
> console BIOS files. Use only homebrew ROMs, public test ROMs, or personal
> cartridge/BIOS dumps that you are legally allowed to use. Do not use ROMs for
> games you do not own or are not licensed to use. This is not legal advice.

GbEmu is not affiliated with, sponsored by, or endorsed by Nintendo. "Game Boy"
and related names are trademarks of their respective owners.

## Features

- Pure Elixir SM83 CPU interpreter with interrupt, HALT, stack, branch, and CB
  opcode support.
- DMG memory bus with boot overlay, MBC0/MBC1/MBC5 cartridge banking, VRAM,
  WRAM, OAM, HRAM, IO registers, OAM DMA, joypad, timer, and serial stub.
- Scanline PPU renderer for background, window, sprites, palettes, VBlank, STAT,
  and frame assembly.
- Phoenix LiveView canvas front end with keyboard input and per-session frame
  streaming.
- Supervised emulator workers with a configurable concurrency limit for safer
  local demos.
- Built-in open boot stub, plus optional `GB_EMU_BOOT_ROM` support for a legally
  obtained local BIOS file.

Audio is not implemented.

## Quick Start

```sh
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

The public repository intentionally starts without ROMs. Add a legal `.gb` file
to `priv/roms/` for local use, then restart the server. Supported cartridges are
MBC0, MBC1, and MBC5.

Controls:

| Keyboard | Game Boy |
| --- | --- |
| Arrow keys | D-pad |
| `Z` | A |
| `X` | B |
| `Enter` | Start |
| `Shift` | Select |

## ROMs and BIOS

By default GbEmu uses a tiny open boot stub that writes `$FF50` to unmap the
boot area and jumps to the cartridge entrypoint at `$0100`. It does not perform
the original startup logo scroll, audio chime, or cartridge header check.

If you have a legally obtained DMG boot ROM dump, point the app at your local
file:

```sh
GB_EMU_BOOT_ROM=/absolute/path/to/dmg_boot.bin mix phx.server
```

See [docs/roms.md](docs/roms.md) for the full ROM, BIOS, trademark, and
redistribution policy before opening an issue or submitting a PR.

## Safety Defaults

Every active browser session runs server-side emulation work. The app therefore
limits concurrent emulator sessions with `GB_EMU_MAX_SESSIONS`:

```sh
GB_EMU_MAX_SESSIONS=4 mix phx.server
```

The default is `4`. Keep public deployments behind authentication, upstream rate
limits, or another access-control layer; this project is designed first as a
local study app.

## Architecture

```text
browser canvas + keyboard hook
   ^ frames, base64 shades        v joypad/control events
GbEmuWeb.EmulatorLive        LiveView per viewer
GbEmu.EmulatorSessions       admission control and worker lifetime tracking
GbEmu.Emulator               real-time GenServer, one machine per viewer
GbEmu.Machine                one video frame = 70,224 T-cycles
├── GbEmu.CPU                SM83 interpreter
├── GbEmu.PPU                scanline renderer
├── GbEmu.Timer              DIV/TIMA
└── GbEmu.Bus                memory map, MBCs, IO, boot overlay, DMA
```

State lives in a single `GbEmu.GB` struct threaded through each emulation step.
Bulk memory uses `:atomics` arrays so instruction-level updates do not copy
large binaries. Tile rows are decoded through a 65,536-entry lookup table stored
in `:persistent_term`.

## Documentation

Start with [docs/README.md](docs/README.md) for a guided tour of the emulator,
then dive into the CPU, memory bus, PPU, timing/IO, and LiveView front end.

## Tests

```sh
mix test
mix precommit
```

Tests use synthetic fixtures and the built-in open boot stub. They do not depend
on commercial games, third-party ROM binaries, or proprietary console BIOS
files.
