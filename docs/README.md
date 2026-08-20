# Documentation

A guided tour of the codebase. GbEmu is a Nintendo Game Boy (DMG) emulator
written in pure Elixir, running server-side on the BEAM, with a Phoenix LiveView
front end that draws frames and forwards key presses.

| Document | What it covers |
| --- | --- |
| [debugger.md](debugger.md) | Attach/boot workflow, execution controls, memory colors, source links, and bounds |
| [roms.md](roms.md) | Legal ROM/BIOS policy, local setup, and redistribution rules |
| [architecture.md](architecture.md) | Process model, data flow, and one frame's journey from CPU to canvas |
| [cpu.md](cpu.md) | The SM83 CPU interpreter: dispatch, flags, interrupts, HALT |
| [memory.md](memory.md) | Address map, boot overlay, MBC banking, and `:atomics` strategy |
| [ppu.md](ppu.md) | LCD modes, scanline rendering, sprites, palettes, and frame assembly |
| [timing-and-io.md](timing-and-io.md) | DIV/TIMA, joypad matrix, and serial-port behavior |
| [frontend.md](frontend.md) | Supervised emulator sessions, LiveView frame streaming, and canvas input |
| [../exercises/README.md](../exercises/README.md) | GBEmulings progressive exercise track |

## Where Things Live

```text
lib/gb_emu/
├── boot_rom.ex          # Open boot stub + optional local BIOS loading
├── gb.ex                # GbEmu.GB machine state struct
├── cpu.ex               # SM83 interpreter
├── bus.ex               # Memory map, MBCs, IO registers
├── ppu.ex               # LCD state machine + scanline renderer
├── timer.ex             # DIV / TIMA
├── machine.ex           # CPU+PPU+Timer+serial frame runner
├── debugger.ex          # Bounded instruction-boundary commands + traces
├── debugger/            # Disassembly, snapshots, source map, trace capture
├── emulator.ex          # Real-time emulator GenServer
├── emulator_sessions.ex # Admission control and worker lifetime tracking
└── upload_store.ex      # Browser-session upload storage and TTL cleanup

lib/gb_emu_web/
├── components/debugger_components.ex      # Stateless debugger workbench
├── controllers/upload_session_controller.ex # Upload keepalive endpoint
├── live/emulator_live.ex                    # LiveView page + canvas hook
├── session.ex                               # Runtime session cookie options
└── upload_session.ex                        # Signed browser upload-session id

priv/roms/                # Local-only user ROM directory
test/gb_emu/              # Synthetic-fixture emulator tests
```

## Quick Orientation

If you read only four things, read these:

1. [debugger.md](debugger.md) - how to pause the live machine, cold-start either
   boot source, and follow assembly through memory/PPU work to Elixir lines.
2. `GbEmu.Machine.step_instruction/1` and `run_frame/1` - the shared heartbeat.
   One boundary advances CPU, PPU, timer, and serial state; normal play repeats
   it for exactly 70,224 T-cycles per frame.
3. `GbEmu.Bus.read8/2` and `write8/3` - every byte the CPU touches goes through
   here; this is where the Game Boy hardware map is encoded.
4. `GbEmuWeb.EmulatorLive` plus `GbEmu.EmulatorSessions` - how public sessions
   are admitted, how frames leave the server, and how key presses come back in.
