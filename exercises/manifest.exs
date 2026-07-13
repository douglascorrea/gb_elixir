# GBEmulings curriculum manifest.
#
# Each entry is intentionally small and ordered. The complete track starts with
# Elixir and binary fundamentals, then rebuilds the emulator through memory,
# CPU, PPU, timing, OTP supervision, LiveView, debugging, and deployment.
[
  %{
    id: "001",
    section: "elixir-fundamentals",
    title: "Parse a hexadecimal byte",
    goal: "Turn Game Boy hexadecimal notation into an unsigned byte value.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "002",
    section: "elixir-fundamentals",
    title: "Expand a byte into bits",
    goal: "Read a byte from its most-significant bit to its least-significant bit.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "003",
    section: "elixir-fundamentals",
    title: "Wrap values to eight bits",
    goal: "Model unsigned byte overflow and underflow with a mask.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "004",
    section: "elixir-fundamentals",
    title: "Set a bit",
    goal: "Build and apply a one-bit mask without changing neighboring bits.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "005",
    section: "elixir-fundamentals",
    title: "Clear a bit",
    goal: "Invert a one-bit mask and clear only the selected bit.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "006",
    section: "elixir-fundamentals",
    title: "Represent little-endian words",
    goal: "Build and split 16-bit values from low and high bytes.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "007",
    section: "elixir-fundamentals",
    title: "Read immutable binary data",
    goal: "Read a ROM byte by offset with :binary.at/2.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "008",
    section: "elixir-fundamentals",
    title: "Allocate atomics-backed memory",
    goal: "Create fixed-size mutable memory without copying the machine struct.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "009",
    section: "elixir-fundamentals",
    title: "Write atomics-backed memory",
    goal: "Translate a zero-based bus offset to the one-based :atomics API.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "010",
    section: "elixir-fundamentals",
    title: "Decode a planar tile row",
    goal: "Combine two Game Boy bitplanes into eight two-bit color indices.",
    files: ["exercises/workbench/fundamentals.exs"],
    checks: ["mix test test/gb_emulings/fundamentals_test.exs"]
  },
  %{
    id: "011",
    section: "machine-state",
    title: "Define the Game Boy state struct",
    goal:
      "Introduce CPU registers, memory handles, IO registers, PPU state, timer state, and interrupt fields.",
    files: ["lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "012",
    section: "machine-state",
    title: "Allocate bulk memory",
    goal: "Create atomics-backed VRAM, WRAM, OAM, HRAM, and external RAM with correct sizes.",
    files: ["lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "013",
    section: "machine-state",
    title: "Build the tile decode table",
    goal: "Convert two planar tile bytes into eight 2-bit pixel indices.",
    files: ["lib/gb_emu/gb.ex", "docs/ppu.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "014",
    section: "machine-state",
    title: "Cache decode data safely",
    goal: "Store immutable decode data in :persistent_term and initialize it once.",
    files: ["lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "015",
    section: "boot-rom",
    title: "Create the open boot stub",
    goal: "Represent a minimal lawful boot path without shipping proprietary BIOS bytes.",
    files: ["lib/gb_emu/boot_rom.ex", "docs/roms.md"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "016",
    section: "boot-rom",
    title: "Validate optional file boot ROMs",
    goal: "Accept only a 256-byte local boot ROM and keep it outside source control.",
    files: ["lib/gb_emu/boot_rom.ex", "docs/roms.md"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "017",
    section: "boot-rom",
    title: "Model fast boot state",
    goal: "Apply documented post-boot register and IO values for the open stub path.",
    files: ["lib/gb_emu/boot_rom.ex", "lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "018",
    section: "cartridge",
    title: "Read cartridge header bytes",
    goal: "Extract cartridge type and reason about ROM banking requirements.",
    files: ["lib/gb_emu/gb.ex", "docs/memory.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "019",
    section: "cartridge",
    title: "Detect MBC0 cartridges",
    goal: "Support fixed 32 KB ROMs before adding bank controllers.",
    files: ["lib/gb_emu/gb.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "020",
    section: "cartridge",
    title: "Reject unsupported cartridge types",
    goal: "Fail loudly when the emulator cannot model a cartridge mapper.",
    files: ["lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "021",
    section: "bus",
    title: "Read ROM bank 0",
    goal: "Route addresses $0000-$3FFF to fixed cartridge ROM bytes.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "022",
    section: "bus",
    title: "Read switchable ROM banks",
    goal: "Compute the flat binary offset for addresses $4000-$7FFF.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "023",
    section: "bus",
    title: "Map VRAM",
    goal: "Read and write $8000-$9FFF through the VRAM atomics array.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "024",
    section: "bus",
    title: "Map work RAM and echo RAM",
    goal: "Share WRAM storage through $C000-$DFFF and its $E000-$FDFF mirror.",
    files: ["lib/gb_emu/bus.ex", "docs/memory.md"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "025",
    section: "bus",
    title: "Map OAM",
    goal: "Read and write sprite attribute memory at $FE00-$FE9F.",
    files: ["lib/gb_emu/bus.ex", "docs/ppu.md"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "026",
    section: "bus",
    title: "Return open-bus values",
    goal: "Return $FF for unusable or disabled regions instead of crashing.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "027",
    section: "bus",
    title: "Map HRAM and IE",
    goal: "Implement $FF80-$FFFE high RAM and $FFFF interrupt enable.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "028",
    section: "bus",
    title: "Implement little-endian read16",
    goal: "Read two bytes through the bus and wrap the high-byte address.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "029",
    section: "bus",
    title: "Unmap the boot overlay",
    goal: "Handle writes to $FF50 so boot ROM bytes disappear permanently.",
    files: ["lib/gb_emu/bus.ex", "lib/gb_emu/boot_rom.ex"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "030",
    section: "bus",
    title: "Implement DIV writes",
    goal: "Reset the divider counter on any write to $FF04.",
    files: ["lib/gb_emu/bus.ex", "lib/gb_emu/timer.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "031",
    section: "bus",
    title: "Protect read-only LCD registers",
    goal: "Keep LY and STAT mode bits hardware-owned even when software writes nearby IO.",
    files: ["lib/gb_emu/bus.ex", "docs/memory.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "032",
    section: "bus",
    title: "Implement OAM DMA",
    goal: "Copy 160 bytes from source page value << 8 into sprite memory.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "033",
    section: "mbc",
    title: "Enable and disable cartridge RAM",
    goal: "Honor the $0000-$1FFF RAM enable command.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "034",
    section: "mbc",
    title: "Switch MBC1 low ROM bits",
    goal: "Map writes at $2000-$3FFF to MBC1 bank selection with bank-zero remap.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "035",
    section: "mbc",
    title: "Switch MBC1 upper bits and mode",
    goal: "Use $4000-$5FFF and $6000-$7FFF commands for larger MBC1 cartridges.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "036",
    section: "mbc",
    title: "Switch MBC5 ROM banks",
    goal: "Implement the 9-bit MBC5 ROM bank number.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "037",
    section: "mbc",
    title: "Switch MBC5 RAM banks",
    goal: "Use the low RAM-bank nibble for external RAM addressing.",
    files: ["lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "038",
    section: "cpu-fetch",
    title: "Fetch an opcode",
    goal: "Read the opcode at PC, increment PC, and dispatch.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "039",
    section: "cpu-fetch",
    title: "Fetch immediate bytes",
    goal: "Implement fetch8 and fetch16 with correct PC wrapping.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "040",
    section: "cpu-fetch",
    title: "Represent register pairs",
    goal: "Create BC, DE, HL getters and setters from 8-bit fields.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "041",
    section: "cpu-loads",
    title: "Implement NOP and LD rr,d16",
    goal: "Execute the first simple opcodes with correct cycle counts.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "042",
    section: "cpu-loads",
    title: "Implement LD (rr),A and LD A,(rr)",
    goal: "Move A through BC, DE, and HL-indirect memory paths.",
    files: ["lib/gb_emu/cpu.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "043",
    section: "cpu-loads",
    title: "Implement HL auto-increment and decrement loads",
    goal: "Support LDI and LDD addressing patterns used by boot and copy loops.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "044",
    section: "cpu-loads",
    title: "Implement register-indexed LD r,r",
    goal: "Collapse 64 load opcodes using SM83 register indices.",
    files: ["lib/gb_emu/cpu.ex", "docs/cpu.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "045",
    section: "cpu-loads",
    title: "Implement LD r,d8",
    goal: "Load immediates into registers and (HL) with extra memory cycles.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "046",
    section: "cpu-loads",
    title: "Implement high-memory loads",
    goal: "Support LDH and C-indexed IO addressing.",
    files: ["lib/gb_emu/cpu.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "047",
    section: "cpu-arithmetic",
    title: "Implement INC and DEC",
    goal: "Update Z, N, H, and preserved C flags for register and memory operands.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "048",
    section: "cpu-arithmetic",
    title: "Implement ADD and ADC",
    goal: "Add operands into A with half-carry and carry detection.",
    files: ["lib/gb_emu/cpu.ex", "docs/cpu.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "049",
    section: "cpu-arithmetic",
    title: "Implement SUB and SBC",
    goal: "Subtract operands from A with N, H, C, and Z flags.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "050",
    section: "cpu-arithmetic",
    title: "Implement AND, XOR, OR, and CP",
    goal: "Finish the regular ALU opcode quadrant.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "051",
    section: "cpu-arithmetic",
    title: "Implement DAA and complement instructions",
    goal: "Handle the irregular accumulator and flag instructions used by test ROMs.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "052",
    section: "cpu-control",
    title: "Implement relative jumps",
    goal: "Parse signed 8-bit offsets and apply conditional cycle counts.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "053",
    section: "cpu-control",
    title: "Implement absolute jumps and calls",
    goal: "Move PC to 16-bit targets and push return addresses for CALL.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "054",
    section: "cpu-control",
    title: "Implement RET, RETI, and RST",
    goal: "Pop PC, restore IME when appropriate, and support restart vectors.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "055",
    section: "cpu-stack",
    title: "Implement PUSH and POP",
    goal: "Move register pairs through stack memory with Game Boy byte order.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "056",
    section: "cpu-stack",
    title: "Mask POP AF",
    goal: "Ensure the lower four bits of F stay zero after stack restore.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "057",
    section: "cpu-control",
    title: "Implement ADD HL,rr and SP math",
    goal: "Handle 16-bit arithmetic and the signed ADD SP,e8 flag rules.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "058",
    section: "cpu-control",
    title: "Implement rotates on A",
    goal: "Support RLCA, RRCA, RLA, and RRA with correct zero flag behavior.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "059",
    section: "cpu-cb",
    title: "Enter the CB opcode table",
    goal: "Fetch the prefixed opcode and dispatch without losing cycle accuracy.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "060",
    section: "cpu-cb",
    title: "Implement CB rotates and shifts",
    goal: "Support RLC, RRC, RL, RR, SLA, SRA, SWAP, and SRL.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "061",
    section: "cpu-cb",
    title: "Implement BIT",
    goal: "Test individual bits while preserving carry and setting H.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "062",
    section: "cpu-cb",
    title: "Implement RES and SET",
    goal: "Clear and set bits in registers and (HL).",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "063",
    section: "interrupts",
    title: "Model interrupt registers",
    goal: "Add IE, IF, IME, ime_pending, and halted state transitions.",
    files: ["lib/gb_emu/gb.ex", "lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "064",
    section: "interrupts",
    title: "Implement EI delay and DI",
    goal: "Make EI take effect after the following instruction.",
    files: ["lib/gb_emu/cpu.ex", "docs/cpu.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "065",
    section: "interrupts",
    title: "Implement HALT behavior",
    goal: "Burn cycles while halted and resume when interrupt flags become pending.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "066",
    section: "interrupts",
    title: "Service interrupts",
    goal: "Choose the lowest pending bit, clear IF, push PC, and jump to the vector.",
    files: ["lib/gb_emu/cpu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "067",
    section: "timer",
    title: "Advance DIV",
    goal: "Increment the internal divider by elapsed T-cycles and expose the high byte.",
    files: ["lib/gb_emu/timer.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "068",
    section: "timer",
    title: "Decode TAC frequencies",
    goal: "Map Game Boy timer control bits to cycle periods.",
    files: ["lib/gb_emu/timer.ex", "docs/timing-and-io.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "069",
    section: "timer",
    title: "Overflow TIMA into TMA",
    goal: "Raise the timer interrupt when TIMA overflows and reload modulo.",
    files: ["lib/gb_emu/timer.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "070",
    section: "serial",
    title: "Represent an idle serial transfer",
    goal: "Leave an inactive or external-clock transfer pending until a clock advances it.",
    files: ["lib/gb_emu/machine.ex", "lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "071",
    section: "serial",
    title: "Complete internal-clock serial transfers",
    goal: "Append completed serial bytes after the correct number of cycles.",
    files: ["lib/gb_emu/machine.ex", "lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "072",
    section: "joypad",
    title: "Represent the joypad matrix",
    goal: "Track direction and button groups as pressed-bit masks.",
    files: ["lib/gb_emu/gb.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "073",
    section: "joypad",
    title: "Read JOYP",
    goal: "Return selected low-nibble button state with active-low hardware semantics.",
    files: ["lib/gb_emu/bus.ex", "docs/timing-and-io.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "074",
    section: "joypad",
    title: "Raise joypad interrupts",
    goal: "Request an interrupt when a key transitions into the pressed state.",
    files: ["lib/gb_emu/machine.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "075",
    section: "ppu-state",
    title: "Project PPU transition state",
    goal: "Capture mode, dot, scanline, and frame counters before a PPU transition.",
    files: ["lib/gb_emu/ppu.ex", "docs/ppu.md"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "076",
    section: "ppu-state",
    title: "Handle LCD off",
    goal: "Keep the PPU idle and reset LY/mode when LCDC bit 7 is clear.",
    files: ["lib/gb_emu/ppu.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "077",
    section: "ppu-state",
    title: "Advance PPU modes",
    goal: "Walk mode 2, mode 3, HBlank, and VBlank with correct dot counts.",
    files: ["lib/gb_emu/ppu.ex", "docs/ppu.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "078",
    section: "ppu-state",
    title: "Update LY and LYC",
    goal: "Compare scanline counters and update STAT coincidence.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "079",
    section: "ppu-state",
    title: "Raise STAT interrupts",
    goal: "Trigger mode and coincidence interrupts only when enabled.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "080",
    section: "ppu-render",
    title: "Read tile row bytes",
    goal: "Locate tile data and decode one 8-pixel row from VRAM.",
    files: ["lib/gb_emu/ppu.ex", "lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "081",
    section: "ppu-render",
    title: "Render a background line",
    goal: "Use SCX, SCY, tile map selection, and wrapping to produce 160 pixels.",
    files: ["lib/gb_emu/ppu.ex", "docs/ppu.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "082",
    section: "ppu-render",
    title: "Support signed tile addressing",
    goal: "Map signed tile IDs through the $9000 addressing mode.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "083",
    section: "ppu-render",
    title: "Apply palettes",
    goal: "Convert color indices through BGP, OBP0, and OBP1 shade registers.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "084",
    section: "ppu-render",
    title: "Render the window",
    goal: "Overlay the window tile map and maintain its independent line counter.",
    files: ["lib/gb_emu/ppu.ex", "docs/ppu.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "085",
    section: "ppu-render",
    title: "Scan OAM for sprites",
    goal: "Find up to 10 visible sprites for the current scanline.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "086",
    section: "ppu-render",
    title: "Render sprite pixels",
    goal: "Apply X/Y flip, object palette selection, and transparent color 0.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "087",
    section: "ppu-render",
    title: "Merge sprites with background",
    goal: "Honor DMG priority rules using raw background color index 0.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "088",
    section: "ppu-render",
    title: "Finish a frame",
    goal: "Concatenate 144 scanlines into a 160x144 shade buffer and raise VBlank.",
    files: ["lib/gb_emu/ppu.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "089",
    section: "machine",
    title: "Step one instruction boundary",
    goal: "Advance CPU, PPU, timer, and serial by the same T-cycle count.",
    files: ["lib/gb_emu/machine.ex"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "090",
    section: "machine",
    title: "Run one full frame",
    goal: "Repeat instruction boundaries until exactly one DMG frame has elapsed.",
    files: ["lib/gb_emu/machine.ex", "docs/architecture.md"],
    checks: ["mix test test/gb_emu/machine_test.exs"]
  },
  %{
    id: "091",
    section: "machine",
    title: "Load a new ROM into the machine",
    goal: "Rebuild machine state while preserving boot-source policy.",
    files: ["lib/gb_emu/emulator.ex", "lib/gb_emu/gb.ex"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "092",
    section: "otp",
    title: "Wrap the machine in a GenServer",
    goal: "Make one emulator process own one authoritative machine state.",
    files: ["lib/gb_emu/emulator.ex"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "093",
    section: "otp",
    title: "Schedule real-time frames",
    goal: "Use Process.send_after with drift-aware deadlines and stale timer tokens.",
    files: ["lib/gb_emu/emulator.ex", "docs/architecture.md"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "094",
    section: "otp",
    title: "Pause, resume, and reset",
    goal: "Expose safe controls for LiveView and debugger commands.",
    files: ["lib/gb_emu/emulator.ex"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "095",
    section: "otp",
    title: "Limit active emulator sessions",
    goal: "Use supervised state to cap concurrent public emulator workers.",
    files: ["lib/gb_emu/emulator_sessions.ex", "lib/gb_emu/application.ex"],
    checks: ["mix test test/gb_emu/emulator_sessions_test.exs"]
  },
  %{
    id: "096",
    section: "phoenix",
    title: "Mount the LiveView shell",
    goal:
      "Render the emulator page through Layouts.app with disabled controls before a ROM is available.",
    files: ["lib/gb_emu_web/live/emulator_live.ex", "lib/gb_emu_web/components/layouts.ex"],
    checks: ["mix test test/gb_emu_web/live/emulator_live_test.exs"]
  },
  %{
    id: "097",
    section: "phoenix",
    title: "Stream frames to the browser",
    goal: "Push base64 frame binaries to a canvas hook without putting game logic in JavaScript.",
    files: ["lib/gb_emu_web/live/emulator_live.ex", "assets/js/app.js"],
    checks: ["mix test test/gb_emu_web/live/emulator_live_test.exs"]
  },
  %{
    id: "098",
    section: "phoenix",
    title: "Send keyboard input back",
    goal: "Map browser keydown and keyup events to joypad button events.",
    files: ["lib/gb_emu_web/live/emulator_live.ex", "assets/js/app.js"],
    checks: ["mix test test/gb_emu_web/live/emulator_live_test.exs"]
  },
  %{
    id: "099",
    section: "phoenix",
    title: "Add upload forms",
    goal: "Use LiveView uploads for legal game ROMs and optional boot ROM files.",
    files: ["lib/gb_emu_web/live/emulator_live.ex", "config/config.exs"],
    checks: ["mix test test/gb_emu_web/live/emulator_live_test.exs"]
  },
  %{
    id: "100",
    section: "uploads",
    title: "Create signed upload sessions",
    goal: "Assign each browser a durable signed session id for server-side uploads.",
    files: ["lib/gb_emu_web/upload_session.ex", "lib/gb_emu_web/session.ex"],
    checks: ["mix test test/gb_emu_web/session_test.exs"]
  },
  %{
    id: "101",
    section: "uploads",
    title: "Store uploads outside the release",
    goal:
      "Copy uploaded files into a configurable per-session directory with private permissions.",
    files: ["lib/gb_emu/upload_store.ex", "docs/roms.md"],
    checks: ["mix test test/gb_emu/upload_store_test.exs"]
  },
  %{
    id: "102",
    section: "uploads",
    title: "Expire inactive upload sessions",
    goal: "Tie browser cookie lifetime and server cleanup to GB_EMU_UPLOAD_TTL_MS.",
    files: ["lib/gb_emu/upload_store.ex", "lib/gb_emu_web/session.ex"],
    checks: ["mix test test/gb_emu/upload_store_test.exs test/gb_emu_web/session_test.exs"]
  },
  %{
    id: "103",
    section: "debugger",
    title: "Attach to the authoritative emulator",
    goal: "Pause real-time execution and inspect the same machine that drives the canvas.",
    files: ["lib/gb_emu/debugger.ex", "lib/gb_emu/emulator.ex"],
    checks: ["mix test test/gb_emu/emulator_debugger_test.exs"]
  },
  %{
    id: "104",
    section: "debugger",
    title: "Project a safe snapshot",
    goal: "Expose CPU, PPU, memory, and instruction summaries without leaking mutable atomics.",
    files: ["lib/gb_emu/debugger/snapshot.ex", "lib/gb_emu/debugger.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "105",
    section: "debugger",
    title: "Disassemble the current instruction",
    goal: "Turn bytes at PC into readable instruction metadata for the workbench.",
    files: ["lib/gb_emu/debugger/disassembler.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "106",
    section: "debugger",
    title: "Trace memory side effects",
    goal: "Record bounded read, write, DMA, and source-location events for debugger commands.",
    files: ["lib/gb_emu/debugger/trace.ex", "lib/gb_emu/bus.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs"]
  },
  %{
    id: "107",
    section: "debugger",
    title: "Render the debugger sidebar",
    goal:
      "Build the accessible instruction workbench, registers, memory grid, PPU panel, and trace list.",
    files: ["lib/gb_emu_web/components/debugger_components.ex"],
    checks: ["mix test test/gb_emu_web/live/emulator_live_test.exs"]
  },
  %{
    id: "108",
    section: "debugger",
    title: "Implement bounded debugger commands",
    goal:
      "Run step, step-10, next scanline, next PPU event, and next frame without unbounded loops.",
    files: ["lib/gb_emu/debugger.ex", "lib/gb_emu_web/live/emulator_live.ex"],
    checks: ["mix test test/gb_emu/debugger_test.exs test/gb_emu_web/live/emulator_live_test.exs"]
  },
  %{
    id: "109",
    section: "docs-and-release",
    title: "Write the ROM and trademark policy",
    goal: "Document legal ROM/BIOS expectations before any public release.",
    files: ["README.md", "docs/roms.md", "priv/roms/README.md"],
    checks: ["mix test"]
  },
  %{
    id: "110",
    section: "docs-and-release",
    title: "Ship the complete emulator",
    goal:
      "Run precommit, verify no private ROMs are included, build assets, and deploy the Phoenix release.",
    files: ["mix.exs", "config/runtime.exs", ".env.example", "README.md"],
    checks: ["mix precommit", "mix assets.deploy", "MIX_ENV=prod mix release --overwrite"]
  }
]
