defmodule GbEmu.EmulatorDebuggerTest do
  use ExUnit.Case, async: false

  alias GbEmu.{BootRom, Emulator, GB}

  @history_limit 200

  setup do
    suffix = System.unique_integer([:positive, :monotonic])
    rom_path = Path.join(System.tmp_dir!(), "gb_emu_debugger_#{suffix}.gb")
    boot_rom_path = Path.join(System.tmp_dir!(), "gb_emu_debugger_boot_#{suffix}.bin")

    File.write!(rom_path, test_rom())
    File.write!(boot_rom_path, BootRom.minimal())

    on_exit(fn ->
      File.rm(rom_path)
      File.rm(boot_rom_path)
    end)

    {:ok, rom_path: rom_path, boot_rom_path: boot_rom_path}
  end

  test "attach, step, restart, memory navigation, and resume share one machine", context do
    pid = start_emulator(context)

    assert {:ok, attached} = Emulator.debug_attach(pid, 0x0100)
    assert attached.snapshot.mode == :debugging
    assert attached.snapshot.cpu.pc == 0x0100
    assert attached.snapshot.memory.start == 0x0100
    assert attached.traces == []
    assert attached.meta.history_size == 0

    state = :sys.get_state(pid)
    assert state.paused
    assert state.debug_attached

    assert {:ok, stepped} = Emulator.debug_command(pid, :instruction, 0x0100)
    assert [%{pc_before: 0x0100, pc_after: 0x0101}] = stepped.traces
    assert stepped.snapshot.cpu.pc == 0x0101
    assert length(stepped.snapshot.history) == 1

    assert {:ok, memory} = Emulator.debug_memory(pid, 0xC123)
    assert memory.traces == []
    assert memory.snapshot.cpu.pc == 0x0101
    assert memory.snapshot.memory.start == 0xC120
    assert length(memory.snapshot.history) == 1

    assert {:ok, restarted} = Emulator.debug_command(pid, :restart, 0x0000)
    assert restarted.traces == []
    assert restarted.snapshot.cpu.pc == 0x0000
    assert restarted.snapshot.boot.enabled
    assert restarted.snapshot.boot.mode == :cold
    assert restarted.snapshot.history == []

    assert :ok = Emulator.debug_resume(pid)

    state = :sys.get_state(pid)
    refute state.paused
    refute state.debug_attached
    assert {:error, :not_attached} = Emulator.debug_command(pid, :instruction)
  end

  test "debug history is cumulative and capped at 200 traces", context do
    pid = start_emulator(context)

    assert {:ok, _attached} = Emulator.debug_attach(pid)
    assert {:ok, first} = Emulator.debug_command(pid, :instruction)
    assert length(first.snapshot.history) == 1

    assert {:ok, stepped} = Emulator.debug_command(pid, {:steps, @history_limit + 5})
    assert length(stepped.traces) == @history_limit
    assert length(stepped.snapshot.history) == @history_limit
    assert stepped.meta.history_size == @history_limit
    assert stepped.meta.history_limit == @history_limit
    assert stepped.meta.history_truncated?

    assert {:ok, memory} = Emulator.debug_memory(pid, 0xC000)
    assert memory.meta.history_truncated?

    assert {:ok, attached_again} = Emulator.debug_attach(pid, 0xC000)
    assert attached_again.meta.history_truncated?

    state = :sys.get_state(pid)
    assert length(state.debug_history) == @history_limit
  end

  test "an expired queued command cannot advance the authoritative machine", context do
    pid = start_emulator(context)
    assert {:ok, _attached} = Emulator.debug_attach(pid)
    before = :sys.get_state(pid)
    expired_deadline = System.monotonic_time(:millisecond) - 1

    assert {:error, :timeout} =
             GenServer.call(
               pid,
               {:debug_command, :instruction, 0x0000, expired_deadline},
               500
             )

    after_state = :sys.get_state(pid)
    assert after_state.gb.pc == before.gb.pc
    assert after_state.gb.b == before.gb.b
    assert after_state.debug_history == before.debug_history
  end

  test "an in-flight boundary command stops at its deadline before the call times out", context do
    pid = start_emulator(context)
    assert {:ok, _attached} = Emulator.debug_attach(pid)

    :sys.replace_state(pid, fn state ->
      %{state | gb: %{state.gb | lcdc: 0x00}}
    end)

    deadline = System.monotonic_time(:millisecond) + 10

    assert {:error, :timeout} =
             GenServer.call(pid, {:debug_command, :ppu_event, 0x0000, deadline}, 500)

    confirmed = :sys.get_state(pid)
    synchronized = :sys.get_state(pid)

    assert synchronized.gb.pc == confirmed.gb.pc
    assert synchronized.gb.b == confirmed.gb.b
    assert synchronized.debug_history == confirmed.debug_history
    assert synchronized.debug_history != []
    assert length(synchronized.debug_history) <= @history_limit
    assert Process.alive?(pid)
  end

  test "unattached and invalid debugger calls return bounded public errors", context do
    pid = start_emulator(context)

    assert {:error, :not_attached} = Emulator.debug_command(pid, :instruction)
    assert {:error, :not_attached} = Emulator.debug_memory(pid, 0x0000)
    assert {:error, :not_attached} = Emulator.debug_resume(pid)
    assert {:error, :invalid_memory_start} = Emulator.debug_attach(pid, "0000")
    assert Process.alive?(pid)
  end

  test "normal ROM loading leaves debugging, clears history, and restores fast boot", context do
    pid = start_emulator(context)

    assert {:ok, _attached} = Emulator.debug_attach(pid)
    assert {:ok, _stepped} = Emulator.debug_command(pid, :instruction)

    Emulator.load_rom(pid, context.rom_path, context.boot_rom_path)
    state = :sys.get_state(pid)

    refute state.paused
    refute state.debug_attached
    assert state.debug_history == []
    assert state.rom_path == context.rom_path
    assert state.boot_rom_path == context.boot_rom_path
    assert state.gb.boot_mode == :fast
    refute state.gb.boot_enabled
    assert {:error, :not_attached} = Emulator.debug_memory(pid, 0x0000)
  end

  test "debugger responses never expose the authoritative machine or atomic references",
       context do
    pid = start_emulator(context)

    assert {:ok, _attached} = Emulator.debug_attach(pid)
    assert {:ok, result} = Emulator.debug_command(pid, :instruction)

    refute nested_match?(result, &is_struct(&1, GB))
    refute nested_match?(result, &is_reference/1)
  end

  defp start_emulator(context) do
    start_supervised!(
      {Emulator,
       subscriber: self(), rom_path: context.rom_path, boot_rom_path: context.boot_rom_path}
    )
  end

  defp test_rom do
    :binary.copy(<<0>>, 0x8000)
    |> put_byte(0x0100, 0x04)
    |> put_byte(0x0101, 0x18)
    |> put_byte(0x0102, 0xFD)
    |> put_byte(0x0147, 0x00)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
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
