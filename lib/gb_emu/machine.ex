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
    run_cycles(gb, budget - cycles)
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
end
