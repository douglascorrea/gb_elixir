defmodule GbEmu.Machine do
  @moduledoc """
  Ties CPU, PPU and timers together and runs the machine one video frame
  (70224 T-cycles) at a time.
  """

  alias GbEmu.{CPU, GB, PPU, Timer}
  alias GbEmu.Debugger.Trace

  @cycles_per_frame 70_224
  @screen_bytes 160 * 144

  @spec new(binary(), binary(), keyword()) :: GB.t()
  def new(boot, rom, opts \\ []), do: GB.new(boot, rom, opts)

  @doc "Advances the CPU and peripherals by one instruction boundary."
  @spec step_instruction(GB.t()) :: {GB.t(), pos_integer()}
  def step_instruction(%{debug_trace?: true} = gb) do
    Trace.record(gb, %{
      type: :stage,
      component: :machine,
      source_location: {:machine, "def step_instruction(%{debug_trace?: true} = gb) do"}
    })

    Trace.record(gb, %{
      type: :stage,
      component: :cpu,
      source_location: {:cpu, "def step(gb) do"}
    })

    {gb, cycles} = CPU.step(gb)

    Trace.record(gb, %{
      type: :stage,
      component: :ppu,
      cycles: cycles,
      source_location: {:ppu, "def step(%{debug_trace?: true} = gb, cycles) do"}
    })

    gb = PPU.step(gb, cycles)

    Trace.record(gb, %{
      type: :stage,
      component: :timer,
      cycles: cycles,
      source_location: {:timer, "def step(gb, cycles) do"}
    })

    gb = Timer.step(gb, cycles)

    serial_selector =
      if is_nil(gb.serial_cycles) do
        "defp step_serial(%{serial_cycles: nil} = gb, _cycles), do: gb"
      else
        "defp step_serial(gb, cycles) do"
      end

    Trace.record(gb, %{
      type: :stage,
      component: :serial,
      cycles: cycles,
      source_location: {:machine, serial_selector}
    })

    gb = step_serial(gb, cycles)
    {gb, cycles}
  end

  def step_instruction(gb) do
    {gb, cycles} = CPU.step(gb)
    gb = PPU.step(gb, cycles)
    gb = Timer.step(gb, cycles)
    gb = step_serial(gb, cycles)
    {gb, cycles}
  end

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
    {gb, cycles} = step_instruction(gb)
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

    {field, bit} = button_location(button)

    current = Map.fetch!(gb, field)

    if down do
      gb = Map.put(gb, field, current ||| bit)
      %{gb | if_: gb.if_ ||| 0x10}
    else
      Map.put(gb, field, current &&& bnot(bit))
    end
  end

  defp button_location(button) do
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
  end

  @doc "Release every button (used when the browser loses focus)."
  def release_all_buttons(gb) do
    %{gb | dpad: 0x00, btns: 0x00}
  end
end
