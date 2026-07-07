# The memory bus

`lib/gb_emu/bus.ex` is the single chokepoint for every byte the CPU reads
or writes. It encodes the Game Boy's address map, cartridge banking, and
all IO registers.

## Address map

| Range | What | Backing store |
| --- | --- | --- |
| `$0000-$00FF` | Boot ROM *while `boot_enabled`* | `gb.boot` binary |
| `$0000-$3FFF` | Cartridge ROM bank 0 | `gb.rom` binary |
| `$4000-$7FFF` | Cartridge ROM bank N (switchable) | `gb.rom` binary + bank offset |
| `$8000-$9FFF` | VRAM (tiles + tile maps) | `:atomics` |
| `$A000-$BFFF` | Cartridge RAM (if enabled) | `:atomics` |
| `$C000-$DFFF` | Work RAM | `:atomics` |
| `$E000-$FDFF` | Echo RAM (mirror of WRAM) | same `:atomics` |
| `$FE00-$FE9F` | OAM (sprite attributes) | `:atomics` |
| `$FF00-$FF7F` | IO registers | struct fields / `io_misc` atomics |
| `$FF80-$FFFE` | HRAM | `:atomics` |
| `$FFFF` | IE (interrupt enable) | struct field |

Reads of unusable/disabled regions return `$FF` (open bus), which matters:
games probe cartridge RAM this way.

## Why two kinds of storage?

**Hot, frequently-written registers** (LCDC, STAT, SCY/SCX, palettes, IF,
timer state, joypad) are struct fields — the PPU and timer read them every
step, and pattern-matching on struct fields is faster than atomics calls.

**Bulk memory** is `:atomics` — mutable arrays that live off the process
heap. Writing a byte of VRAM doesn't produce a new 8 KB binary, and the
GB struct stays small so its per-instruction updates stay cheap. The
trade-off is that `Bus.write8/3` sometimes returns the same struct
(atomics write) and sometimes an updated one (register write); the CPU
treats every write as returning the authoritative struct.

## Writes to ROM = MBC commands

Cartridge ROM is read-only, so writes to `$0000-$7FFF` are commands to the
Memory Bank Controller chip. The cartridge type byte at header offset
`$0147` selects the controller in `GbEmu.GB.new/2`:

- **MBC0** (`:none`) — 32 KB fixed-bank ROMs. Writes are ignored.
- **MBC1** — 5-bit ROM bank at `$2000` (bank 0 maps to 1), 2-bit upper
  bits/RAM bank at `$4000`, mode switch at `$6000`.
- **MBC5** — 8-bit ROM bank at `$2000` + 9th bit at `$3000`, RAM bank at
  `$4000`, RAM enable via `$0A` at `$0000`.

Banked reads compute a flat offset into the ROM binary:

```elixir
offset = (gb.rom_bank &&& gb.rom_bank_mask) * 0x4000 + (addr - 0x4000)
```

`rom_bank_mask` wraps out-of-range bank numbers, matching hardware
behavior where unused bank pins float.

## The boot ROM overlay

The first 256 bytes are special: while `boot_enabled` is true they read from
`gb.boot` instead of the cartridge. The public repository's default boot binary
is an open stub from `GbEmu.BootRom.minimal/0`; a legally obtained local DMG BIOS
can be supplied with `GB_EMU_BOOT_ROM`.

The cartridge header (`$0100+`) remains visible while the overlay is active.
Writing any nonzero value to `$FF50` clears the overlay permanently (there is no
way to map it back, same as hardware).

## OAM DMA

Writing `$FF46` triggers sprite DMA: 160 bytes are copied from `value <<< 8`
into OAM. Real hardware takes 160 µs and locks the CPU out of most memory;
here the copy is instantaneous, which is a safe simplification for games
that follow the standard "copy routine in HRAM + busy-wait" pattern.

## IO register quirks worth knowing

- **`$FF00` (joypad)** is a 2x4 key matrix; see
  [timing-and-io.md](timing-and-io.md).
- **`$FF04` (DIV)** — *any* write resets the internal 16-bit divider
  counter to 0. Reads return its upper byte.
- **`$FF41` (STAT)** — bits 0-2 (mode + LYC flag) are read-only; writes
  only affect the interrupt-enable bits 3-6.
- **`$FF44` (LY)** is read-only.
- **`$FF40` (LCDC)** — turning bit 7 off stops the PPU and forces
  `LY = 0`, mode 0. Boot code often does this before loading tiles.
- **Sound registers (`$FF10-$FF3F`)** are stored in the `io_misc` scratch
  array so games can read back what they wrote, but no audio is produced.
