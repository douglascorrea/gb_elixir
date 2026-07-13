defmodule GbEmu.Exercises.CatalogTest do
  use ExUnit.Case, async: true

  alias GbEmu.Exercises
  alias GbEmu.Exercises.Scaffolder

  test "all curriculum entries have a concrete scaffold target" do
    exercises = Exercises.all()

    assert length(exercises) == 110

    for exercise <- exercises do
      assert %{file: file} = exercise.target
      assert is_binary(file) and file != ""
      assert valid_target?(exercise.target)
      assert is_list(exercise.hints) and exercise.hints != []
      assert Enum.all?(exercise.hints, &is_binary/1)
      assert Enum.all?(exercise.checks, &valid_command?/1)
      assert {:ok, plan} = Scaffolder.plan(File.cwd!(), exercise)
      assert {:ok, _quoted} = Code.string_to_quoted(plan.contents)
    end
  end

  test "no two exercises replace the same anchored definition" do
    targets = Enum.map(Exercises.all(), &target_identity(&1.target))

    assert Enum.uniq(targets) == targets
  end

  defp valid_command?([executable | args]) do
    is_binary(executable) and executable != "" and Enum.all?(args, &is_binary/1)
  end

  defp valid_command?(_command), do: false

  defp valid_target?(%{kind: :definition, anchor: anchor}),
    do: is_binary(anchor) and anchor != ""

  defp valid_target?(%{kind: :branch, start: start, stop: stop}),
    do: is_binary(start) and start != "" and is_binary(stop) and stop != ""

  defp valid_target?(_target), do: false

  defp target_identity(%{kind: :definition, file: file, anchor: anchor}),
    do: {file, :definition, anchor}

  defp target_identity(%{kind: :branch, file: file, start: start, stop: stop} = target),
    do: {file, :branch, target[:after], start, stop}
end
