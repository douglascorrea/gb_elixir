defmodule GbEmu.Emulator do
  @moduledoc """
  Runs a Game Boy machine in real time (~59.7 fps) and streams frames to a
  subscriber process as `{:gb_frame, binary, fps}` messages.
  """

  use GenServer

  alias GbEmu.{BootRom, Debugger, Machine}
  alias GbEmu.Debugger.Snapshot

  # 70224 T-cycles at 4.194304 MHz
  @frame_interval_us 16_742
  @debug_history_limit 200
  @debug_call_timeout 5_000
  @debug_runner_timeout 15_000
  @debug_frame_timeout 30_000
  @debug_reply_grace 1_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def button(pid, btn, down), do: GenServer.cast(pid, {:button, btn, down})
  def release_all_buttons(pid), do: GenServer.cast(pid, :release_all_buttons)

  def load_rom(pid, rom_path, boot_rom_path \\ nil) do
    GenServer.cast(pid, {:load_rom, rom_path, boot_rom_path})
  end

  def set_paused(pid, paused), do: GenServer.cast(pid, {:pause, paused})

  @doc "Pauses the authoritative machine and returns its first debugger snapshot."
  def debug_attach(pid, memory_start \\ 0x0000)

  def debug_attach(pid, memory_start) when is_integer(memory_start) do
    debug_call(pid, {:debug_attach, memory_start}, @debug_call_timeout)
  end

  def debug_attach(_pid, _memory_start), do: {:error, :invalid_memory_start}

  @doc "Runs a debugger command against the attached authoritative machine."
  def debug_command(pid, command, memory_start \\ 0x0000)

  def debug_command(pid, command, memory_start) when is_integer(memory_start) do
    debug_call(pid, {:debug_command, command, memory_start}, command_timeout(command))
  end

  def debug_command(_pid, _command, _memory_start), do: {:error, :invalid_memory_start}

  @doc "Returns another memory window without advancing the machine."
  def debug_memory(pid, memory_start) when is_integer(memory_start) do
    debug_call(pid, {:debug_memory, memory_start}, @debug_call_timeout)
  end

  def debug_memory(_pid, _memory_start), do: {:error, :invalid_memory_start}

  @doc "Detaches the debugger and resumes the paced frame loop."
  def debug_resume(pid), do: debug_call(pid, :debug_resume, @debug_call_timeout)

  @impl true
  def init(opts) do
    subscriber = Keyword.fetch!(opts, :subscriber)
    rom_path = Keyword.fetch!(opts, :rom_path)
    boot_rom_path = Keyword.get(opts, :boot_rom_path)

    state = %{
      subscriber: subscriber,
      gb: new_machine(rom_path, boot_rom_path),
      rom_path: rom_path,
      boot_rom_path: boot_rom_path,
      paused: false,
      debug_attached: false,
      debug_history: [],
      debug_history_truncated?: false,
      next_frame_at: System.monotonic_time(:microsecond),
      tick_timer: nil,
      tick_token: nil,
      fps_window_start: System.monotonic_time(:millisecond),
      fps_frames: 0,
      fps: 0.0
    }

    {:ok, schedule_tick(state, 0)}
  end

  @impl true
  def handle_info({:tick, token}, %{tick_token: token, paused: true} = state) do
    {:noreply, clear_tick(state)}
  end

  def handle_info({:tick, token}, %{tick_token: token} = state) do
    state = clear_tick(state)
    {gb, frame} = Machine.run_frame(state.gb)

    state = update_fps(state)
    maybe_log_state(state, gb)
    send(state.subscriber, {:gb_frame, frame, state.fps})

    now = System.monotonic_time(:microsecond)
    next_at = max(state.next_frame_at + @frame_interval_us, now - 5 * @frame_interval_us)
    delay_ms = max(div(next_at - now, 1000), 0)

    state = %{state | gb: gb, next_frame_at: next_at}
    {:noreply, schedule_tick(state, delay_ms)}
  end

  def handle_info({:tick, _stale_token}, state), do: {:noreply, state}

  defp maybe_log_state(state, gb) do
    if Application.get_env(:gb_emu, :debug_input, false) and rem(gb.frame_count, 60) == 0 do
      require Logger

      # FFE1 / FF80 / FF81 live in HRAM (not IO)
      e1 = :atomics.get(gb.hram, 0xFFE1 - 0xFF80 + 1)
      keys = :atomics.get(gb.hram, 0xFF80 - 0xFF80 + 1)
      newk = :atomics.get(gb.hram, 0xFF81 - 0xFF80 + 1)
      sc = :atomics.get(gb.io_misc, 0x02 + 1)

      Logger.info(
        "frame=#{gb.frame_count} pc=#{Integer.to_string(gb.pc, 16)} lcdc=#{Integer.to_string(gb.lcdc, 16)} " <>
          "E1=#{Integer.to_string(e1, 16)} keys=#{Integer.to_string(keys, 16)} new=#{Integer.to_string(newk, 16)} " <>
          "btns=#{gb.btns} sc=#{Integer.to_string(sc, 16)} " <>
          "serial_cycles=#{inspect(gb.serial_cycles)} fps=#{state.fps}"
      )
    end
  end

  @impl true
  def handle_cast({:button, btn, down}, state) do
    if Application.get_env(:gb_emu, :debug_input, false) do
      require Logger

      Logger.info(
        "joypad #{btn} #{if down, do: "DOWN", else: "UP"} btns=#{state.gb.btns} dpad=#{state.gb.dpad}"
      )
    end

    {:noreply, %{state | gb: Machine.set_button(state.gb, btn, down)}}
  end

  def handle_cast(:release_all_buttons, state) do
    {:noreply, %{state | gb: Machine.release_all_buttons(state.gb)}}
  end

  def handle_cast({:load_rom, rom_path, boot_rom_path}, state) do
    state =
      %{
        state
        | gb: new_machine(rom_path, boot_rom_path),
          rom_path: rom_path,
          boot_rom_path: boot_rom_path,
          paused: false,
          debug_attached: false,
          debug_history: [],
          debug_history_truncated?: false,
          next_frame_at: System.monotonic_time(:microsecond)
      }

    {:noreply, schedule_tick(state, 0)}
  end

  def handle_cast({:pause, false}, %{debug_attached: true} = state) do
    {:noreply, state}
  end

  def handle_cast({:pause, false}, %{paused: false} = state) do
    {:noreply, state}
  end

  def handle_cast({:pause, true}, state) do
    {:noreply, state |> Map.put(:paused, true) |> cancel_tick()}
  end

  def handle_cast({:pause, false}, state) do
    state = %{state | paused: false, next_frame_at: System.monotonic_time(:microsecond)}
    {:noreply, schedule_tick(state, 0)}
  end

  @impl true
  def handle_call({:debug_attach, memory_start, deadline}, _from, state)
      when is_integer(memory_start) do
    if deadline_expired?(deadline) do
      {:reply, {:error, :timeout}, state}
    else
      state =
        state
        |> cancel_tick()
        |> Map.merge(%{paused: true, debug_attached: true})

      {:reply, {:ok, debug_result(state, [], memory_start, :attach)}, state}
    end
  end

  def handle_call({:debug_attach, _memory_start, _deadline}, _from, state) do
    {:reply, {:error, :invalid_memory_start}, state}
  end

  def handle_call(
        {:debug_command, _command, _memory_start, _deadline},
        _from,
        %{debug_attached: false} = state
      ) do
    {:reply, {:error, :not_attached}, state}
  end

  def handle_call({:debug_command, :restart, memory_start, deadline}, _from, state)
      when is_integer(memory_start) do
    cond do
      deadline_expired?(deadline) ->
        {:reply, {:error, :timeout}, state}

      true ->
        case restart_machine(state) do
          {:ok, gb} ->
            if deadline_expired?(deadline) do
              {:reply, {:error, :timeout}, state}
            else
              state = %{
                state
                | gb: gb,
                  paused: true,
                  debug_history: [],
                  debug_history_truncated?: false
              }

              {:reply, {:ok, debug_result(state, [], memory_start, :restart)}, state}
            end

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:debug_command, command, memory_start, deadline}, _from, state)
      when is_integer(memory_start) do
    if deadline_expired?(deadline) do
      {:reply, {:error, :timeout}, state}
    else
      case Debugger.run(state.gb, command, deadline) do
        {:ok, gb, traces, command_snapshot} ->
          {state, traces} = retain_debug_result(state, gb, traces, command_snapshot)

          if deadline_expired?(deadline) do
            {:reply, {:error, :timeout}, state}
          else
            result = debug_result(state, traces, memory_start, command, command_snapshot)
            {:reply, {:ok, result}, state}
          end

        {:error, reason, gb, traces, command_snapshot} ->
          {state, _traces} = retain_debug_result(state, gb, traces, command_snapshot)
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:debug_command, _command, _memory_start, _deadline}, _from, state) do
    {:reply, {:error, :invalid_memory_start}, state}
  end

  def handle_call(
        {:debug_memory, _memory_start, _deadline},
        _from,
        %{debug_attached: false} = state
      ) do
    {:reply, {:error, :not_attached}, state}
  end

  def handle_call({:debug_memory, memory_start, deadline}, _from, state)
      when is_integer(memory_start) do
    if deadline_expired?(deadline) do
      {:reply, {:error, :timeout}, state}
    else
      {:reply, {:ok, debug_result(state, [], memory_start, :memory)}, state}
    end
  end

  def handle_call({:debug_memory, _memory_start, _deadline}, _from, state) do
    {:reply, {:error, :invalid_memory_start}, state}
  end

  def handle_call({:debug_resume, _deadline}, _from, %{debug_attached: false} = state) do
    {:reply, {:error, :not_attached}, state}
  end

  def handle_call({:debug_resume, deadline}, _from, state) do
    if deadline_expired?(deadline) do
      {:reply, {:error, :timeout}, state}
    else
      state =
        state
        |> Map.merge(%{
          paused: false,
          debug_attached: false,
          next_frame_at: System.monotonic_time(:microsecond)
        })
        |> schedule_tick(0)

      {:reply, :ok, state}
    end
  end

  defp new_machine(rom_path, boot_rom_path, opts \\ []) do
    boot = BootRom.load!(boot_rom_path)
    rom = File.read!(rom_path)
    Machine.new(boot, rom, opts)
  end

  defp restart_machine(state) do
    {:ok, new_machine(state.rom_path, state.boot_rom_path, boot_mode: :cold)}
  rescue
    _error in [File.Error, ArgumentError, RuntimeError] -> {:error, :restart_failed}
  end

  defp retain_debug_result(state, gb, _traces, command_snapshot) do
    projected_traces = command_snapshot.history

    history_truncated? =
      state.debug_history_truncated? or
        length(state.debug_history) + length(projected_traces) > @debug_history_limit or
        get_in(command_snapshot, [:command, :history_truncated?]) == true

    history = (state.debug_history ++ projected_traces) |> Enum.take(-@debug_history_limit)

    {%{
       state
       | gb: gb,
         debug_history: history,
         debug_history_truncated?: history_truncated?
     }, projected_traces}
  end

  defp debug_result(
         state,
         traces,
         memory_start,
         command,
         command_snapshot \\ nil
       ) do
    snapshot =
      state.gb
      |> Snapshot.build(
        memory_start: memory_start,
        newest_trace: List.last(state.debug_history),
        history: state.debug_history
      )
      |> expose_debug_mode()
      |> maybe_put_command(command_snapshot)

    %{
      snapshot: snapshot,
      traces: traces,
      meta: %{
        mode: :debugging,
        command: command,
        total_steps: command_total_steps(command_snapshot),
        history_size: length(state.debug_history),
        history_limit: @debug_history_limit,
        history_truncated?: state.debug_history_truncated?
      }
    }
  end

  defp expose_debug_mode(snapshot) do
    snapshot
    |> Map.put(:mode, :debugging)
    |> put_in([:cpu, :pc], snapshot.cpu.registers.pc)
    |> put_in([:boot, :enabled], snapshot.boot.overlay_enabled?)
  end

  defp maybe_put_command(snapshot, %{command: command}), do: Map.put(snapshot, :command, command)
  defp maybe_put_command(snapshot, _command_snapshot), do: snapshot

  defp command_total_steps(%{command: %{total_steps: total_steps}}), do: total_steps
  defp command_total_steps(_command_snapshot), do: 0

  defp command_timeout(:frame), do: @debug_frame_timeout

  defp command_timeout({:steps, steps}) when is_integer(steps) and steps > 10,
    do: @debug_runner_timeout

  defp command_timeout(command) when command in [:ppu_event, :scanline], do: @debug_runner_timeout
  defp command_timeout(_command), do: @debug_call_timeout

  defp debug_call(pid, request, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout - @debug_reply_grace
    GenServer.call(pid, put_deadline(request, deadline), timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :timeout}
    :exit, _reason -> {:error, :emulator_unavailable}
  end

  defp put_deadline({:debug_attach, memory_start}, deadline) do
    {:debug_attach, memory_start, deadline}
  end

  defp put_deadline({:debug_command, command, memory_start}, deadline) do
    {:debug_command, command, memory_start, deadline}
  end

  defp put_deadline({:debug_memory, memory_start}, deadline) do
    {:debug_memory, memory_start, deadline}
  end

  defp put_deadline(:debug_resume, deadline), do: {:debug_resume, deadline}

  defp deadline_expired?(deadline) when is_integer(deadline) do
    System.monotonic_time(:millisecond) >= deadline
  end

  defp schedule_tick(state, delay_ms) do
    state = cancel_tick(state)
    token = make_ref()
    timer = Process.send_after(self(), {:tick, token}, delay_ms)
    %{state | tick_timer: timer, tick_token: token}
  end

  defp cancel_tick(%{tick_timer: timer} = state) when is_reference(timer) do
    Process.cancel_timer(timer)
    clear_tick(state)
  end

  defp cancel_tick(state), do: clear_tick(state)
  defp clear_tick(state), do: %{state | tick_timer: nil, tick_token: nil}

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
