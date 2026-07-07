# The PPU: pixel pipeline

`lib/gb_emu/ppu.ex` emulates the LCD controller. It has two halves: a
**state machine** that tracks where the electron-beam-equivalent is, and a
**scanline renderer** that produces actual pixels.

## The LCD state machine

A frame is 154 scanlines of 456 dots (T-cycles) each = 70,224 dots.
Lines 0-143 are visible; 144-153 are the vertical blanking interval.
Each visible line cycles through three modes:

```
line 0..143:  [ mode 2: OAM scan ][ mode 3: drawing ][ mode 0: HBlank ]
                0..79 dots          80..251            252..455
line 144..153: [ mode 1: VBlank, whole line ]
```

`PPU.step(gb, cycles)` adds elapsed cycles to a dot counter and walks mode
transitions recursively until the counter is spent. Things that happen on
transitions:

- **mode 3 → 0**: the scanline is rendered (one shot, at HBlank start).
- **line increment**: LY is compared with LYC; the STAT coincidence bit
  and (if enabled) STAT interrupt fire.
- **entering line 144**: the frame is assembled, the VBlank interrupt
  (`IF` bit 0) fires — this is what wakes games sleeping in `HALT`-based
  `vsync()` loops.
- Each mode change can raise a STAT interrupt if the corresponding enable
  bit (3, 4 or 5) is set.

If LCDC bit 7 is off the PPU does nothing at all — boot code and games
disable the LCD while loading VRAM.

## Scanline rendering

The renderer produces one 160-byte binary per line (one byte per pixel,
final 2-bit shade after palette mapping). Rendering per scanline rather
than per frame is what makes raster effects work: games can change
`SCX`/`SCY` and palettes mid-frame, and startup/logo effects from a
user-supplied boot ROM would break if everything rendered only at VBlank.

### Background

The BG is a 32x32 tile map (256x256 px) scrolled by SCY/SCX with
wraparound. Instead of computing each of the 160 pixels independently,
`tile_row_pixels/3` renders the **entire 256-pixel map row** (32 tile
lookups), then slices 160 pixels starting at `SCX`:

```elixir
lo = :atomics.get(vram, data_addr + py * 2 + 1)
hi = :atomics.get(vram, data_addr + py * 2 + 2)
elem(table, lo ||| hi <<< 8)   # -> 8 color indices, one lookup
```

`table` is the precomputed 64K-entry decode table (see
[architecture.md](architecture.md)) that converts the Game Boy's planar
2bpp format (bit *n* of `lo` = low bit of pixel, bit *n* of `hi` = high
bit) into 8 pixel values in one step.

Tile IDs resolve through one of two addressing modes (LCDC bit 4):
unsigned from `$8000`, or signed from `$9000` — the latter is used by
several startup and UI tile patterns.

### Window

The window is a second, non-scrolling tile map overlaid from position
(WX-7, WY). Many games use it for dialogs, menus, HUDs, or on-screen
keyboards.

The window has a famous hardware quirk that this emulator reproduces
because real software depends on it: **the window keeps its own line
counter**, which only advances on scanlines where the window was actually
rendered. If a game moves WY mid-frame or hides the window for a few
lines, the window content must *pause*, not skip. Using `LY - WY` instead
produces garbled dialogs.

### Sprites (OBJ)

Per scanline:

1. Scan all 40 OAM entries, keep those covering this line (8- or 16-pixel
   tall per LCDC bit 2), cap at **10 sprites per line** (hardware limit,
   selected in OAM order).
2. Sort by DMG priority: lower X wins, ties broken by OAM index.
3. Fold them into an `x -> {color, palette, behind_bg}` map, iterating in
   *reverse* priority so higher-priority pixels overwrite lower ones.
   Color 0 is transparent and never lands in the map.
4. Merge over the BG line: a sprite pixel loses only if its `behind_bg`
   attribute flag is set *and* the BG pixel is nonzero.

The merge uses raw BG **color indices** (pre-palette), because the
behind-BG rule compares against color 0, not shade 0 — a palette could map
any index to any shade.

### Palettes

BGP, OBP0 and OBP1 are 8-bit registers holding four 2-bit shades each.
Shades are applied server-side (`pal >>> (index * 2) &&& 3`); mapping the
final 0-3 shade to actual colors (the green DMG palette) happens in the
browser, keeping the wire format 1 byte per pixel.

## Frame assembly

Rendered lines accumulate in `fb_lines` (a map of `ly -> binary`). On
entering VBlank, `finish_frame/1` concatenates lines 0-143 into a single
23,040-byte binary and bumps `frame_count`. Missing lines (LCD switched
on mid-frame) fall back to blank.
