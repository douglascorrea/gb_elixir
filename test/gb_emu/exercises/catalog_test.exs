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
      assert plan.contents =~ Scaffolder.marker(exercise)

      if Path.extname(plan.relative_path) in [".ex", ".exs"] do
        assert {:ok, _quoted} = Code.string_to_quoted(plan.contents)
        assert_formatted(plan.contents, plan.relative_path)
      end
    end
  end

  test "the first cumulative branch has one TODO and locks all future implementations" do
    exercises = Exercises.all()

    assert {:ok, plans} = Scaffolder.curriculum_plan(File.cwd!(), exercises, "001")

    contents = Enum.map_join(plans, "\n", & &1.contents)

    assert length(Regex.scan(~r/TODO: exercise \d{3}/, contents)) == 1
    assert contents =~ "TODO: exercise 001"

    for exercise <- Enum.drop(exercises, 1) do
      assert contents =~ Scaffolder.locked_message(exercise)
    end

    for plan <- plans, Path.extname(plan.relative_path) in [".ex", ".exs"] do
      assert {:ok, _quoted} = Code.string_to_quoted(plan.contents)
      assert_formatted(plan.contents, plan.relative_path)
    end
  end

  test "all 110 cumulative transitions can restore one solution and activate the next" do
    exercises = Exercises.all()

    root =
      Path.join(
        System.tmp_dir!(),
        "gbemulings-catalog-#{System.unique_integer([:positive, :monotonic])}"
      )

    solutions =
      exercises
      |> Enum.map(& &1.target.file)
      |> Enum.uniq()
      |> Map.new(fn file -> {file, File.read!(Path.join(File.cwd!(), file))} end)

    for {file, source} <- solutions do
      path = Path.join(root, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, source)
    end

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, plans} = Scaffolder.curriculum_plan(root, exercises, "001")
    write_plans!(plans)

    exercises
    |> Enum.with_index()
    |> Enum.each(fn {exercise, index} ->
      source = File.read!(Path.join(root, exercise.target.file))
      assert source =~ Scaffolder.marker(exercise)

      assert {:ok, solved_plans} =
               Scaffolder.hydration_plan(root, [exercise], solutions)

      write_plans!(solved_plans)

      case Enum.at(exercises, index + 1) do
        nil ->
          :ok

        next ->
          assert {:ok, next_plan} = Scaffolder.plan(root, next)
          File.write!(next_plan.path, next_plan.contents)
      end
    end)

    for {file, solution} <- solutions do
      assert File.read!(Path.join(root, file)) == solution
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

  defp valid_target?(%{kind: :file}), do: true

  defp valid_target?(_target), do: false

  defp target_identity(%{kind: :definition, file: file, anchor: anchor}),
    do: {file, :definition, anchor}

  defp target_identity(%{kind: :branch, file: file, start: start, stop: stop} = target),
    do: {file, :branch, target[:after], start, stop}

  defp target_identity(%{kind: :file, file: file}), do: {file, :file}

  defp write_plans!(plans) do
    Enum.each(plans, fn plan -> File.write!(plan.path, plan.contents) end)
  end

  defp assert_formatted(source, path) do
    {formatter, _opts} = Mix.Tasks.Format.formatter_for_file(path)
    formatted = source |> formatter.() |> IO.iodata_to_binary()
    assert source == formatted
  end
end
