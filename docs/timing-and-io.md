# Timers, joypad, and the serial port

## Timers (`lib/gb_emu/timer.ex`)

Two timers share `Timer.step(gb, cycles)`:

**DIV (`$FF04`)** - a free-running 16-bit counter incremented every T-cycle. The
register exposes its upper byte, so it visibly ticks at 16,384 Hz. Any write
resets it to zero. Games often use DIV as a cheap entropy source, so exact input
timing can affect game state.

**TIMA (`$FF05`)** - the programmable timer. When TAC bit 2 enables it, TIMA
increments every 1024/16/64/256 T-cycles (TAC bits 0-1). On overflow it reloads
from TMA (`$FF06`) and raises interrupt bit 2. Implementation is a cycle
accumulator drained in a `tick_tima/2` loop, so a long instruction that spans
multiple timer periods still produces multiple increments.

## Joypad (`Bus.joyp_value/1`)

The Game Boy reads 8 buttons through a 2x4 matrix at `$FF00`, and the register
is **active-low in both directions** - 0 means "selected" / "pressed":

```text
bit 5: select action buttons  (A, B, Select, Start)
bit 4: select direction pad   (Right, Left, Up, Down)
bits 3-0: key states for the selected group (0 = pressed)
```

The emulator stores pressed state as normal 1-bits (`gb.dpad`, `gb.btns`) and
inverts at read time:

```elixir
base &&& bnot(pressed) &&& 0xFF
```

A game reads the pad by writing `$20` (select d-pad), reading, writing `$10`
(select buttons), reading several times for hardware debounce, then writing
`$30` to deselect. Key presses arrive from the browser via
`GbEmu.Machine.set_button/3`, which also raises the joypad interrupt (bit 4) on
press.

## The serial port (link cable)

`$FF01` (SB, data) and `$FF02` (SC, control) form the link-cable serial port.
Bit 7 of SC starts a transfer; bit 0 selects the clock source
(1 = internal, 0 = external / waiting for a partner).

**Internal clock** (blargg tests, some homebrew): the transfer completes after
~4096 T-cycles. `Machine.step_serial/2` counts those cycles, writes `$FF` into
SB (idle line), clears SC bit 7, and raises the serial interrupt. Outgoing
bytes are appended to `gb.serial_out` so tests can read results like
"Passed all tests".

**External clock** (Tetris title screen): with no link partner the transfer must
stay pending forever. An earlier stub completed *every* transfer instantly,
which made Tetris think a 2-player handshake had finished and skip its Start
handler — Start appeared broken and the title screen could look like it was
"blinking". Completing only internal-clock transfers fixed that.

## Debug logging

In `config/dev.exs`, `config :gb_emu, debug_input: true` logs:

- every joypad press/release
- once per second: `frame`, `pc`, `lcdc`, Tetris-style `E1` state, key HRAM,
  button bits, and serial state

Watch the Phoenix terminal while pressing Start to confirm input is reaching
the emulator.
