defmodule GbEmu.Debugger do
  @moduledoc """
  Public debugger facade for traced instruction boundaries and bounded runners.
  """

  import Bitwise

  alias GbEmu.{CPU, GB, Machine}
  alias GbEmu.Debugger.{Disassembler, Snapshot, SourceMap, Trace}

  @limits %{ppu_event: 10_000, scanline: 10_000, frame: 100_000}
  @history_limit 200
  @fixed_step_limit 100_000

  @cpu_fields [:a, :f, :b, :c, :d, :e, :h, :l, :sp, :pc, :ime, :ime_pending, :halted]
  @ppu_fields [
    :lcdc,
    :stat,
    :scy,
    :scx,
    :ly,
    :lyc,
    :bgp,
    :obp0,
    :obp1,
    :wy,
    :wx,
    :ppu_dot,
    :ppu_mode,
    :window_line,
    :frame_count
  ]
  @timer_fields [:div_counter, :tima_acc, :tima, :tma, :tac]
  @cartridge_fields [:mbc, :rom_bank, :rom_bank_mask, :ram_bank, :ram_enabled, :mbc1_mode]
  @boot_fields [:boot_enabled, :boot_kind, :boot_mode]

  @doc "Executes and explains one instruction, interrupt, or idle-HALT boundary."
  @spec step(GB.t()) :: {GB.t(), map()}
  def step(gb) do
    boundary = CPU.boundary(gb)
    decoded = decoded_boundary(gb, boundary)
    before = trace_state(gb)

    {{traced_gb, cycles}, raw_events} =
      Trace.capture(fn ->
        Machine.step_instruction(%{gb | debug_trace?: true})
      end)

    result = %{traced_gb | debug_trace?: false}
    after_state = trace_state(result)
    events = Enum.map(raw_events, &resolve_event_source/1)
    trace = build_trace(boundary, decoded, before, after_state, cycles, events)

    {result, trace}
  end

  @doc "Runs a validated debugger command and returns bounded history plus a snapshot."
  @spec run(GB.t(), term()) ::
          {:ok, GB.t(), [map()], map()} | {:error, atom(), GB.t(), [map()], map()}
  def run(gb, :instruction) do
    {gb, trace} = step(gb)
    traces = [trace]
    {:ok, gb, traces, command_snapshot(gb, traces, :instruction, 1, nil)}
  end

  def run(gb, {:steps, steps})
      when is_integer(steps) and steps > 0 and steps <= @fixed_step_limit do
    {gb, newest_first} = run_steps(gb, steps, [])
    traces = Enum.reverse(newest_first)
    {:ok, gb, traces, command_snapshot(gb, traces, {:steps, steps}, steps, steps)}
  end

  def run(gb, {:steps, _steps}) do
    snapshot = command_snapshot(gb, [], :invalid_steps, 0, @fixed_step_limit)
    {:error, :invalid_steps, gb, [], snapshot}
  end

  def run(gb, command) when command in [:ppu_event, :scanline, :frame] do
    run_to_boundary(gb, command)
  end

  def run(gb, _command) do
    snapshot = command_snapshot(gb, [], :invalid_command, 0, nil)
    {:error, :invalid_command, gb, [], snapshot}
  end

  defp run_steps(gb, 0, traces), do: {gb, traces}

  defp run_steps(gb, remaining, traces) do
    {gb, trace} = step(gb)
    run_steps(gb, remaining - 1, retain(trace, traces))
  end

  defp run_to_boundary(gb, command) do
    limit = Map.fetch!(@limits, command)
    initial = boundary_value(gb, command)
    run_to_boundary(gb, command, initial, limit, 0, [])
  end

  defp run_to_boundary(gb, command, initial, limit, total_steps, traces) do
    {gb, trace} = step(gb)
    total_steps = total_steps + 1
    traces = retain(trace, traces)

    cond do
      boundary_value(gb, command) != initial ->
        traces = Enum.reverse(traces)
        {:ok, gb, traces, command_snapshot(gb, traces, command, total_steps, limit)}

      total_steps >= limit ->
        traces = Enum.reverse(traces)

        {:error, :step_limit, gb, traces,
         command_snapshot(gb, traces, command, total_steps, limit)}

      true ->
        run_to_boundary(gb, command, initial, limit, total_steps, traces)
    end
  end

  defp boundary_value(gb, :ppu_event), do: {gb.ppu_mode, gb.ly, gb.frame_count}
  defp boundary_value(gb, :scanline), do: {gb.ly, gb.frame_count}
  defp boundary_value(gb, :frame), do: gb.frame_count

  defp retain(trace, traces), do: [trace | traces] |> Enum.take(@history_limit)

  defp command_snapshot(gb, traces, command, total_steps, limit) do
    newest_trace = List.last(traces)

    gb
    |> Snapshot.build(newest_trace: newest_trace, history: traces)
    |> Map.put(:command, %{
      name: command,
      total_steps: total_steps,
      limit: limit,
      history_limit: @history_limit,
      history_truncated?: total_steps > @history_limit
    })
  end

  defp decoded_boundary(gb, %{kind: :instruction}), do: Disassembler.decode(gb)

  defp decoded_boundary(gb, %{kind: :interrupt, interrupt: interrupt, vector: vector}) do
    %{
      kind: :interrupt,
      pc: gb.pc,
      opcode: nil,
      bytes: [],
      length: 0,
      mnemonic: "INT #{interrupt_name(interrupt)} ($#{hex16(vector)})",
      operands: [vector],
      handler: {:cpu, "defp service_interrupt(gb, pending) do"}
    }
  end

  defp decoded_boundary(gb, %{kind: :halt}) do
    %{
      kind: :halt,
      pc: gb.pc,
      opcode: nil,
      bytes: [],
      length: 0,
      mnemonic: "HALT (idle)",
      operands: [],
      handler: {:cpu, "def step(gb) do"}
    }
  end

  defp build_trace(boundary, decoded, before, after_state, cycles, events) do
    memory = Enum.filter(events, &(&1.type == :memory))
    component_events = Enum.reject(events, &(&1.type == :memory))
    side_effects = memory_side_effects(memory)
    notable = boundary_events(boundary, before, after_state) ++ component_events ++ side_effects

    registers = delta_group(before.cpu, after_state.cpu)
    ppu = delta_group(before.ppu, after_state.ppu)
    timer = delta_group(before.timer, after_state.timer)
    interrupts = delta_group(before.interrupts, after_state.interrupts)
    serial = delta_group(before.serial, after_state.serial)
    cartridge = delta_group(before.cartridge, after_state.cartridge)
    boot = delta_group(before.boot, after_state.boot)

    sources =
      [decoded.handler | source_references(events)]
      |> Enum.map(&resolve_source/1)
      |> Enum.uniq_by(&{&1.path, &1.line})

    decoded
    |> Map.merge(%{
      id: System.unique_integer([:positive, :monotonic]),
      kind: boundary.kind,
      pc_before: before.cpu.pc,
      pc_after: after_state.cpu.pc,
      cycles: cycles,
      registers: registers,
      register_deltas: registers.changes,
      flags: delta_group(flags(before.cpu.f), flags(after_state.cpu.f)),
      memory: memory,
      ppu: ppu,
      timer: timer,
      interrupts: interrupts,
      serial: serial,
      cartridge: cartridge,
      boot: boot,
      deltas: %{
        cpu: registers.changes,
        ppu: ppu.changes,
        timer: timer.changes,
        interrupts: interrupts.changes,
        serial: serial.changes,
        cartridge: cartridge.changes,
        boot: boot.changes
      },
      events: notable,
      sources: sources
    })
  end

  defp trace_state(gb) do
    %{
      cpu: Map.take(gb, @cpu_fields),
      ppu: Map.take(gb, @ppu_fields),
      timer: Map.take(gb, @timer_fields),
      interrupts: %{ie: gb.ie, if: gb.if_},
      serial: %{
        cycles_remaining: gb.serial_cycles,
        output_bytes: length(gb.serial_out)
      },
      cartridge: Map.take(gb, @cartridge_fields),
      boot: Map.take(gb, @boot_fields)
    }
  end

  defp delta_group(before, after_state) do
    %{before: before, after: after_state, changes: changes(before, after_state)}
  end

  defp changes(before, after_state) do
    Enum.reduce(before, %{}, fn {field, old}, acc ->
      new = Map.fetch!(after_state, field)

      if old == new do
        acc
      else
        Map.put(acc, field, %{before: old, after: new})
      end
    end)
  end

  defp flags(value) do
    %{
      z: (value &&& 0x80) != 0,
      n: (value &&& 0x40) != 0,
      h: (value &&& 0x20) != 0,
      c: (value &&& 0x10) != 0
    }
  end

  defp resolve_event_source(%{source_location: source} = event) when is_tuple(source) do
    Map.put(event, :source_location, resolve_source(source))
  end

  defp resolve_event_source(event), do: event

  defp source_references(events) do
    Enum.flat_map(events, fn
      %{source_location: %{component: component, selector: selector}} -> [{component, selector}]
      _ -> []
    end)
  end

  defp resolve_source({component, selector}), do: SourceMap.location(component, selector)

  defp memory_side_effects(memory) do
    Enum.flat_map(memory, fn event ->
      event
      |> Map.get(:side_effects, [])
      |> Enum.map(&Map.put(&1, :source_location, event.source_location))
    end)
  end

  defp boundary_events(%{kind: :interrupt} = boundary, _before, _after_state) do
    [
      %{
        type: :interrupt_dispatch,
        interrupt: boundary.interrupt,
        vector: boundary.vector,
        source_location: resolve_source({:cpu, "defp service_interrupt(gb, pending) do"})
      }
    ]
  end

  defp boundary_events(%{kind: :halt}, _before, _after_state) do
    [
      %{
        type: :halt_idle,
        source_location: resolve_source({:cpu, "def step(gb) do"})
      }
    ]
  end

  defp boundary_events(_boundary, _before, _after_state), do: []

  defp interrupt_name(:vblank), do: "VBLANK"
  defp interrupt_name(:lcd_stat), do: "LCD STAT"
  defp interrupt_name(:timer), do: "TIMER"
  defp interrupt_name(:serial), do: "SERIAL"
  defp interrupt_name(:joypad), do: "JOYPAD"

  defp hex16(value) do
    value
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(4, "0")
  end
end
