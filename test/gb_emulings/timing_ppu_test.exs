defmodule GBEmulings.TimingPPUTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias GbEmu.{BootRom, Bus, Machine, PPU, Timer}
  alias GbEmu.Debugger.Trace

  test "advances DIV and decodes every TAC frequency" do
    gb = machine()
    assert Timer.step(gb, 0x123).div_counter == gb.div_counter + 0x123

    for {selector, period} <- [{0, 1024}, {1, 16}, {2, 64}, {3, 256}] do
      gb = %{machine() | tac: 0x04 ||| selector, tima: 0, tima_acc: 0}
      assert Timer.step(gb, period - 1).tima == 0
      assert Timer.step(gb, period).tima == 1
    end
  end

  test "reloads TIMA from TMA and requests an interrupt on overflow" do
    gb = %{machine() | tac: 0x05, tima: 0xFF, tma: 0x67, tima_acc: 0, if_: 0}
    gb = Timer.step(gb, 16)

    assert gb.tima == 0x67
    assert (gb.if_ &&& 0x04) == 0x04
  end

  test "keeps idle serial state and completes an internal-clock transfer" do
    {idle, 4} = machine() |> Machine.step_instruction()
    assert idle.serial_cycles == nil

    active = %{machine() | serial_cycles: 4, if_: 0}
    :atomics.put(active.io_misc, 0x01 + 1, 0x42)
    :atomics.put(active.io_misc, 0x02 + 1, 0x81)

    {active, 4} = Machine.step_instruction(active)
    assert active.serial_cycles == nil
    assert active.serial_out == [0x42]
    assert (active.if_ &&& 0x08) == 0x08
  end

  test "maps buttons into the joypad matrix and requests its interrupt" do
    gb = machine() |> Bus.write8(0xFF00, 0x10)
    gb = Machine.set_button(gb, :a, true)

    assert gb.btns == 0x01
    assert (Bus.read8(gb, 0xFF00) &&& 0x01) == 0
    assert (gb.if_ &&& 0x10) == 0x10

    gb = Machine.set_button(gb, :left, true)
    assert gb.dpad == 0x02
  end

  test "projects PPU transition state into debugger events" do
    gb = %{machine() | debug_trace?: true, lcdc: 0x91, ppu_mode: 2, ppu_dot: 79}

    {_gb, events} = Trace.capture(fn -> PPU.step(gb, 1) end)
    event = Enum.find(events, &(&1.type == :ppu_event))

    assert event.before.ppu_mode == 2
    assert event.after.ppu_mode == 3
    assert event.after.ppu_dot == 80
  end

  test "turns the LCD off and advances mode, LY, LYC, and STAT state" do
    gb = %{machine() | lcdc: 0x91, ppu_mode: 3, ppu_dot: 200, ly: 12, window_line: 4}
    off = Bus.write8(gb, 0xFF40, 0)

    assert {off.ppu_mode, off.ppu_dot, off.ly, off.window_line} == {0, 0, 0, 0}

    gb = %{machine() | lcdc: 0x91, ppu_mode: 0, ppu_dot: 455, ly: 0, lyc: 1, stat: 0x40, if_: 0}
    gb = PPU.step(gb, 1)

    assert gb.ly == 1
    assert gb.ppu_mode == 2
    assert (gb.stat &&& 0x04) == 0x04
    assert (gb.if_ &&& 0x02) == 0x02
  end

  test "reads tile rows, applies palettes, and renders a background line" do
    gb = render_state(0x91)
    gb = gb |> Bus.write8(0x9800, 0) |> Bus.write8(0x8000, 0x80) |> Bus.write8(0x8001, 0)
    gb = render_line(gb)
    line = Map.fetch!(gb.fb_lines, 0)

    assert byte_size(line) == 160
    assert :binary.at(line, 0) == 1
    assert :binary.at(line, 1) == 0
  end

  test "supports signed tile addressing" do
    gb = render_state(0x81)
    gb = gb |> Bus.write8(0x9800, 0xFF) |> Bus.write8(0x8FF0, 0x80) |> Bus.write8(0x8FF1, 0)
    line = gb |> render_line() |> Map.fetch!(:fb_lines) |> Map.fetch!(0)

    assert :binary.at(line, 0) == 1
  end

  test "renders the window and advances its private line counter" do
    gb = %{render_state(0xF1) | wy: 0, wx: 7}

    gb =
      gb
      |> Bus.write8(0x9C00, 1)
      |> Bus.write8(0x8010, 0x80)
      |> Bus.write8(0x8011, 0)
      |> render_line()

    assert gb.window_line == 1
    assert gb.fb_lines |> Map.fetch!(0) |> :binary.at(0) == 1
  end

  test "selects visible sprites, renders pixels, and honors background priority" do
    gb = render_state(0x93)

    front =
      gb
      |> put_sprite(0x00)
      |> Bus.write8(0x8010, 0x80)
      |> Bus.write8(0x8011, 0)
      |> render_line()

    assert front.fb_lines |> Map.fetch!(0) |> :binary.at(0) == 1

    behind =
      gb
      |> Bus.write8(0x9800, 0)
      |> Bus.write8(0x8000, 0x80)
      |> Bus.write8(0x8001, 0)
      |> put_sprite(0x80)
      |> Bus.write8(0x8010, 0)
      |> Bus.write8(0x8011, 0x80)
      |> render_line()

    assert behind.fb_lines |> Map.fetch!(0) |> :binary.at(0) == 1
  end

  test "finishes a 160 by 144 frame at VBlank" do
    gb = %{
      machine()
      | lcdc: 0x91,
        ppu_mode: 0,
        ppu_dot: 455,
        ly: 143,
        fb_lines: %{0 => :binary.copy(<<1>>, 160)},
        frame_count: 0
    }

    gb = PPU.step(gb, 1)

    assert gb.ppu_mode == 1
    assert gb.ly == 144
    assert gb.frame_count == 1
    assert byte_size(gb.frame) == 160 * 144
    assert :binary.at(gb.frame, 0) == 1
  end

  defp render_state(lcdc) do
    %{machine() | lcdc: lcdc, bgp: 0xE4, obp0: 0xE4, ppu_mode: 3, ppu_dot: 251, ly: 0}
  end

  defp render_line(gb), do: PPU.step(gb, 1)

  defp put_sprite(gb, attributes) do
    gb
    |> Bus.write8(0xFE00, 16)
    |> Bus.write8(0xFE01, 8)
    |> Bus.write8(0xFE02, 1)
    |> Bus.write8(0xFE03, attributes)
  end

  defp machine do
    rom =
      :binary.copy(<<0>>, 0x8000)
      |> put_byte(0x0100, 0x00)
      |> put_byte(0x0147, 0x00)

    Machine.new(BootRom.minimal(), rom)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end
end
