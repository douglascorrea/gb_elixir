defmodule GbEmu.CPU do
  @moduledoc """
  SM83 (Game Boy CPU) interpreter. `step/1` services pending interrupts,
  executes one instruction and returns `{gb, t_cycles}`.
  """

  import Bitwise
  alias GbEmu.{Bus, GB}

  @z 0x80
  @n 0x40
  @h 0x20
  @c 0x10

  @doc "Classifies the next CPU boundary without executing it."
  @spec boundary(GB.t()) :: map()
  def boundary(gb) do
    pending = gb.ie &&& gb.if_ &&& 0x1F

    cond do
      gb.ime and pending != 0 ->
        bit = pending &&& -pending
        Map.merge(%{kind: :interrupt, pending: pending}, interrupt(bit))

      gb.halted and pending == 0 ->
        %{kind: :halt, pending: pending}

      true ->
        %{kind: :instruction, pending: pending}
    end
  end

  @spec step(struct()) :: {struct(), pos_integer()}
  def step(gb) do
    pending = gb.ie &&& gb.if_ &&& 0x1F

    cond do
      gb.ime and pending != 0 ->
        {service_interrupt(gb, pending), 20}

      gb.halted ->
        if pending != 0 do
          # IME off: exit halt, continue execution
          execute(%{gb | halted: false})
        else
          {gb, 4}
        end

      true ->
        execute(gb)
    end
  end

  defp interrupt(0x01), do: %{interrupt: :vblank, vector: 0x40, bit: 0x01}
  defp interrupt(0x02), do: %{interrupt: :lcd_stat, vector: 0x48, bit: 0x02}
  defp interrupt(0x04), do: %{interrupt: :timer, vector: 0x50, bit: 0x04}
  defp interrupt(0x08), do: %{interrupt: :serial, vector: 0x58, bit: 0x08}
  defp interrupt(0x10), do: %{interrupt: :joypad, vector: 0x60, bit: 0x10}

  defp execute(gb) do
    ei_pending = gb.ime_pending
    op = Bus.read8(gb, gb.pc)
    gb = %{gb | pc: gb.pc + 1 &&& 0xFFFF}
    {gb, cycles} = exec(op, gb)
    gb = if ei_pending, do: %{gb | ime: true, ime_pending: false}, else: gb
    {gb, cycles}
  end

  defp service_interrupt(gb, pending) do
    bit = pending &&& -pending

    vector =
      case bit do
        0x01 -> 0x40
        0x02 -> 0x48
        0x04 -> 0x50
        0x08 -> 0x58
        _ -> 0x60
      end

    gb = %{gb | ime: false, halted: false, if_: gb.if_ &&& bnot(bit)}
    gb = push16(gb, gb.pc)
    %{gb | pc: vector}
  end

  # ---------------------------------------------------------------
  # 16-bit register helpers
  # ---------------------------------------------------------------

  defp hl(gb), do: gb.h <<< 8 ||| gb.l
  defp bc(gb), do: gb.b <<< 8 ||| gb.c
  defp de(gb), do: gb.d <<< 8 ||| gb.e

  defp set_hl(gb, v), do: %{gb | h: v >>> 8 &&& 0xFF, l: v &&& 0xFF}
  defp set_bc(gb, v), do: %{gb | b: v >>> 8 &&& 0xFF, c: v &&& 0xFF}
  defp set_de(gb, v), do: %{gb | d: v >>> 8 &&& 0xFF, e: v &&& 0xFF}

  defp fetch8(gb) do
    v = Bus.read8(gb, gb.pc)
    {%{gb | pc: gb.pc + 1 &&& 0xFFFF}, v}
  end

  defp fetch16(gb) do
    v = Bus.read16(gb, gb.pc)
    {%{gb | pc: gb.pc + 2 &&& 0xFFFF}, v}
  end

  defp push16(gb, v) do
    sp = gb.sp - 2 &&& 0xFFFF
    gb = Bus.write8(gb, sp + 1 &&& 0xFFFF, v >>> 8)
    gb = Bus.write8(gb, sp, v &&& 0xFF)
    %{gb | sp: sp}
  end

  defp pop16(gb) do
    lo = Bus.read8(gb, gb.sp)
    hi = Bus.read8(gb, gb.sp + 1 &&& 0xFFFF)
    {%{gb | sp: gb.sp + 2 &&& 0xFFFF}, hi <<< 8 ||| lo}
  end

  defp signed8(v), do: if(v > 127, do: v - 256, else: v)

  # Register index helpers: 0=B 1=C 2=D 3=E 4=H 5=L 6=(HL) 7=A
  defp reg_get(gb, 0), do: {gb.b, 0}
  defp reg_get(gb, 1), do: {gb.c, 0}
  defp reg_get(gb, 2), do: {gb.d, 0}
  defp reg_get(gb, 3), do: {gb.e, 0}
  defp reg_get(gb, 4), do: {gb.h, 0}
  defp reg_get(gb, 5), do: {gb.l, 0}
  defp reg_get(gb, 6), do: {Bus.read8(gb, hl(gb)), 4}
  defp reg_get(gb, 7), do: {gb.a, 0}

  defp reg_set(gb, 0, v), do: {%{gb | b: v}, 0}
  defp reg_set(gb, 1, v), do: {%{gb | c: v}, 0}
  defp reg_set(gb, 2, v), do: {%{gb | d: v}, 0}
  defp reg_set(gb, 3, v), do: {%{gb | e: v}, 0}
  defp reg_set(gb, 4, v), do: {%{gb | h: v}, 0}
  defp reg_set(gb, 5, v), do: {%{gb | l: v}, 0}
  defp reg_set(gb, 6, v), do: {Bus.write8(gb, hl(gb), v), 4}
  defp reg_set(gb, 7, v), do: {%{gb | a: v}, 0}

  # ---------------------------------------------------------------
  # Opcode dispatch
  # ---------------------------------------------------------------

  defp exec(0x00, gb), do: {gb, 4}

  # LD rr,d16
  defp exec(0x01, gb) do
    {gb, v} = fetch16(gb)
    {set_bc(gb, v), 12}
  end

  defp exec(0x11, gb) do
    {gb, v} = fetch16(gb)
    {set_de(gb, v), 12}
  end

  defp exec(0x21, gb) do
    {gb, v} = fetch16(gb)
    {set_hl(gb, v), 12}
  end

  defp exec(0x31, gb) do
    {gb, v} = fetch16(gb)
    {%{gb | sp: v}, 12}
  end

  # LD (rr),A / LD A,(rr) with HL inc/dec
  defp exec(0x02, gb), do: {Bus.write8(gb, bc(gb), gb.a), 8}
  defp exec(0x12, gb), do: {Bus.write8(gb, de(gb), gb.a), 8}

  defp exec(0x22, gb) do
    addr = hl(gb)
    gb = Bus.write8(gb, addr, gb.a)
    {set_hl(gb, addr + 1 &&& 0xFFFF), 8}
  end

  defp exec(0x32, gb) do
    addr = hl(gb)
    gb = Bus.write8(gb, addr, gb.a)
    {set_hl(gb, addr - 1 &&& 0xFFFF), 8}
  end

  defp exec(0x0A, gb), do: {%{gb | a: Bus.read8(gb, bc(gb))}, 8}
  defp exec(0x1A, gb), do: {%{gb | a: Bus.read8(gb, de(gb))}, 8}

  defp exec(0x2A, gb) do
    addr = hl(gb)
    {set_hl(%{gb | a: Bus.read8(gb, addr)}, addr + 1 &&& 0xFFFF), 8}
  end

  defp exec(0x3A, gb) do
    addr = hl(gb)
    {set_hl(%{gb | a: Bus.read8(gb, addr)}, addr - 1 &&& 0xFFFF), 8}
  end

  # INC/DEC rr
  defp exec(0x03, gb), do: {set_bc(gb, bc(gb) + 1 &&& 0xFFFF), 8}
  defp exec(0x13, gb), do: {set_de(gb, de(gb) + 1 &&& 0xFFFF), 8}
  defp exec(0x23, gb), do: {set_hl(gb, hl(gb) + 1 &&& 0xFFFF), 8}
  defp exec(0x33, gb), do: {%{gb | sp: gb.sp + 1 &&& 0xFFFF}, 8}
  defp exec(0x0B, gb), do: {set_bc(gb, bc(gb) - 1 &&& 0xFFFF), 8}
  defp exec(0x1B, gb), do: {set_de(gb, de(gb) - 1 &&& 0xFFFF), 8}
  defp exec(0x2B, gb), do: {set_hl(gb, hl(gb) - 1 &&& 0xFFFF), 8}
  defp exec(0x3B, gb), do: {%{gb | sp: gb.sp - 1 &&& 0xFFFF}, 8}

  # INC r / DEC r
  defp exec(op, gb) when op in [0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C] do
    idx = op >>> 3 &&& 7
    {v, extra} = reg_get(gb, idx)
    r = v + 1 &&& 0xFF

    f =
      (gb.f &&& @c) ||| if(r == 0, do: @z, else: 0) ||| if((v &&& 0x0F) == 0x0F, do: @h, else: 0)

    {gb, extra2} = reg_set(%{gb | f: f}, idx, r)
    {gb, 4 + extra + extra2}
  end

  defp exec(op, gb) when op in [0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D] do
    idx = op >>> 3 &&& 7
    {v, extra} = reg_get(gb, idx)
    r = v - 1 &&& 0xFF

    f =
      (gb.f &&& @c) ||| @n ||| if(r == 0, do: @z, else: 0) |||
        if((v &&& 0x0F) == 0, do: @h, else: 0)

    {gb, extra2} = reg_set(%{gb | f: f}, idx, r)
    {gb, 4 + extra + extra2}
  end

  # LD r,d8
  defp exec(op, gb) when op in [0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E] do
    idx = op >>> 3 &&& 7
    {gb, v} = fetch8(gb)
    {gb, extra} = reg_set(gb, idx, v)
    {gb, 8 + extra}
  end

  # Rotates on A
  defp exec(0x07, gb) do
    c = gb.a >>> 7
    {%{gb | a: (gb.a <<< 1 ||| c) &&& 0xFF, f: c <<< 4}, 4}
  end

  defp exec(0x0F, gb) do
    c = gb.a &&& 1
    {%{gb | a: gb.a >>> 1 ||| c <<< 7, f: c <<< 4}, 4}
  end

  defp exec(0x17, gb) do
    carry = gb.f >>> 4 &&& 1
    c = gb.a >>> 7
    {%{gb | a: (gb.a <<< 1 ||| carry) &&& 0xFF, f: c <<< 4}, 4}
  end

  defp exec(0x1F, gb) do
    carry = gb.f >>> 4 &&& 1
    c = gb.a &&& 1
    {%{gb | a: gb.a >>> 1 ||| carry <<< 7, f: c <<< 4}, 4}
  end

  # LD (a16),SP
  defp exec(0x08, gb) do
    {gb, addr} = fetch16(gb)
    gb = Bus.write8(gb, addr, gb.sp &&& 0xFF)
    gb = Bus.write8(gb, addr + 1 &&& 0xFFFF, gb.sp >>> 8)
    {gb, 20}
  end

  # ADD HL,rr
  defp exec(op, gb) when op in [0x09, 0x19, 0x29, 0x39] do
    v =
      case op do
        0x09 -> bc(gb)
        0x19 -> de(gb)
        0x29 -> hl(gb)
        0x39 -> gb.sp
      end

    h = hl(gb)
    sum = h + v

    f =
      (gb.f &&& @z) |||
        if((h &&& 0xFFF) + (v &&& 0xFFF) > 0xFFF, do: @h, else: 0) |||
        if(sum > 0xFFFF, do: @c, else: 0)

    {set_hl(%{gb | f: f}, sum &&& 0xFFFF), 8}
  end

  # STOP (treated as NOP; consumes one operand byte)
  defp exec(0x10, gb) do
    {gb, _} = fetch8(gb)
    {gb, 4}
  end

  # JR
  defp exec(0x18, gb) do
    {gb, off} = fetch8(gb)
    {%{gb | pc: gb.pc + signed8(off) &&& 0xFFFF}, 12}
  end

  defp exec(op, gb) when op in [0x20, 0x28, 0x30, 0x38] do
    {gb, off} = fetch8(gb)

    if cond_met?(gb, op >>> 3 &&& 3) do
      {%{gb | pc: gb.pc + signed8(off) &&& 0xFFFF}, 12}
    else
      {gb, 8}
    end
  end

  # DAA / CPL / SCF / CCF
  defp exec(0x27, gb) do
    a = gb.a
    f = gb.f

    {a, carry} =
      if (f &&& @n) == 0 do
        a = if (f &&& @h) != 0 or (a &&& 0x0F) > 9, do: a + 0x06, else: a
        if (f &&& @c) != 0 or a > 0x9F, do: {a + 0x60, true}, else: {a, (f &&& @c) != 0}
      else
        a = if (f &&& @h) != 0, do: a - 0x06 &&& 0xFF, else: a
        a = if (f &&& @c) != 0, do: a - 0x60, else: a
        {a, (f &&& @c) != 0}
      end

    a = a &&& 0xFF

    f =
      (f &&& @n) ||| if(a == 0, do: @z, else: 0) ||| if(carry, do: @c, else: 0)

    {%{gb | a: a, f: f}, 4}
  end

  defp exec(0x2F, gb), do: {%{gb | a: bxor(gb.a, 0xFF), f: gb.f ||| @n ||| @h}, 4}
  defp exec(0x37, gb), do: {%{gb | f: (gb.f &&& @z) ||| @c}, 4}
  defp exec(0x3F, gb), do: {%{gb | f: (gb.f &&& @z) ||| bxor(gb.f &&& @c, @c)}, 4}

  # HALT
  defp exec(0x76, gb), do: {%{gb | halted: true}, 4}

  # LD r,r'
  defp exec(op, gb) when op in 0x40..0x7F do
    {v, e1} = reg_get(gb, op &&& 7)
    {gb, e2} = reg_set(gb, op >>> 3 &&& 7, v)
    {gb, 4 + e1 + e2}
  end

  # ALU A, r
  defp exec(op, gb) when op in 0x80..0xBF do
    {v, extra} = reg_get(gb, op &&& 7)
    {alu(gb, op >>> 3 &&& 7, v), 4 + extra}
  end

  # ALU A, d8
  defp exec(op, gb) when op in [0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE] do
    {gb, v} = fetch8(gb)
    {alu(gb, op >>> 3 &&& 7, v), 8}
  end

  # RET cc / RET / RETI
  defp exec(op, gb) when op in [0xC0, 0xC8, 0xD0, 0xD8] do
    if cond_met?(gb, op >>> 3 &&& 3) do
      {gb, addr} = pop16(gb)
      {%{gb | pc: addr}, 20}
    else
      {gb, 8}
    end
  end

  defp exec(0xC9, gb) do
    {gb, addr} = pop16(gb)
    {%{gb | pc: addr}, 16}
  end

  defp exec(0xD9, gb) do
    {gb, addr} = pop16(gb)
    {%{gb | pc: addr, ime: true}, 16}
  end

  # POP / PUSH
  defp exec(0xC1, gb) do
    {gb, v} = pop16(gb)
    {set_bc(gb, v), 12}
  end

  defp exec(0xD1, gb) do
    {gb, v} = pop16(gb)
    {set_de(gb, v), 12}
  end

  defp exec(0xE1, gb) do
    {gb, v} = pop16(gb)
    {set_hl(gb, v), 12}
  end

  defp exec(0xF1, gb) do
    {gb, v} = pop16(gb)
    {%{gb | a: v >>> 8 &&& 0xFF, f: v &&& 0xF0}, 12}
  end

  defp exec(0xC5, gb), do: {push16(gb, bc(gb)), 16}
  defp exec(0xD5, gb), do: {push16(gb, de(gb)), 16}
  defp exec(0xE5, gb), do: {push16(gb, hl(gb)), 16}
  defp exec(0xF5, gb), do: {push16(gb, gb.a <<< 8 ||| (gb.f &&& 0xF0)), 16}

  # JP
  defp exec(0xC3, gb) do
    {gb, addr} = fetch16(gb)
    {%{gb | pc: addr}, 16}
  end

  defp exec(op, gb) when op in [0xC2, 0xCA, 0xD2, 0xDA] do
    {gb, addr} = fetch16(gb)

    if cond_met?(gb, op >>> 3 &&& 3) do
      {%{gb | pc: addr}, 16}
    else
      {gb, 12}
    end
  end

  defp exec(0xE9, gb), do: {%{gb | pc: hl(gb)}, 4}

  # CALL
  defp exec(0xCD, gb) do
    {gb, addr} = fetch16(gb)
    {%{push16(gb, gb.pc) | pc: addr}, 24}
  end

  defp exec(op, gb) when op in [0xC4, 0xCC, 0xD4, 0xDC] do
    {gb, addr} = fetch16(gb)

    if cond_met?(gb, op >>> 3 &&& 3) do
      {%{push16(gb, gb.pc) | pc: addr}, 24}
    else
      {gb, 12}
    end
  end

  # RST
  defp exec(op, gb) when op in [0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF] do
    {%{push16(gb, gb.pc) | pc: op &&& 0x38}, 16}
  end

  # LDH
  defp exec(0xE0, gb) do
    {gb, off} = fetch8(gb)
    {Bus.write8(gb, 0xFF00 + off, gb.a), 12}
  end

  defp exec(0xF0, gb) do
    {gb, off} = fetch8(gb)
    {%{gb | a: Bus.read8(gb, 0xFF00 + off)}, 12}
  end

  defp exec(0xE2, gb), do: {Bus.write8(gb, 0xFF00 + gb.c, gb.a), 8}
  defp exec(0xF2, gb), do: {%{gb | a: Bus.read8(gb, 0xFF00 + gb.c)}, 8}

  # LD (a16),A / LD A,(a16)
  defp exec(0xEA, gb) do
    {gb, addr} = fetch16(gb)
    {Bus.write8(gb, addr, gb.a), 16}
  end

  defp exec(0xFA, gb) do
    {gb, addr} = fetch16(gb)
    {%{gb | a: Bus.read8(gb, addr)}, 16}
  end

  # ADD SP,e8 / LD HL,SP+e8 / LD SP,HL
  defp exec(0xE8, gb) do
    {gb, off} = fetch8(gb)
    {sum, f} = sp_add(gb.sp, off)
    {%{gb | sp: sum, f: f}, 16}
  end

  defp exec(0xF8, gb) do
    {gb, off} = fetch8(gb)
    {sum, f} = sp_add(gb.sp, off)
    {set_hl(%{gb | f: f}, sum), 12}
  end

  defp exec(0xF9, gb), do: {%{gb | sp: hl(gb)}, 8}

  # DI / EI
  defp exec(0xF3, gb), do: {%{gb | ime: false, ime_pending: false}, 4}
  defp exec(0xFB, gb), do: {%{gb | ime_pending: true}, 4}

  # CB prefix
  defp exec(0xCB, gb) do
    {gb, op} = fetch8(gb)
    exec_cb(op, gb)
  end

  # Undefined opcodes: treat as NOP to avoid crashing
  defp exec(_op, gb), do: {gb, 4}

  # ---------------------------------------------------------------
  # CB-prefixed opcodes
  # ---------------------------------------------------------------

  defp exec_cb(op, gb) do
    idx = op &&& 7

    case op >>> 6 do
      0 ->
        {v, extra} = reg_get(gb, idx)
        {r, f} = cb_rot(op >>> 3 &&& 7, v, gb.f)
        {gb, extra2} = reg_set(%{gb | f: f}, idx, r)
        {gb, 8 + extra + extra2}

      1 ->
        {v, extra} = reg_get(gb, idx)
        bit = op >>> 3 &&& 7

        f =
          (gb.f &&& @c) ||| @h ||| if((v &&& 1 <<< bit) == 0, do: @z, else: 0)

        {%{gb | f: f}, 8 + extra}

      2 ->
        {v, extra} = reg_get(gb, idx)
        {gb, extra2} = reg_set(gb, idx, v &&& bnot(1 <<< (op >>> 3 &&& 7)))
        {gb, 8 + extra + extra2}

      3 ->
        {v, extra} = reg_get(gb, idx)
        {gb, extra2} = reg_set(gb, idx, v ||| 1 <<< (op >>> 3 &&& 7))
        {gb, 8 + extra + extra2}
    end
  end

  # returns {result, flags}
  defp cb_rot(0, v, _f) do
    c = v >>> 7
    r = (v <<< 1 ||| c) &&& 0xFF
    {r, rot_flags(r, c)}
  end

  defp cb_rot(1, v, _f) do
    c = v &&& 1
    r = v >>> 1 ||| c <<< 7
    {r, rot_flags(r, c)}
  end

  defp cb_rot(2, v, f) do
    carry = f >>> 4 &&& 1
    c = v >>> 7
    r = (v <<< 1 ||| carry) &&& 0xFF
    {r, rot_flags(r, c)}
  end

  defp cb_rot(3, v, f) do
    carry = f >>> 4 &&& 1
    c = v &&& 1
    r = v >>> 1 ||| carry <<< 7
    {r, rot_flags(r, c)}
  end

  defp cb_rot(4, v, _f) do
    c = v >>> 7
    r = v <<< 1 &&& 0xFF
    {r, rot_flags(r, c)}
  end

  defp cb_rot(5, v, _f) do
    c = v &&& 1
    r = v >>> 1 ||| (v &&& 0x80)
    {r, rot_flags(r, c)}
  end

  defp cb_rot(6, v, _f) do
    r = (v <<< 4 ||| v >>> 4) &&& 0xFF
    {r, rot_flags(r, 0)}
  end

  defp cb_rot(7, v, _f) do
    c = v &&& 1
    r = v >>> 1
    {r, rot_flags(r, c)}
  end

  defp rot_flags(r, c), do: if(r == 0, do: @z, else: 0) ||| c <<< 4

  # ---------------------------------------------------------------
  # ALU
  # ---------------------------------------------------------------

  # 0 ADD, 1 ADC, 2 SUB, 3 SBC, 4 AND, 5 XOR, 6 OR, 7 CP
  defp alu(gb, 0, v), do: alu_add(gb, v, 0)
  defp alu(gb, 1, v), do: alu_add(gb, v, gb.f >>> 4 &&& 1)
  defp alu(gb, 2, v), do: alu_sub(gb, v, 0, true)
  defp alu(gb, 3, v), do: alu_sub(gb, v, gb.f >>> 4 &&& 1, true)

  defp alu(gb, 4, v) do
    r = gb.a &&& v
    %{gb | a: r, f: if(r == 0, do: @z, else: 0) ||| @h}
  end

  defp alu(gb, 5, v) do
    r = bxor(gb.a, v)
    %{gb | a: r, f: if(r == 0, do: @z, else: 0)}
  end

  defp alu(gb, 6, v) do
    r = gb.a ||| v
    %{gb | a: r, f: if(r == 0, do: @z, else: 0)}
  end

  defp alu(gb, 7, v), do: alu_sub(gb, v, 0, false)

  defp alu_add(gb, v, carry) do
    a = gb.a
    sum = a + v + carry
    r = sum &&& 0xFF

    f =
      if(r == 0, do: @z, else: 0) |||
        if((a &&& 0xF) + (v &&& 0xF) + carry > 0xF, do: @h, else: 0) |||
        if(sum > 0xFF, do: @c, else: 0)

    %{gb | a: r, f: f}
  end

  defp alu_sub(gb, v, carry, store) do
    a = gb.a
    diff = a - v - carry
    r = diff &&& 0xFF

    f =
      @n ||| if(r == 0, do: @z, else: 0) |||
        if((a &&& 0xF) - (v &&& 0xF) - carry < 0, do: @h, else: 0) |||
        if(diff < 0, do: @c, else: 0)

    if store, do: %{gb | a: r, f: f}, else: %{gb | f: f}
  end

  defp sp_add(sp, off) do
    s = signed8(off)
    sum = sp + s &&& 0xFFFF

    f =
      if((sp &&& 0xF) + (off &&& 0xF) > 0xF, do: @h, else: 0) |||
        if((sp &&& 0xFF) + off > 0xFF, do: @c, else: 0)

    {sum, f}
  end

  # Conditions: 0 NZ, 1 Z, 2 NC, 3 C
  defp cond_met?(gb, 0), do: (gb.f &&& @z) == 0
  defp cond_met?(gb, 1), do: (gb.f &&& @z) != 0
  defp cond_met?(gb, 2), do: (gb.f &&& @c) == 0
  defp cond_met?(gb, 3), do: (gb.f &&& @c) != 0
end
