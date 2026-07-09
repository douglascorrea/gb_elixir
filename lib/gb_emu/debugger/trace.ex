defmodule GbEmu.Debugger.Trace do
  @moduledoc """
  Process-local event collection used only while the debugger executes a step.

  Keeping the collector out of the machine struct makes traces opt-in and keeps
  ordinary frame execution free of retained debugger state.
  """

  @key {__MODULE__, :events}

  @doc "Runs `fun` and returns its result together with ordered trace events."
  @spec capture((-> result)) :: {result, [map()]} when result: var
  def capture(fun) when is_function(fun, 0) do
    previous = Process.get(@key, :unset)
    Process.put(@key, [])

    try do
      result = fun.()
      {result, Process.get(@key, []) |> Enum.reverse()}
    after
      restore(previous)
    end
  end

  @doc "Records an event when tracing is enabled on the current machine."
  @spec record(struct(), map()) :: :ok
  def record(%{debug_trace?: true}, event) when is_map(event) do
    Process.put(@key, [event | Process.get(@key, [])])
    :ok
  end

  def record(_gb, _event), do: :ok

  defp restore(:unset), do: Process.delete(@key)
  defp restore(previous), do: Process.put(@key, previous)
end
