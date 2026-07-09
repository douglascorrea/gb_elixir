defmodule GbEmu.Debugger.Snapshot do
  @moduledoc """
  Builds compact, display-only debugger state from the authoritative machine.
  """

  import Bitwise

  alias GbEmu.{Bus, GB}
  alias GbEmu.Debugger.Disassembler

  @memory_size 256
  @history_limit 200
  @trace_collection_limit 512
  @trace_text_limit 255

  @trace_keys [
    :id,
    :kind,
    :pc,
    :opcode,
    :cb_opcode,
    :bytes,
    :length,
    :mnemonic,
    :operands,
    :handler,
    :pc_before,
    :pc_after,
    :cycles,
    :registers,
    :register_deltas,
    :flags,
    :memory,
    :ppu,
    :timer,
    :interrupts,
    :serial,
    :cartridge,
    :boot,
    :deltas,
    :events,
    :sources
  ]

  @trace_nested_keys [
    :type,
    :operation,
    :address,
    :value,
    :requested,
    :before,
    :after,
    :changes,
    :region,
    :label,
    :source_location,
    :side_effects,
    :ranges,
    :source,
    :destination,
    :start,
    :stop,
    :purpose,
    :component,
    :cycles,
    :ly,
    :frame_count,
    :interrupt,
    :vector,
    :compatibility?,
    :source_start,
    :bytes,
    :selector,
    :path,
    :line,
    :url,
    :cpu,
    :ppu,
    :timer,
    :interrupts,
    :serial,
    :cartridge,
    :boot,
    :a,
    :f,
    :b,
    :c,
    :d,
    :e,
    :h,
    :l,
    :sp,
    :pc,
    :ime,
    :ime_pending,
    :halted,
    :z,
    :n,
    :lcdc,
    :stat,
    :scy,
    :scx,
    :lyc,
    :bgp,
    :obp0,
    :obp1,
    :wy,
    :wx,
    :ppu_dot,
    :ppu_mode,
    :window_line,
    :div_counter,
    :tima_acc,
    :tima,
    :tma,
    :tac,
    :ie,
    :if,
    :if_,
    :sb,
    :sc,
    :cycles_remaining,
    :output_bytes,
    :mbc,
    :rom_bank,
    :rom_bank_mask,
    :ram_bank,
    :ram_enabled,
    :mbc1_mode,
    :boot_enabled,
    :boot_kind,
    :boot_mode
  ]

  @trace_text_keys [:mnemonic, :label, :selector, :path, :url]

  @doc "Builds a compact snapshot and a clamped 256-byte memory window."
  @spec build(GB.t(), keyword()) :: map()
  def build(gb, opts \\ []) do
    newest_trace =
      opts
      |> Keyword.get(:newest_trace, Keyword.get(opts, :trace))
      |> project_trace()

    history =
      opts
      |> Keyword.get(:history, default_history(newest_trace))
      |> project_history()

    instruction = Disassembler.decode(gb)
    next_pc = gb.pc + instruction.length &&& 0xFFFF
    next_instruction = Disassembler.decode(%{gb | pc: next_pc})
    memory_start = normalize_start(Keyword.get(opts, :memory_start, gb.pc))

    %{
      cpu: cpu(gb),
      interrupts: %{ie: gb.ie, if: gb.if_, pending: gb.ie &&& gb.if_ &&& 0x1F},
      ppu: ppu(gb),
      timer: timer(gb),
      serial: serial(gb),
      joypad: joypad(gb),
      cartridge: cartridge(gb),
      boot: boot(gb),
      instruction: instruction,
      next_instruction: next_instruction,
      memory: memory(gb, memory_start, newest_trace),
      newest_trace: newest_trace,
      history: history
    }
  end

  defp project_history(history) when is_list(history) do
    history
    |> Enum.take(-@history_limit)
    |> Enum.map(&project_trace/1)
    |> Enum.reject(&is_nil/1)
  end

  defp project_history(_history), do: []

  defp project_trace(nil), do: nil
  defp project_trace(%{__struct__: _module}), do: nil

  defp project_trace(trace) when is_map(trace) do
    project_map(trace, @trace_keys)
  end

  defp project_trace(_trace), do: nil

  defp project_map(map, keys) do
    Enum.reduce(keys, %{}, fn key, projected ->
      with {:ok, value} <- Map.fetch(map, key),
           {:ok, value} <- project_value(key, value) do
        Map.put(projected, key, value)
      else
        _ -> projected
      end
    end)
  end

  defp project_value(:handler, {component, selector})
       when is_atom(component) and is_binary(selector) do
    case project_text(selector) do
      {:ok, selector} -> {:ok, {component, selector}}
      :error -> :error
    end
  end

  defp project_value(_key, %Range{} = range), do: {:ok, range}
  defp project_value(_key, %{__struct__: _module}), do: :error

  defp project_value(_key, value) when is_map(value) do
    {:ok, project_map(value, @trace_nested_keys)}
  end

  defp project_value(_key, value) when is_list(value) do
    projected =
      value
      |> Enum.take(@trace_collection_limit)
      |> Enum.reduce([], fn item, acc ->
        case project_value(nil, item) do
          {:ok, item} -> [item | acc]
          :error -> acc
        end
      end)
      |> Enum.reverse()

    {:ok, projected}
  end

  defp project_value(key, value) when key in @trace_text_keys and is_binary(value),
    do: project_text(value)

  defp project_value(_key, value)
       when is_integer(value) or is_float(value) or is_atom(value),
       do: {:ok, value}

  defp project_value(_key, _value), do: :error

  defp project_text(value) do
    if byte_size(value) <= @trace_text_limit and String.valid?(value) and
         String.printable?(value) do
      {:ok, value}
    else
      :error
    end
  end

  defp cpu(gb) do
    %{
      registers: Map.take(gb, [:a, :f, :b, :c, :d, :e, :h, :l, :sp, :pc]),
      flags: flags(gb.f),
      ime: gb.ime,
      ime_pending: gb.ime_pending,
      halted: gb.halted
    }
  end

  defp flags(value) do
    %{
      z: (value &&& 0x80) != 0,
      n: (value &&& 0x40) != 0,
      h: (value &&& 0x20) != 0,
      c: (value &&& 0x10) != 0
    }
  end

  defp ppu(gb) do
    Map.take(gb, [
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
    ])
  end

  defp timer(gb), do: Map.take(gb, [:div_counter, :tima_acc, :tima, :tma, :tac])

  defp serial(gb) do
    %{
      data: Bus.peek8(gb, 0xFF01),
      control: Bus.peek8(gb, 0xFF02),
      cycles_remaining: gb.serial_cycles,
      output_bytes: length(gb.serial_out)
    }
  end

  defp joypad(gb), do: Map.take(gb, [:joyp_select, :dpad, :btns])

  defp cartridge(gb) do
    Map.take(gb, [:mbc, :rom_bank, :rom_bank_mask, :ram_bank, :ram_enabled, :mbc1_mode])
  end

  defp boot(gb) do
    %{
      kind: gb.boot_kind,
      mode: gb.boot_mode,
      overlay_enabled?: gb.boot_enabled
    }
  end

  defp memory(gb, start, newest_trace) do
    bytes = for address <- start..(start + @memory_size - 1), do: Bus.peek8(gb, address)
    activity = memory_activity(newest_trace)

    cells =
      bytes
      |> Enum.with_index(start)
      |> Enum.map(fn {value, address} ->
        read? = active?(activity.reads, activity.read_ranges, address)
        write? = active?(activity.writes, activity.write_ranges, address)

        %{
          address: address,
          value: value,
          region: Bus.region(gb, address),
          label: Bus.label(gb, address),
          pc?: address == gb.pc,
          sp?: address == gb.sp,
          read?: read?,
          write?: write?,
          markers: markers(address == gb.pc, address == gb.sp, read?, write?)
        }
      end)

    %{
      start: start,
      stop: start + @memory_size - 1,
      bytes: bytes,
      cells: cells,
      markers: %{
        pc: gb.pc,
        sp: gb.sp,
        reads: activity.reads |> MapSet.to_list() |> Enum.sort(),
        writes: activity.writes |> MapSet.to_list() |> Enum.sort()
      }
    }
  end

  defp memory_activity(nil) do
    %{reads: MapSet.new(), writes: MapSet.new(), read_ranges: [], write_ranges: []}
  end

  defp memory_activity(%{memory: memory}) when is_list(memory) do
    Enum.reduce(memory, memory_activity(nil), fn event, acc ->
      case event do
        %{operation: :read, address: address} when is_integer(address) ->
          %{acc | reads: MapSet.put(acc.reads, address)}

        %{operation: :write, address: address} when is_integer(address) ->
          %{acc | writes: MapSet.put(acc.writes, address)}

        %{operation: :read_range, ranges: ranges} ->
          %{acc | read_ranges: event_ranges(ranges) ++ acc.read_ranges}

        %{operation: :dma, source: %Range{} = source, destination: %Range{} = destination} ->
          %{
            acc
            | read_ranges: [source | acc.read_ranges],
              write_ranges: [destination | acc.write_ranges]
          }

        _ ->
          acc
      end
    end)
  end

  defp memory_activity(_trace), do: memory_activity(nil)

  defp event_ranges(ranges) do
    Enum.flat_map(ranges, fn
      %{start: start, stop: stop} when is_integer(start) and is_integer(stop) -> [start..stop]
      %Range{} = range -> [range]
      _ -> []
    end)
  end

  defp active?(addresses, ranges, address) do
    MapSet.member?(addresses, address) or Enum.any?(ranges, &(address in &1))
  end

  defp markers(pc?, sp?, read?, write?) do
    []
    |> maybe_marker(pc?, :pc)
    |> maybe_marker(sp?, :sp)
    |> maybe_marker(read?, :read)
    |> maybe_marker(write?, :write)
    |> Enum.reverse()
  end

  defp maybe_marker(markers, true, marker), do: [marker | markers]
  defp maybe_marker(markers, false, _marker), do: markers

  defp normalize_start(address) when is_integer(address) do
    address
    |> max(0)
    |> min(0xFF00)
    |> band(0xFFF0)
  end

  defp normalize_start(address) do
    raise ArgumentError, "memory_start must be an integer, got: #{inspect(address)}"
  end

  defp default_history(nil), do: []
  defp default_history(trace), do: [trace]
end
