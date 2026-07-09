defmodule GbEmu.Debugger.Snapshot do
  @moduledoc """
  Builds compact, display-only debugger state from the authoritative machine.
  """

  import Bitwise

  alias GbEmu.{Bus, GB}
  alias GbEmu.Debugger.Disassembler

  @memory_size 256
  @history_limit 200

  @doc "Builds a compact snapshot and a clamped 256-byte memory window."
  @spec build(GB.t(), keyword()) :: map()
  def build(gb, opts \\ []) do
    newest_trace = Keyword.get(opts, :newest_trace, Keyword.get(opts, :trace))

    history =
      opts
      |> Keyword.get(:history, default_history(newest_trace))
      |> Enum.take(-@history_limit)

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
