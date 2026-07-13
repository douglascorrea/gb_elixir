defmodule GBEmulings.CPUTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias GbEmu.{BootRom, Bus, CPU, Machine}

  test "fetches and executes an opcode" do
    {gb, cycles} = [0x00] |> machine() |> CPU.step()
    assert gb.pc == 0x0101
    assert cycles == 4
  end

  test "fetches immediate bytes and words" do
    {gb, 8} = [0x06, 0xAB] |> machine() |> CPU.step()
    assert gb.b == 0xAB
    assert gb.pc == 0x0102

    {gb, 12} = [0x21, 0x34, 0x12] |> machine() |> CPU.step()
    assert {gb.h, gb.l, gb.pc} == {0x12, 0x34, 0x0103}
  end

  test "implements 16-bit and indirect loads" do
    {gb, 12} = [0x01, 0x00, 0xC0] |> machine() |> CPU.step()
    assert {gb.b, gb.c} == {0xC0, 0x00}

    gb = machine([0x02], %{a: 0x42, b: 0xC0, c: 0x00})
    {gb, 8} = CPU.step(gb)
    assert Bus.read8(gb, 0xC000) == 0x42
  end

  test "implements HL auto-increment and register-indexed loads" do
    gb = machine([0x22, 0x47], %{a: 0x77, h: 0xC0, l: 0x00})
    {gb, 8} = CPU.step(gb)
    assert Bus.read8(gb, 0xC000) == 0x77
    assert {gb.h, gb.l} == {0xC0, 0x01}

    {gb, 4} = CPU.step(gb)
    assert gb.b == 0x77
  end

  test "implements immediate and high-memory loads" do
    {gb, 8} = [0x0E, 0x5A] |> machine() |> CPU.step()
    assert gb.c == 0x5A

    gb = machine([0xE0, 0x80], %{a: 0x66})
    {gb, 12} = CPU.step(gb)
    assert Bus.read8(gb, 0xFF80) == 0x66
  end

  test "implements INC and DEC with flags" do
    gb = machine([0x04, 0x05], %{b: 0x0F, f: 0x10})
    {gb, 4} = CPU.step(gb)
    assert gb.b == 0x10
    assert (gb.f &&& 0x30) == 0x30

    {gb, 4} = CPU.step(gb)
    assert gb.b == 0x0F
    assert (gb.f &&& 0x60) == 0x60
  end

  test "implements ADD, ADC, SUB, and SBC" do
    {gb, 8} = [0xC6, 1] |> machine(%{a: 0xFF}) |> CPU.step()
    assert gb.a == 0
    assert (gb.f &&& 0xB0) == 0xB0

    {gb, 8} = [0xCE, 0] |> machine(%{a: 0, f: 0x10}) |> CPU.step()
    assert gb.a == 1

    {gb, 8} = [0xD6, 1] |> machine(%{a: 0}) |> CPU.step()
    assert gb.a == 0xFF
    assert (gb.f &&& 0x50) == 0x50

    {gb, 8} = [0xDE, 0] |> machine(%{a: 1, f: 0x10}) |> CPU.step()
    assert gb.a == 0
  end

  test "implements logical operations and compare" do
    {and_gb, 8} = [0xE6, 0x0F] |> machine(%{a: 0xF0}) |> CPU.step()
    assert {and_gb.a, and_gb.f} == {0, 0xA0}

    {xor_gb, 8} = [0xEE, 0xFF] |> machine(%{a: 0x0F}) |> CPU.step()
    assert xor_gb.a == 0xF0

    {or_gb, 8} = [0xF6, 0xF0] |> machine(%{a: 0x0F}) |> CPU.step()
    assert or_gb.a == 0xFF

    {cp_gb, 8} = [0xFE, 0x20] |> machine(%{a: 0x20}) |> CPU.step()
    assert cp_gb.a == 0x20
    assert (cp_gb.f &&& 0xC0) == 0xC0
  end

  test "implements decimal adjust and complement" do
    gb = machine([0xC6, 0x01, 0x27], %{a: 0x09})
    {gb, 8} = CPU.step(gb)
    {gb, 4} = CPU.step(gb)
    assert gb.a == 0x10

    {gb, 4} = [0x2F] |> machine(%{a: 0x55}) |> CPU.step()
    assert gb.a == 0xAA
  end

  test "implements relative and absolute control flow" do
    {gb, 12} = [0x18, 0x02] |> machine() |> CPU.step()
    assert gb.pc == 0x0104

    {gb, 16} = [0xC3, 0x34, 0x12] |> machine() |> CPU.step()
    assert gb.pc == 0x1234
  end

  test "implements calls, returns, pushes, pops, and POP AF masking" do
    gb = machine([0xCD, 0x34, 0x12], %{sp: 0xC100})
    {gb, 24} = CPU.step(gb)
    assert gb.pc == 0x1234
    assert Bus.read16(gb, 0xC0FE) == 0x0103

    gb = gb |> Map.put(:pc, 0x0100) |> put_program([0xC9])
    {gb, 16} = CPU.step(gb)
    assert gb.pc == 0x0103

    gb = machine([0xC5, 0xD1], %{b: 0x12, c: 0x34, sp: 0xC100})
    {gb, 16} = CPU.step(gb)
    {gb, 12} = CPU.step(gb)
    assert {gb.d, gb.e, gb.sp} == {0x12, 0x34, 0xC100}

    gb = machine([0xF1], %{sp: 0xC000})
    gb = gb |> Bus.write8(0xC000, 0xFF) |> Bus.write8(0xC001, 0xAB)
    {gb, 12} = CPU.step(gb)
    assert {gb.a, gb.f} == {0xAB, 0xF0}
  end

  test "implements signed SP arithmetic and accumulator rotates" do
    {gb, 16} = [0xE8, 0x08] |> machine(%{sp: 0xFFF8}) |> CPU.step()
    assert gb.sp == 0
    assert (gb.f &&& 0x30) == 0x30

    {gb, 4} = [0x07] |> machine(%{a: 0x81}) |> CPU.step()
    assert {gb.a, gb.f} == {0x03, 0x10}
  end

  test "dispatches CB rotates, BIT, RES, and SET" do
    gb = machine([0xCB, 0x00, 0xCB, 0x40, 0xCB, 0x80, 0xCB, 0xC0], %{b: 0x81})

    {gb, 8} = CPU.step(gb)
    assert gb.b == 0x03
    assert (gb.f &&& 0x10) == 0x10

    {gb, 8} = CPU.step(gb)
    assert (gb.f &&& 0xA0) == 0x20

    {gb, 8} = CPU.step(gb)
    assert gb.b == 0x02

    {gb, 8} = CPU.step(gb)
    assert gb.b == 0x03
  end

  test "classifies and services interrupts" do
    gb = machine() |> Map.merge(%{ime: true, ie: 0x01, if_: 0x01, pc: 0x1234, sp: 0xC100})
    assert CPU.boundary(gb).interrupt == :vblank

    {gb, 20} = CPU.step(gb)
    assert gb.pc == 0x0040
    assert gb.sp == 0xC0FE
    assert Bus.read16(gb, 0xC0FE) == 0x1234
    refute gb.ime
  end

  test "delays EI by one instruction and implements HALT" do
    gb = machine([0xFB, 0x00])
    {gb, 4} = CPU.step(gb)
    refute gb.ime
    assert gb.ime_pending

    {gb, 4} = CPU.step(gb)
    assert gb.ime
    refute gb.ime_pending

    {gb, 4} = [0x76] |> machine() |> CPU.step()
    assert gb.halted
  end

  defp machine(program, attrs) when is_list(program) do
    gb = Machine.new(BootRom.minimal(), test_rom(program))
    struct!(gb, attrs)
  end

  defp machine(), do: machine([], %{})
  defp machine(program) when is_list(program), do: machine(program, %{})

  defp put_program(gb, program) do
    %{gb | rom: put_bytes(gb.rom, 0x0100, program)}
  end

  defp test_rom(program) do
    :binary.copy(<<0>>, 0x8000)
    |> put_bytes(0x0100, program)
    |> put_byte(0x0147, 0x00)
  end

  defp put_bytes(binary, offset, values) do
    Enum.with_index(values, offset)
    |> Enum.reduce(binary, fn {value, index}, acc -> put_byte(acc, index, value) end)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end
end
