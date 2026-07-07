defmodule GbEmu.EmulatorSessions do
  @moduledoc """
  Admission control for server-side emulator sessions.

  Each browser session can start a real-time emulator process. This GenServer
  keeps that work bounded by limiting concurrent sessions and stopping an
  emulator when its LiveView subscriber exits.
  """

  use GenServer

  @default_max_sessions 4

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_emulator(opts) do
    GenServer.call(__MODULE__, {:start_emulator, opts})
  end

  def active_count do
    GenServer.call(__MODULE__, :active_count)
  end

  def max_sessions do
    GenServer.call(__MODULE__, :max_sessions)
  end

  @impl true
  def init(opts) do
    max_sessions = Keyword.get_lazy(opts, :max_sessions, &configured_max_sessions/0)

    {:ok,
     %{
       max_sessions: max_sessions,
       emulators: %{},
       subscribers: %{}
     }}
  end

  @impl true
  def handle_call(:active_count, _from, state) do
    {:reply, map_size(state.emulators), state}
  end

  def handle_call(:max_sessions, _from, state) do
    {:reply, state.max_sessions, state}
  end

  def handle_call({:start_emulator, opts}, _from, state) do
    with :ok <- reserve_slot(state),
         {:ok, subscriber} <- fetch_subscriber(opts),
         {:ok, pid} <- start_child(opts) do
      emulator_ref = Process.monitor(pid)
      subscriber_ref = Process.monitor(subscriber)

      session = %{
        emulator: pid,
        emulator_ref: emulator_ref,
        subscriber: subscriber,
        subscriber_ref: subscriber_ref
      }

      state =
        state
        |> put_in([:emulators, emulator_ref], session)
        |> put_in([:subscribers, subscriber_ref], session)

      {:reply, {:ok, pid}, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    cond do
      session = Map.get(state.emulators, ref) ->
        Process.demonitor(session.subscriber_ref, [:flush])
        {:noreply, drop_session(state, session)}

      session = Map.get(state.subscribers, ref) ->
        DynamicSupervisor.terminate_child(GbEmu.EmulatorSupervisor, session.emulator)
        Process.demonitor(session.emulator_ref, [:flush])
        {:noreply, drop_session(state, session)}

      true ->
        {:noreply, state}
    end
  end

  defp reserve_slot(state) do
    if map_size(state.emulators) < state.max_sessions do
      :ok
    else
      {:error, :capacity}
    end
  end

  defp fetch_subscriber(opts) do
    case Keyword.fetch(opts, :subscriber) do
      {:ok, subscriber} when is_pid(subscriber) -> {:ok, subscriber}
      {:ok, _} -> {:error, :invalid_subscriber}
      :error -> {:error, :missing_subscriber}
    end
  end

  defp start_child(opts) do
    child_spec = Supervisor.child_spec({GbEmu.Emulator, opts}, restart: :temporary)
    DynamicSupervisor.start_child(GbEmu.EmulatorSupervisor, child_spec)
  end

  defp drop_session(state, session) do
    state
    |> update_in([:emulators], &Map.delete(&1, session.emulator_ref))
    |> update_in([:subscribers], &Map.delete(&1, session.subscriber_ref))
  end

  defp configured_max_sessions do
    System.get_env("GB_EMU_MAX_SESSIONS")
    |> normalize_max_sessions()
    |> case do
      nil -> Application.get_env(:gb_emu, :max_emulator_sessions, @default_max_sessions)
      max_sessions -> max_sessions
    end
    |> normalize_max_sessions()
    |> Kernel.||(@default_max_sessions)
  end

  defp normalize_max_sessions(value) when is_integer(value) and value >= 0, do: value

  defp normalize_max_sessions(value) when is_binary(value) do
    case Integer.parse(value) do
      {max_sessions, ""} when max_sessions >= 0 -> max_sessions
      _ -> nil
    end
  end

  defp normalize_max_sessions(_value), do: nil
end
