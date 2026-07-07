defmodule GbEmu.Emulator do
  @moduledoc """
  Runs a Game Boy machine in real time (~59.7 fps) and streams frames to a
  subscriber process as `{:gb_frame, binary, fps}` messages.
  """

  use GenServer

  alias GbEmu.{BootRom, Machine}

  # 70224 T-cycles at 4.194304 MHz
  @frame_interval_us 16_742

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def button(pid, btn, down), do: GenServer.cast(pid, {:button, btn, down})
  def load_rom(pid, rom_path), do: GenServer.cast(pid, {:load_rom, rom_path})
  def set_paused(pid, paused), do: GenServer.cast(pid, {:pause, paused})

  @impl true
  def init(opts) do
    subscriber = Keyword.fetch!(opts, :subscriber)
    rom_path = Keyword.fetch!(opts, :rom_path)

    state = %{
      subscriber: subscriber,
      gb: new_machine(rom_path),
      paused: false,
      next_frame_at: System.monotonic_time(:microsecond),
      fps_window_start: System.monotonic_time(:millisecond),
      fps_frames: 0,
      fps: 0.0
    }

    send(self(), :tick)
    {:ok, state}
  end

  @impl true
  def handle_info(:tick, %{paused: true} = state) do
    Process.send_after(self(), :tick, 100)
    {:noreply, %{state | next_frame_at: System.monotonic_time(:microsecond)}}
  end

  def handle_info(:tick, state) do
    {gb, frame} = Machine.run_frame(state.gb)

    state = update_fps(state)
    send(state.subscriber, {:gb_frame, frame, state.fps})

    now = System.monotonic_time(:microsecond)
    next_at = max(state.next_frame_at + @frame_interval_us, now - 5 * @frame_interval_us)
    delay_ms = max(div(next_at - now, 1000), 0)
    Process.send_after(self(), :tick, delay_ms)

    {:noreply, %{state | gb: gb, next_frame_at: next_at}}
  end

  @impl true
  def handle_cast({:button, btn, down}, state) do
    {:noreply, %{state | gb: Machine.set_button(state.gb, btn, down)}}
  end

  def handle_cast({:load_rom, rom_path}, state) do
    {:noreply, %{state | gb: new_machine(rom_path)}}
  end

  def handle_cast({:pause, paused}, state) do
    {:noreply, %{state | paused: paused}}
  end

  defp new_machine(rom_path) do
    boot = BootRom.load!()
    rom = File.read!(rom_path)
    Machine.new(boot, rom)
  end

  defp update_fps(state) do
    now = System.monotonic_time(:millisecond)
    frames = state.fps_frames + 1
    elapsed = now - state.fps_window_start

    if elapsed >= 1000 do
      %{
        state
        | fps: Float.round(frames * 1000 / elapsed, 1),
          fps_frames: 0,
          fps_window_start: now
      }
    else
      %{state | fps_frames: frames}
    end
  end
end
