defmodule GbEmu.UploadStoreTest do
  use ExUnit.Case, async: false

  alias GbEmu.UploadStore

  @session_id "test_session_1234567890abcdefghijklmnopqrstuvwxyz"

  setup do
    root = Path.join(System.tmp_dir!(), "gb_emu_upload_store_test_#{System.unique_integer()}")
    File.rm_rf!(root)

    child_spec =
      Supervisor.child_spec(
        {UploadStore, root: root, ttl_ms: :timer.hours(2), sweep_interval_ms: false, name: nil},
        id: {UploadStore, make_ref()}
      )

    server = start_supervised!(child_spec)

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root, server: server}
  end

  test "stores game and boot ROMs for the same browser session", %{
    root: root,
    server: server
  } do
    game_source = Path.join(root, "source.gb")
    boot_source = Path.join(root, "source_boot.bin")

    File.write!(game_source, :binary.copy(<<0x42>>, 0x8000))
    File.write!(boot_source, :binary.copy(<<0x24>>, 0x100))

    empty_session = UploadStore.get_or_create_session(@session_id, server)

    assert File.dir?(empty_session.dir)
    assert empty_session.game_path == nil
    assert empty_session.boot_path == nil

    game_session = UploadStore.put_game!(@session_id, game_source, server)
    boot_session = UploadStore.put_boot!(@session_id, boot_source, server)
    touched_session = UploadStore.touch_session(@session_id, server)

    assert game_session.game_path == Path.join(empty_session.dir, "game.gb")
    assert boot_session.boot_path == Path.join(empty_session.dir, "boot.bin")
    assert touched_session.game_path == game_session.game_path
    assert touched_session.boot_path == boot_session.boot_path
    assert File.read!(touched_session.game_path) == File.read!(game_source)
    assert File.read!(touched_session.boot_path) == File.read!(boot_source)
  end

  test "deletes a session when its configured inactive window has elapsed", %{
    root: root,
    server: server
  } do
    game_source = Path.join(root, "cleanup_source.gb")
    File.write!(game_source, :binary.copy(<<0x42>>, 0x8000))

    session = UploadStore.put_game!(@session_id, game_source, server)
    assert File.exists?(session.game_path)

    assert :ok = UploadStore.schedule_cleanup(@session_id, server: server, ttl_ms: 0)
    refute File.exists?(session.dir)
  end
end
