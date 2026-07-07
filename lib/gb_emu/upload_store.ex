defmodule GbEmu.UploadStore do
  @moduledoc """
  Stores browser-session ROM uploads and deletes them after inactivity.

  Uploaded files live under a random session id carried in Phoenix's signed
  session cookie. Every browser revisit touches the directory and schedules a
  cleanup check. A directory is deleted only after the configured TTL has passed
  without another touch.
  """

  use GenServer

  @default_ttl_ms :timer.hours(2)
  @default_sweep_interval_ms :timer.minutes(10)
  @game_filename "game.gb"
  @boot_filename "boot.bin"
  @last_seen_filename ".last_seen"

  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  def get_or_create_session(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_or_create_session, session_id})
  end

  def touch_session(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:touch_session, session_id})
  end

  def put_game!(session_id, source_path, server \\ __MODULE__) do
    GenServer.call(server, {:put_file, session_id, :game, source_path})
  end

  def put_boot!(session_id, source_path, server \\ __MODULE__) do
    GenServer.call(server, {:put_file, session_id, :boot, source_path})
  end

  def schedule_cleanup(session_id, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    ttl_ms = Keyword.get(opts, :ttl_ms, ttl_ms())
    GenServer.call(server, {:schedule_cleanup, session_id, ttl_ms})
  end

  def upload_root do
    System.get_env("GB_EMU_UPLOAD_ROOT") ||
      Path.join(System.tmp_dir!(), "gb_emu_uploads")
  end

  def ttl_ms do
    "GB_EMU_UPLOAD_TTL_MS"
    |> System.get_env()
    |> parse_non_negative_integer()
    |> Kernel.||(@default_ttl_ms)
  end

  @impl true
  def init(opts) do
    root = Keyword.get_lazy(opts, :root, &upload_root/0)
    ttl_ms = Keyword.get(opts, :ttl_ms, ttl_ms())
    sweep_interval_ms = Keyword.get(opts, :sweep_interval_ms, @default_sweep_interval_ms)

    File.mkdir_p!(root)
    File.chmod(root, 0o700)

    state = %{
      root: Path.expand(root),
      ttl_ms: ttl_ms,
      sweep_interval_ms: sweep_interval_ms
    }

    schedule_sweep(state)
    {:ok, sweep_stale_uploads(state)}
  end

  @impl true
  def handle_call({:get_or_create_session, session_id}, _from, state) do
    session = touch_session!(state, session_id)
    {:reply, session, state}
  end

  def handle_call({:touch_session, session_id}, _from, state) do
    session = touch_session!(state, session_id)
    {:reply, session, state}
  end

  def handle_call({:put_file, session_id, kind, source_path}, _from, state) do
    session = touch_session!(state, session_id)
    target_path = Path.join(session.dir, filename(kind))

    File.cp!(source_path, target_path)
    File.chmod(target_path, 0o600)
    touch_session!(state, session_id)

    {:reply, session_paths(session.dir), state}
  end

  def handle_call({:schedule_cleanup, session_id, ttl_ms}, _from, state) when ttl_ms <= 0 do
    cleanup_session(state, session_id, ttl_ms)
    {:reply, :ok, state}
  end

  def handle_call({:schedule_cleanup, session_id, ttl_ms}, _from, state) do
    schedule_cleanup_check(session_id, ttl_ms)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:cleanup, session_id, ttl_ms}, state) do
    cleanup_session(state, session_id, ttl_ms)
    {:noreply, state}
  end

  def handle_info(:sweep_stale_uploads, state) do
    state = sweep_stale_uploads(state)
    schedule_sweep(state)
    {:noreply, state}
  end

  defp touch_session!(state, session_id) do
    validate_session_id!(session_id)

    dir = session_dir(state.root, session_id)
    File.mkdir_p!(dir)
    File.chmod(dir, 0o700)

    touch_last_seen!(dir)
    schedule_cleanup_check(session_id, state.ttl_ms)

    session_paths(dir)
  end

  defp session_paths(dir) do
    game_path = Path.join(dir, @game_filename)
    boot_path = Path.join(dir, @boot_filename)

    %{
      dir: dir,
      game_path: existing_path(game_path),
      boot_path: existing_path(boot_path)
    }
  end

  defp existing_path(path), do: if(File.exists?(path), do: path)

  defp session_dir(root, session_id), do: Path.join(root, session_id)

  defp filename(:game), do: @game_filename
  defp filename(:boot), do: @boot_filename

  defp schedule_cleanup_check(session_id, ttl_ms) when ttl_ms <= 0 do
    send(self(), {:cleanup, session_id, 0})
  end

  defp schedule_cleanup_check(session_id, ttl_ms) do
    Process.send_after(self(), {:cleanup, session_id, ttl_ms}, ttl_ms)
  end

  defp cleanup_session(state, session_id, ttl_ms) do
    path = session_dir(state.root, session_id)

    with true <- File.dir?(path),
         {:ok, last_seen_ms} <- last_seen_ms(path) do
      age_ms = System.system_time(:millisecond) - last_seen_ms

      if age_ms >= ttl_ms do
        rm_rf_inside_root(state.root, path)
      else
        schedule_cleanup_check(session_id, ttl_ms - age_ms)
      end
    end
  end

  defp sweep_stale_uploads(state) do
    cutoff = System.system_time(:millisecond) - state.ttl_ms

    state.root
    |> File.ls!()
    |> Enum.map(&Path.join(state.root, &1))
    |> Enum.each(fn path ->
      with true <- File.dir?(path),
           {:ok, last_seen_ms} <- last_seen_ms(path),
           true <- last_seen_ms < cutoff do
        rm_rf_inside_root(state.root, path)
      else
        _ -> :ok
      end
    end)

    state
  end

  defp schedule_sweep(%{sweep_interval_ms: false}), do: :ok
  defp schedule_sweep(%{sweep_interval_ms: nil}), do: :ok

  defp schedule_sweep(%{sweep_interval_ms: sweep_interval_ms}) do
    Process.send_after(self(), :sweep_stale_uploads, sweep_interval_ms)
  end

  defp rm_rf_inside_root(root, path) do
    root = Path.expand(root)
    path = Path.expand(path)

    if String.starts_with?(path, root <> "/") do
      File.rm_rf(path)
    else
      {:error, :outside_upload_root}
    end
  end

  defp touch_last_seen!(dir) do
    path = Path.join(dir, @last_seen_filename)

    unless File.exists?(path) do
      File.write!(path, "")
      File.chmod(path, 0o600)
    end

    File.touch!(path)
  end

  defp last_seen_ms(dir) do
    marker_path = Path.join(dir, @last_seen_filename)

    case File.stat(marker_path, time: :posix) do
      {:ok, stat} -> {:ok, stat.mtime * 1000}
      _ -> dir_mtime_ms(dir)
    end
  end

  defp dir_mtime_ms(dir) do
    case File.stat(dir, time: :posix) do
      {:ok, stat} -> {:ok, stat.mtime * 1000}
      error -> error
    end
  end

  defp validate_session_id!(session_id)
       when is_binary(session_id) and byte_size(session_id) >= 32 do
    if String.match?(session_id, ~r/\A[-_A-Za-z0-9]+\z/) do
      :ok
    else
      raise ArgumentError, "invalid upload session id"
    end
  end

  defp validate_session_id!(_session_id), do: raise(ArgumentError, "invalid upload session id")

  defp parse_non_negative_integer(nil), do: nil

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _ -> nil
    end
  end
end
