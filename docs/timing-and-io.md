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

## The Serial Port Stub

`$FF01` (SB, data) and `$FF02` (SC, control) form the link-cable serial port.
The emulator has no link partner, but it cannot just ignore these registers.

Some homebrew and test ROMs poll serial hardware every frame, including inside
"wait for input" loops:

```c
static uint8_t serial_exchange(void) {
    SB_REG = 0x00u;
    SC_REG = SIOF_CLOCK_INT | SIOF_XFER_START;   // write 0x81
    while (timeout && (SC_REG & SIOF_XFER_START)) timeout--;
    if (!timeout) { SC_REG = 0x00u; return 0xFFu; }
    return SB_REG;
}
```

The stub therefore models "transfer started, nobody on the other end": writing
`$FF02` with bit 7 set completes the transfer immediately. SB is loaded with
`$FF` (an idle link line reads all 1s), SC bit 7 is cleared, and serial
interrupt bit 3 is raised. Programs that use this pattern translate `$FF` to "no
key" and move on.

The captured serial bytes also double as a debug channel: many public test ROMs
print their results over serial, and `gb.serial_out` is where those bytes are
recorded for local debugging.
