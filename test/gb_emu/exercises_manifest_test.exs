defmodule GbEmu.ExercisesManifestTest do
  use ExUnit.Case, async: true

  @manifest Path.expand("../../exercises/manifest.exs", __DIR__)

  test "GBEmulings manifest is granular, ordered, and complete enough" do
    exercises = manifest()

    assert length(exercises) >= 100
    assert Enum.map(exercises, & &1.id) == exercises |> Enum.map(& &1.id) |> Enum.sort()
    assert exercises |> Enum.map(& &1.id) |> Enum.uniq() |> length() == length(exercises)
    assert List.first(exercises).section == "elixir-fundamentals"
    assert List.last(exercises).section == "docs-and-release"
  end

  test "each exercise declares the fields needed by the Mix task" do
    for exercise <- manifest() do
      assert %{id: id, section: section, title: title, goal: goal, files: files, checks: checks} =
               exercise

      assert id =~ ~r/^\d{3}$/
      assert is_binary(section) and section != ""
      assert is_binary(title) and title != ""
      assert is_binary(goal) and goal != ""
      assert is_list(files) and files != []
      assert Enum.all?(files, &is_binary/1)
      assert is_list(checks) and checks != []
      assert Enum.all?(checks, &is_binary/1)
    end
  end

  defp manifest do
    {exercises, _binding} = Code.eval_file(@manifest)
    exercises
  end
end
