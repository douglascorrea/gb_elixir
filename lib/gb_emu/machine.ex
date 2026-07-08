defmodule GbEmu.Machine do
  @moduledoc """
  Ties CPU, PPU and timers together and runs the machine one video frame
  (70224 T-cycles) at a time.
  """

  alias GbEmu.{CPU, GB, PPU, Timer}

  @cycles_per_frame 70_224
  @screen_bytes 160 * 144

  def new(boot, rom), do: GB.new(boot, rom)

  @doc """
  Runs one frame worth of cycles. Returns `{gb, frame_binary}` where the
  frame is 160*144 bytes of 2-bit shades (0 = lightest, 3 = darkest).
  """
  def run_frame(gb) do
    gb = run_cycles(gb, @cycles_per_frame)
    {gb, gb.frame || :binary.copy(<<0>>, @screen_bytes)}
  end

  defp run_cycles(gb, budget) when budget <= 0, do: gb

  defp run_cycles(gb, budget) do
    {gb, cycles} = CPU.step(gb)
    gb = PPU.step(gb, cycles)
    gb = Timer.step(gb, cycles)
    gb = step_serial(gb, cycles)
    run_cycles(gb, budget - cycles)
  end

  # Complete an internal-clock serial transfer after ~4096 T-cycles.
  # External-clock transfers (SC bit0 = 0) never complete without a partner.
  defp step_serial(%{serial_cycles: nil} = gb, _cycles), do: gb

  defp step_serial(gb, cycles) do
    import Bitwise
    left = gb.serial_cycles - cycles

    if left <= 0 do
      byte = :atomics.get(gb.io_misc, 0x01 + 1)
      sc = :atomics.get(gb.io_misc, 0x02 + 1)
      :atomics.put(gb.io_misc, 0x01 + 1, 0xFF)
      :atomics.put(gb.io_misc, 0x02 + 1, sc &&& 0x7F)

      %{gb | serial_cycles: nil, serial_out: [byte | gb.serial_out], if_: gb.if_ ||| 0x08}
    else
      %{gb | serial_cycles: left}
    end
  end

  @doc "Press or release a button. Requests the joypad interrupt on press."
  def set_button(gb, button, down) do
    import Bitwise

    {field, bit} =
      case button do
        :right -> {:dpad, 0x01}
        :left -> {:dpad, 0x02}
        :up -> {:dpad, 0x04}
        :down -> {:dpad, 0x08}
        :a -> {:btns, 0x01}
        :b -> {:btns, 0x02}
        :select -> {:btns, 0x04}
        :start -> {:btns, 0x08}
      end

    current = Map.fetch!(gb, field)

    if down do
      gb = Map.put(gb, field, current ||| bit)
      %{gb | if_: gb.if_ ||| 0x10}
    else
      Map.put(gb, field, current &&& bnot(bit))
    end
  end

  @doc "Release every button (used when the browser loses focus)."
  def release_all_buttons(gb) do
    %{gb | dpad: 0x00, btns: 0x00}
  end
end
