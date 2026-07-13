defmodule GbEmu.Exercises do
  @moduledoc "Loads the ordered GBEmulings curriculum and branch scaffolds."

  @manifest Path.expand("../../exercises/manifest.exs", __DIR__)
  @targets Path.expand("../../exercises/targets.exs", __DIR__)

  def all do
    manifest = evaluate!(@manifest)
    targets = evaluate!(@targets)

    Enum.map(manifest, fn exercise ->
      target = Map.fetch!(targets, exercise.id)

      exercise
      |> Map.merge(target)
      |> Map.put_new(:hints, default_hints(exercise))
    end)
  end

  def fetch(id) do
    case Enum.find(all(), &(&1.id == id)) do
      nil -> :error
      exercise -> {:ok, exercise}
    end
  end

  defp evaluate!(path) do
    {value, _binding} = Code.eval_file(path)
    value
  end

  defp default_hints(exercise) do
    [
      exercise.goal,
      "Start with #{List.first(exercise.files)} and keep the change limited to this exercise."
    ]
  end
end
