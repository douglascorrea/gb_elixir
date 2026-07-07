# The CPU: SM83 interpreter

`lib/gb_emu/cpu.ex` implements the Game Boy's CPU (the Sharp SM83 — a
Z80/8080 hybrid). It is a classic interpreter: fetch a byte, dispatch on
it, mutate the register state, report elapsed T-cycles. It passes all 11
sub-tests of blargg's `cpu_instrs` test ROM.

## Entry point

```elixir
{gb, t_cycles} = GbEmu.CPU.step(gb)
```

`step/1` does three things, in priority order:

1. **Interrupt dispatch** — if `IME` is set and `IE & IF` has pending bits,
   push `pc`, jump to the vector (`$40` VBlank, `$48` STAT, `$50` Timer,
   `$58` Serial, `$60` Joypad), clear the served `IF` bit. Costs 20 cycles.
2. **HALT handling** — a halted CPU with no pending interrupt just burns 4
   cycles. A pending interrupt wakes it (even with `IME` off, per hardware).
3. **Execute** — fetch the opcode at `pc` and run it.

## Dispatch strategy

Rather than 512 hand-written handlers, the opcode space is exploited for
its regularity. The SM83 encodes registers as 3-bit indices
(`0=B 1=C 2=D 3=E 4=H 5=L 6=(HL) 7=A`), so whole quadrants collapse into a
few clauses:

```elixir
# 64 opcodes (0x40-0x7F): LD r, r'
defp exec(op, gb) when op in 0x40..0x7F do
  {v, e1} = reg_get(gb, op &&& 7)
  {gb, e2} = reg_set(gb, op >>> 3 &&& 7, v)
  {gb, 4 + e1 + e2}
end

# 64 opcodes (0x80-0xBF): ADD/ADC/SUB/SBC/AND/XOR/OR/CP A, r
defp exec(op, gb) when op in 0x80..0xBF do
  {v, extra} = reg_get(gb, op &&& 7)
  {alu(gb, op >>> 3 &&& 7, v), 4 + extra}
end
```

`reg_get/2` and `reg_set/3` return an *extra-cycles* value: index 6 is the
memory-indirect `(HL)` pseudo-register, which costs 4 additional T-cycles.
This one convention gives correct per-opcode timing across all the grouped
clauses without a cycle table.

The entire 256-opcode CB prefix (rotates, shifts, `SWAP`, `BIT`, `RES`,
`SET`) is 4 clauses in `exec_cb/2`, dispatching on `op >>> 6` and reusing
the same register indexing.

Irregular opcodes (`DAA`, `ADD SP,e8`, conditional jumps, `RST`, ...) get
individual clauses. Elixir compiles integer-literal heads into a BEAM jump
table, so dispatch is cheap.

## Flags

The F register is kept as a plain integer (`Z=0x80 N=0x40 H=0x20 C=0x10`),
recomputed wholesale by each ALU helper rather than bit-flipped piecemeal:

```elixir
defp alu_add(gb, v, carry) do
  sum = gb.a + v + carry
  r = sum &&& 0xFF
  f = if(r == 0, do: @z, else: 0)
      ||| if((gb.a &&& 0xF) + (v &&& 0xF) + carry > 0xF, do: @h, else: 0)
      ||| if(sum > 0xFF, do: @c, else: 0)
  %{gb | a: r, f: f}
end
```

Two flag subtleties that test ROMs catch:

- `POP AF` masks the low nibble (`v &&& 0xF0`) — the four unused F bits
  always read as zero on hardware.
- `ADD SP,e8` / `LD HL,SP+e8` compute H and C from the *unsigned low byte*
  addition even though the operand is signed, and always clear Z and N.

## EI delay

`EI` doesn't enable interrupts immediately — it takes effect after the
*following* instruction (so `EI; RET` can't be interrupted between the two).
This is modeled with an `ime_pending` flag: `execute/1` captures it before
running the instruction and promotes it to `ime: true` afterwards.

## What's intentionally simplified

- `STOP` is treated as a 2-byte NOP (no CGB double-speed switch on DMG).
- The HALT bug (PC failing to increment when HALT is entered with
  `IME=0` and pending interrupts) is not emulated; no ROM in the repo
  relies on it.
- Undefined opcodes execute as NOPs instead of locking up the CPU.
