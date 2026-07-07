# Documentation

A guided tour of the codebase. GbEmu is a Nintendo Game Boy (DMG) emulator
written in pure Elixir, running server-side on the BEAM, with a Phoenix LiveView
front end that draws frames and forwards key presses.

| Document | What it covers |
| --- | --- |
| [roms.md](roms.md) | Legal ROM/BIOS policy, local setup, and redistribution rules |
| [architecture.md](architecture.md) | Process model, data flow, and one frame's journey from CPU to canvas |
| [cpu.md](cpu.md) | The SM83 CPU interpreter: dispatch, flags, interrupts, HALT |
| [memory.md](memory.md) | Address map, boot overlay, MBC banking, and `:atomics` strategy |
| [ppu.md](ppu.md) | LCD modes, scanline rendering, sprites, palettes, and frame assembly |
| [timing-and-io.md](timing-and-io.md) | DIV/TIMA, joypad matrix, and serial-port behavior |
| [frontend.md](frontend.md) | Supervised emulator sessions, LiveView frame streaming, and canvas input |

## Where Things Live

```text
lib/gb_emu/
├── boot_rom.ex          # Open boot stub + optional local BIOS loading
├── gb.ex                # GbEmu.GB machine state struct
├── cpu.ex               # SM83 interpreter
├── bus.ex               # Memory map, MBCs, IO registers
├── ppu.ex               # LCD state machine + scanline renderer
├── timer.ex             # DIV / TIMA
├── machine.ex           # CPU+PPU+Timer frame runner
├── emulator.ex          # Real-time emulator GenServer
└── emulator_sessions.ex # Admission control and worker lifetime tracking

lib/gb_emu_web/
└── live/emulator_live.ex # LiveView page + colocated canvas/keyboard JS hook

priv/roms/                # Local-only user ROM directory
test/gb_emu/              # Synthetic-fixture emulator tests
```

## Quick Orientation

If you read only three things, read these:

1. `GbEmu.Machine.run_frame/1` - the heartbeat. It runs exactly 70,224
   T-cycles by looping `CPU.step -> PPU.step -> Timer.step`.
2. `GbEmu.Bus.read8/2` and `write8/3` - every byte the CPU touches goes through
   here; this is where the Game Boy hardware map is encoded.
3. `GbEmuWeb.EmulatorLive` plus `GbEmu.EmulatorSessions` - how public sessions
   are admitted, how frames leave the server, and how key presses come back in.
