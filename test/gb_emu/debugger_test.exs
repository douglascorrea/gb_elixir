defmodule GbEmu.DebuggerTest do
  use ExUnit.Case, async: true

  alias GbEmu.{BootRom, Bus, Debugger, GB, Machine}
  alias GbEmu.Debugger.{Disassembler, Snapshot, SourceMap, Trace}

  defp test_rom do
    rom = :binary.copy(<<0>>, 0x8000)

    rom
    |> put_byte(0x100, 0xC3)
    |> put_byte(0x101, 0x00)
    |> put_byte(0x102, 0x01)
    |> put_byte(0x147, 0x00)
  end

  defp new_machine, do: Machine.new(BootRom.minimal(), test_rom())

  defp machine_with_bytes(bytes) do
    rom = put_bytes(test_rom(), 0x100, bytes)
    Machine.new(BootRom.minimal(), rom)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end

  defp put_bytes(binary, index, bytes) do
    prefix = binary_part(binary, 0, index)
    suffix_start = index + byte_size(bytes)
    suffix = binary_part(binary, suffix_start, byte_size(binary) - suffix_start)
    prefix <> bytes <> suffix
  end

  test "cold open boot executes three instructions and hands off at 0100" do
    gb = Machine.new(BootRom.minimal(), test_rom(), boot_mode: :cold)
    assert gb.pc == 0x0000
    assert gb.boot_enabled
    assert gb.boot_kind == :minimal
    assert gb.boot_mode == :cold
    refute gb.debug_trace?

    {gb, 16} = Machine.step_instruction(gb)
    assert gb.pc == 0x00FC
    {gb, 8} = Machine.step_instruction(gb)
    assert gb.pc == 0x00FE
    {gb, 12} = Machine.step_instruction(gb)

    assert gb.pc == 0x0100
    refute gb.boot_enabled
    assert gb.sp == 0xFFFE
    assert gb.lcdc == 0x91
  end

  test "disassembler decodes literal, grouped, immediate, and CB-prefixed instructions" do
    literal = Disassembler.decode(machine_with_bytes(<<0xEA, 0x00, 0xC0>>))

    assert literal == %{
             kind: :instruction,
             pc: 0x0100,
             opcode: 0xEA,
             bytes: [0xEA, 0x00, 0xC0],
             length: 3,
             mnemonic: "LD ($C000), A",
             operands: [0xC000],
             handler: {:cpu, "defp exec(0xEA"}
           }

    grouped = Disassembler.decode(machine_with_bytes(<<0x41>>))
    assert grouped.mnemonic == "LD B, C"
    assert grouped.length == 1
    assert grouped.handler == {:cpu, "defp exec(op, gb) when op in 0x40..0x7F do"}

    immediate = Disassembler.decode(machine_with_bytes(<<0x06, 0x7F>>))
    assert immediate.mnemonic == "LD B, $7F"
    assert immediate.bytes == [0x06, 0x7F]
    assert immediate.operands == [0x7F]

    cb = Disassembler.decode(machine_with_bytes(<<0xCB, 0x7C>>))
    assert cb.mnemonic == "BIT 7, H"
    assert cb.bytes == [0xCB, 0x7C]
    assert cb.length == 2
    assert cb.cb_opcode == 0x7C
    assert cb.handler == {:cpu, "defp exec_cb(op, gb) do"}
  end

  test "a traced store explains instruction memory and source flow" do
    gb = %{machine_with_bytes(<<0xEA, 0x00, 0xC0>>) | a: 0x42}

    {gb, trace} = Debugger.step(gb)

    assert trace.kind == :instruction
    assert trace.pc_before == 0x0100
    assert trace.pc_after == 0x0103
    assert trace.mnemonic == "LD ($C000), A"
    assert trace.cycles == 16

    assert Enum.any?(trace.memory, fn event ->
             match?(
               %{
                 operation: :write,
                 address: 0xC000,
                 requested: 0x42,
                 before: 0x00,
                 after: 0x42,
                 region: :wram
               },
               event
             )
           end)

    assert Enum.any?(trace.sources, fn source ->
             source.path == "lib/gb_emu/cpu.ex" and is_integer(source.line)
           end)

    assert Enum.any?(trace.sources, &(&1.path == "lib/gb_emu/bus.ex"))
    write_event = Enum.find(trace.memory, &(&1.operation == :write))
    assert write_event.source_location.selector == "bus:write:wram"
    assert Bus.read8(gb, 0xC000) == 0x42
    refute gb.debug_trace?
  end

  test "a traced load records reads and register deltas" do
    gb = machine_with_bytes(<<0xFA, 0x00, 0xC0>>)
    gb = Bus.write8(gb, 0xC000, 0x9A)

    {_gb, trace} = Debugger.step(gb)

    assert trace.register_deltas.a == %{before: 0x01, after: 0x9A}
    assert trace.register_deltas.pc == %{before: 0x0100, after: 0x0103}

    assert Enum.any?(trace.memory, fn event ->
             match?(
               %{operation: :read, address: 0xC000, value: 0x9A, region: :wram},
               event
             )
           end)

    data_read = Enum.find(trace.memory, &(&1.operation == :read and &1.address == 0xC000))
    assert data_read.source_location.selector == "bus:read:wram"
  end

  test "a traced instruction reports coordinated PPU and timer changes" do
    gb = machine_with_bytes(<<0x00>>)

    {_gb, trace} = Debugger.step(gb)

    assert trace.cycles == 4
    assert trace.ppu.changes.ppu_dot == %{before: 0, after: 4}
    assert trace.timer.changes.div_counter == %{before: 0xABCC, after: 0xABD0}
    assert Enum.any?(trace.sources, &(&1.path == "lib/gb_emu/ppu.ex"))
    assert Enum.any?(trace.sources, &(&1.path == "lib/gb_emu/timer.ex"))
  end

  test "a traced serial completion reports SB and SC before-after deltas" do
    gb = machine_with_bytes(<<0x00>>)
    gb = Bus.write8(gb, 0xFF01, 0x42)
    gb = Bus.write8(gb, 0xFF02, 0x81)
    gb = %{gb | serial_cycles: 4}

    {gb, trace} = Debugger.step(gb)

    assert trace.serial.before == %{
             sb: 0x42,
             sc: 0x81,
             cycles_remaining: 4,
             output_bytes: 0
           }

    assert trace.serial.after == %{
             sb: 0xFF,
             sc: 0x01,
             cycles_remaining: nil,
             output_bytes: 1
           }

    assert trace.serial.changes.sb == %{before: 0x42, after: 0xFF}
    assert trace.serial.changes.sc == %{before: 0x81, after: 0x01}
    assert Bus.peek8(gb, 0xFF01) == 0xFF
    assert Bus.peek8(gb, 0xFF02) == 0x01
  end

  test "PPU scanline rendering records grouped memory ranges and a transition" do
    gb = %{machine_with_bytes(<<0x00>>) | ppu_mode: 3, ppu_dot: 250, ly: 7}

    {_gb, trace} = Debugger.step(gb)

    assert Enum.any?(trace.memory, fn event ->
             event.operation == :read_range and
               Enum.any?(event.ranges, &(&1.purpose == :tile_data))
           end)

    assert Enum.any?(trace.events, &(&1.type == :scanline_render and &1.ly == 7))
    assert trace.ppu.changes.ppu_mode == %{before: 3, after: 0}
  end

  test "PPU sprite ranges use unsigned tile data independently of the background mode" do
    gb = %{
      machine_with_bytes(<<0x00>>)
      | lcdc: 0x82,
        ppu_mode: 3,
        ppu_dot: 250,
        ly: 7
    }

    {_gb, trace} = Debugger.step(gb)
    grouped = Enum.find(trace.memory, &(&1.operation == :read_range))

    assert Enum.any?(grouped.ranges, fn range ->
             match?(
               %{purpose: :sprite_tile_data, start: 0x8000, stop: 0x8FFF},
               range
             )
           end)
  end

  test "DMA emits one grouped transfer instead of one read per byte" do
    gb = machine_with_bytes(<<0xE0, 0x46>>)
    gb = %{gb | a: 0xC0}

    {_gb, trace} = Debugger.step(gb)

    dma_events = Enum.filter(trace.memory, &(&1.operation == :dma))
    assert [%{source: 0xC000..0xC09F, destination: 0xFE00..0xFE9F}] = dma_events

    refute Enum.any?(trace.memory, fn event ->
             event.operation == :read and event.address in 0xC000..0xC09F
           end)
  end

  test "interrupt and idle HALT boundaries are classified from pre-step CPU state" do
    interrupt_gb =
      machine_with_bytes(<<0x00>>)
      |> Map.merge(%{ime: true, ie: 0x04, if_: 0x04, sp: 0xFFFE})

    {interrupt_gb, interrupt_trace} = Debugger.step(interrupt_gb)
    assert interrupt_trace.kind == :interrupt
    assert interrupt_trace.mnemonic == "INT TIMER ($0050)"
    assert interrupt_trace.bytes == []
    assert interrupt_trace.pc_after == 0x0050
    assert interrupt_gb.sp == 0xFFFC

    halt_gb = %{machine_with_bytes(<<0x00>>) | halted: true}
    {halt_gb, halt_trace} = Debugger.step(halt_gb)
    assert halt_trace.kind == :halt
    assert halt_trace.mnemonic == "HALT (idle)"
    assert halt_trace.pc_before == halt_trace.pc_after
    assert halt_trace.cycles == 4
    assert halt_gb.halted
  end

  test "source locations resolve to real compile-time source lines" do
    source = SourceMap.location(:cpu, "defp exec(0xEA, gb)")

    assert source.path == "lib/gb_emu/cpu.ex"
    assert source.line > 0
    assert source.label == "CPU"
    assert String.ends_with?(source.url, "lib/gb_emu/cpu.ex#L#{source.line}")

    line =
      "lib/gb_emu/cpu.ex"
      |> File.read!()
      |> String.split("\n")
      |> Enum.at(source.line - 1)

    assert String.contains?(line, "defp exec(0xEA, gb)")

    read_branch = SourceMap.location(:bus, "bus:read:wram")
    write_branch = SourceMap.location(:bus, "bus:write:wram")

    read_line =
      read_branch.path
      |> File.read!()
      |> String.split("\n")
      |> Enum.at(read_branch.line - 1)

    write_line =
      write_branch.path
      |> File.read!()
      |> String.split("\n")
      |> Enum.at(write_branch.line - 1)

    assert String.contains?(read_line, "addr < 0xE000 ->")
    assert String.contains?(write_line, "addr < 0xE000 ->")
    assert read_branch.line != write_branch.line
  end

  test "the open-stub compatibility handoff is reported exactly once" do
    gb = Machine.new(BootRom.minimal(), test_rom(), boot_mode: :cold)

    {gb, _trace} = Debugger.step(gb)
    {gb, _trace} = Debugger.step(gb)
    {_gb, trace} = Debugger.step(gb)

    assert Enum.count(trace.events, &(&1.type == :boot_handoff)) == 1
  end

  test "a 256-byte file-style boot traces from 0000 without the open-stub handoff" do
    file_boot = put_byte(BootRom.minimal(), 0x80, 0x42)
    assert byte_size(file_boot) == 256
    refute BootRom.minimal?(file_boot)

    gb = Machine.new(file_boot, test_rom())

    assert gb.pc == 0x0000
    assert gb.boot_enabled
    assert gb.boot_kind == :file

    {gb, first_trace} = Debugger.step(gb)

    assert first_trace.pc_before == 0x0000
    assert first_trace.pc_after == 0x00FC
    assert first_trace.mnemonic == "JP $00FC"
    refute Enum.any?(first_trace.events, &(&1.type == :boot_handoff))

    {gb, _second_trace} = Debugger.step(gb)
    {gb, handoff_trace} = Debugger.step(gb)

    assert [%{compatibility?: false}] =
             Enum.filter(handoff_trace.events, &(&1.type == :boot_handoff))

    refute gb.boot_enabled
    assert gb.pc == 0x0100
    assert gb.sp == 0x0000
    assert gb.lcdc == 0x00
  end

  test "snapshot clamps and aligns a 256-byte memory window without trace reads" do
    newest_trace = %{
      memory: [
        %{operation: :read, address: 0xFF10},
        %{operation: :write, address: 0xFF20}
      ]
    }

    gb = %{new_machine() | debug_trace?: true}

    {snapshot, events} =
      Trace.capture(fn ->
        Snapshot.build(gb, memory_start: 0xFFF8, newest_trace: newest_trace)
      end)

    assert events == []
    assert snapshot.memory.start == 0xFF00
    assert snapshot.memory.stop == 0xFFFF
    assert length(snapshot.memory.bytes) == 256
    assert length(snapshot.memory.cells) == 256

    assert %{pc?: false, sp?: true} = Enum.at(snapshot.memory.cells, 0xFE)
    assert %{read?: true, write?: false} = Enum.at(snapshot.memory.cells, 0x10)
    assert %{read?: false, write?: true} = Enum.at(snapshot.memory.cells, 0x20)

    aligned = Snapshot.build(new_machine(), memory_start: 0x012B)
    assert aligned.memory.start == 0x0120
  end

  test "snapshot recursively projects caller traces onto a display-only schema" do
    gb = new_machine()
    frame = :binary.copy(<<3>>, 160 * 144)

    newest_trace = %{
      id: 7,
      kind: :instruction,
      mnemonic: "NOP",
      registers: gb,
      memory: [
        %{
          type: :memory,
          operation: :read,
          address: 0xC000,
          value: gb.vram,
          label: gb.boot,
          before: gb,
          payload: %{rom: gb.rom, atomics: gb.wram}
        }
      ],
      events: [
        %{
          type: :stage,
          component: :cpu,
          cycles: gb.extram,
          source_location: gb.oam,
          after: %{frame: frame, atomics: gb.hram}
        }
      ],
      machine: gb,
      rom: gb.rom
    }

    history_trace = %{
      id: 6,
      kind: :instruction,
      mnemonic: gb.rom,
      handler: {:cpu, frame},
      events: [%{type: :stage, before: gb, source_location: gb.io_misc}],
      boot: gb.boot,
      frame: frame,
      atomics: [gb.vram, gb.wram, gb.oam, gb.hram, gb.extram, gb.io_misc]
    }

    snapshot =
      Snapshot.build(gb,
        newest_trace: newest_trace,
        history: [history_trace, newest_trace]
      )

    assert snapshot.newest_trace.id == 7
    assert snapshot.newest_trace.mnemonic == "NOP"
    assert Enum.map(snapshot.history, & &1.id) == [6, 7]

    refute nested_match?(snapshot, &is_struct(&1, GB))
    refute nested_match?(snapshot, &is_reference/1)

    for machine_binary <- [gb.rom, gb.boot, frame] do
      refute nested_match?(snapshot, &(&1 === machine_binary))
    end
  end

  test "snapshot preserves every display-safe field in a rich debugger trace" do
    gb = %{machine_with_bytes(<<0xE0, 0x46>>) | a: 0xC0}
    {gb, trace} = Debugger.step(gb)
    trace = %{trace | operands: trace.operands ++ ["DMA", :block]}

    snapshot = Snapshot.build(gb, newest_trace: trace, history: [trace])

    assert snapshot.newest_trace == trace
    assert snapshot.history == [trace]
  end

  test "snapshot preserves serial and joypad Bus side-effect fields" do
    serial_gb = %{machine_with_bytes(<<0xE0, 0x02>>) | a: 0x81}
    {serial_gb, serial_trace} = Debugger.step(serial_gb)
    serial_snapshot = Snapshot.build(serial_gb, newest_trace: serial_trace)

    assert serial_snapshot.newest_trace == serial_trace

    assert Enum.any?(serial_trace.memory, fn event ->
             get_in(event, [:side_effects, Access.at(0), :changes, :serial_cycles]) == %{
               before: nil,
               after: 4096
             }
           end)

    joypad_gb = %{machine_with_bytes(<<0xE0, 0x00>>) | a: 0x10}
    {joypad_gb, joypad_trace} = Debugger.step(joypad_gb)
    joypad_snapshot = Snapshot.build(joypad_gb, newest_trace: joypad_trace)

    assert joypad_snapshot.newest_trace == joypad_trace

    assert Enum.any?(joypad_trace.memory, fn event ->
             get_in(event, [:side_effects, Access.at(0), :changes, :joyp_select]) == %{
               before: 0x30,
               after: 0x10
             }
           end)
  end

  test "snapshot drops malformed ranges containing non-display terms" do
    reference = make_ref()
    poisoned_range = %{(0xC000..0xC09F) | first: reference}

    trace = %{
      id: 9,
      kind: :instruction,
      memory: [
        %{
          type: :memory,
          operation: :dma,
          source: poisoned_range,
          destination: 0xFE00..0xFE9F
        }
      ]
    }

    snapshot = Snapshot.build(new_machine(), newest_trace: trace)
    [memory_event] = snapshot.newest_trace.memory

    refute Map.has_key?(memory_event, :source)
    assert memory_event.destination == 0xFE00..0xFE9F
    refute nested_match?(snapshot, &is_reference/1)
  end

  test "fixed and boundary commands return snapshots and retain at most 200 traces" do
    {:ok, gb, traces, snapshot} = Debugger.run(machine_with_bytes(<<0x00>>), {:steps, 205})

    assert length(traces) == 200
    assert snapshot.command.total_steps == 205
    assert snapshot.command.history_truncated?
    assert length(snapshot.history) == 200
    assert snapshot.newest_trace == List.last(traces)
    refute gb.debug_trace?

    {:error, :invalid_steps, _gb, [], invalid_snapshot} = Debugger.run(gb, {:steps, 0})
    assert invalid_snapshot.command.total_steps == 0

    ppu_gb = %{machine_with_bytes(<<0x00>>) | ppu_mode: 2, ppu_dot: 78}
    {:ok, _gb, [_trace], ppu_snapshot} = Debugger.run(ppu_gb, :ppu_event)
    assert ppu_snapshot.command.total_steps == 1

    scanline_gb = %{machine_with_bytes(<<0x00>>) | ppu_mode: 0, ppu_dot: 454, ly: 12}
    {:ok, _gb, [_trace], scanline_snapshot} = Debugger.run(scanline_gb, :scanline)
    assert scanline_snapshot.command.total_steps == 1

    frame_gb = %{machine_with_bytes(<<0x00>>) | ppu_mode: 0, ppu_dot: 454, ly: 143}
    {:ok, frame_gb, [frame_trace], frame_snapshot} = Debugger.run(frame_gb, :frame)
    assert frame_gb.frame_count == 1
    assert frame_snapshot.command.total_steps == 1
    assert Enum.any?(frame_trace.events, &(&1.type == :vblank))
  end

  @tag timeout: 30_000
  test "boundary commands stop at their hard instruction ceiling" do
    gb = %{machine_with_bytes(<<0xC3, 0x00, 0x01>>) | lcdc: 0x00}

    assert {:error, :step_limit, _gb, traces, snapshot} = Debugger.run(gb, :ppu_event)
    assert length(traces) == 200
    assert snapshot.command.total_steps == 10_000
    assert snapshot.command.limit == 10_000
    assert snapshot.command.history_truncated?
  end

  defp nested_match?(term, predicate) do
    predicate.(term) or
      cond do
        is_struct(term, Range) ->
          Enum.any?([term.first, term.last, term.step], &nested_match?(&1, predicate))

        is_map(term) ->
          Enum.any?(term, fn {key, value} ->
            nested_match?(key, predicate) or nested_match?(value, predicate)
          end)

        is_list(term) ->
          Enum.any?(term, &nested_match?(&1, predicate))

        is_tuple(term) ->
          term
          |> Tuple.to_list()
          |> Enum.any?(&nested_match?(&1, predicate))

        true ->
          false
      end
  end
end
