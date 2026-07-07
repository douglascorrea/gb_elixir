defmodule GbEmu.EmulatorSessionsTest do
  use ExUnit.Case, async: false

  alias GbEmu.EmulatorSessions

  defp test_rom do
    rom = :binary.copy(<<0>>, 0x8000)

    rom
    |> put_byte(0x100, 0xC3)
    |> put_byte(0x101, 0x00)
    |> put_byte(0x102, 0x01)
    |> put_byte(0x147, 0x00)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end

  defp subscriber do
    child_spec =
      Supervisor.child_spec(
        {Task, fn -> receive do: (:stop -> :ok) end},
        id: {:emulator_session_test_subscriber, make_ref()}
      )

    start_supervised!(child_spec)
  end

  test "session manager enforces the configured emulator capacity" do
    assert EmulatorSessions.active_count() == 0

    rom_path = Path.join(System.tmp_dir!(), "gb_emu_session_test.gb")
    File.write!(rom_path, test_rom())
    on_exit(fn -> File.rm(rom_path) end)

    max_sessions = EmulatorSessions.max_sessions()

    subscribers =
      for _ <- 1..max_sessions do
        subscriber = subscriber()

        assert {:ok, _pid} =
                 EmulatorSessions.start_emulator(subscriber: subscriber, rom_path: rom_path)

        subscriber
      end

    assert EmulatorSessions.active_count() == max_sessions

    extra_subscriber = subscriber()

    assert {:error, :capacity} =
             EmulatorSessions.start_emulator(subscriber: extra_subscriber, rom_path: rom_path)

    Enum.each(subscribers, &send(&1, :stop))
    :sys.get_state(EmulatorSessions)

    assert EmulatorSessions.active_count() == 0
  end
end
