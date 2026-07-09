defmodule GbEmu.MachineTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias GbEmu.{BootRom, Machine}

  defp test_rom do
    rom = :binary.copy(<<0>>, 0x8000)

    rom
    |> put_byte(0x100, 0xC3)
    |> put_byte(0x101, 0x00)
    |> put_byte(0x102, 0x01)
    |> put_byte(0x147, 0x00)
  end

  defp new_machine, do: Machine.new(BootRom.minimal(), test_rom())

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end

  test "minimal open boot ROM hands off to the cartridge" do
    gb = new_machine()

    assert byte_size(BootRom.minimal()) == 0x100
    # Open stub skips the real BIOS and starts already handed off.
    refute gb.boot_enabled
    assert gb.pc == 0x100
    assert gb.lcdc == 0x91

    {gb, frame} = Machine.run_frame(gb)

    refute gb.boot_enabled
    assert byte_size(frame) == 160 * 144
  end

  test "fast open boot preserves the existing post-boot start" do
    gb = Machine.new(BootRom.minimal(), test_rom())

    assert gb.pc == 0x0100
    refute gb.boot_enabled
    assert gb.boot_kind == :minimal
    assert gb.boot_mode == :fast
    refute gb.debug_trace?
  end

  test "file boot records its source without taking the open-boot fast path" do
    gb = Machine.new(:binary.copy(<<0>>, 0x100), test_rom())

    assert gb.pc == 0x0000
    assert gb.boot_enabled
    assert gb.boot_kind == :file
    assert gb.boot_mode == :fast
    refute gb.debug_trace?
  end

  test "joypad input updates button state and requests the joypad interrupt" do
    gb = new_machine()

    gb = Machine.set_button(gb, :start, true)

    assert gb.btns == 0x08
    assert (gb.if_ &&& 0x10) == 0x10

    gb = Machine.set_button(gb, :start, false)
    assert gb.btns == 0x00

    gb = Machine.set_button(gb, :a, true)
    gb = Machine.release_all_buttons(gb)
    assert gb.btns == 0x00
    assert gb.dpad == 0x00
  end
end
