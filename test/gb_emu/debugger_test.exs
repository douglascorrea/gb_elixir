defmodule GbEmu.DebuggerTest do
  use ExUnit.Case, async: true

  alias GbEmu.{BootRom, Machine}

  defp test_rom do
    rom = :binary.copy(<<0>>, 0x8000)

    rom
    |> put_byte(0x100, 0xC3)
    |> put_byte(0x101, 0x00)
    |> put_byte(0x102, 0x01)
    |> put_byte(0x147, 0x00)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end

  test "cold open boot executes three instructions and hands off at 0100" do
    gb = Machine.new(BootRom.minimal(), test_rom(), boot_mode: :cold)
    assert gb.pc == 0x0000
    assert gb.boot_enabled
    assert gb.boot_kind == :minimal
    assert gb.boot_mode == :cold
    refute gb.debug_trace?

    {gb, 16} = Machine.step_instruction(gb)
    assert gb.pc == 0x00FC
    {gb, 8} = Machine.step_instruction(gb)
    assert gb.pc == 0x00FE
    {gb, 12} = Machine.step_instruction(gb)

    assert gb.pc == 0x0100
    refute gb.boot_enabled
    assert gb.sp == 0xFFFE
    assert gb.lcdc == 0x91
  end
end
