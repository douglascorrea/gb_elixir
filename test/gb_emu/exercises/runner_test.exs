defmodule GbEmu.Exercises.RunnerTest do
  use ExUnit.Case, async: false

  alias GbEmu.Exercises.Runner

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "gbemulings-runner-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "lib"))

    File.write!(
      Path.join(root, "lib/demo.ex"),
      """
      defmodule Demo do
        def first, do: 1
        def second, do: 2
      end
      """
    )

    File.write!(
      Path.join(root, "check_first.exs"),
      """
      Code.require_file("lib/demo.ex")
      if Demo.first() != 1, do: System.halt(1)
      """
    )

    File.write!(
      Path.join(root, "check_second.exs"),
      """
      Code.require_file("lib/demo.ex")
      if Demo.second() != 2, do: System.halt(1)
      """
    )

    git!(root, ["init", "--initial-branch=master"])
    git!(root, ["config", "user.name", "GBEmulings Test"])
    git!(root, ["config", "user.email", "gbemulings@example.test"])
    git!(root, ["add", "--all"])
    git!(root, ["commit", "-m", "Initial solution"])

    exercises = [
      exercise("001", "First step", "def first, do: 1", "check_first.exs"),
      exercise("002", "Second step", "def second, do: 2", "check_second.exs")
    ]

    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root, exercises: exercises}
  end

  test "start creates and switches to a committed broken exercise branch", context do
    assert {:ok, result} =
             Runner.start("001", root: context.root, exercises: context.exercises)

    assert result.exercise.id == "001"
    assert result.branch == "codex/gbemulings/001-first-step"
    assert current_branch(context.root) == result.branch
    assert git_status(context.root) == ""

    source = File.read!(Path.join(context.root, "lib/demo.ex"))
    assert source =~ "TODO: exercise 001"
    assert source =~ ~s(raise "GBEmulings exercise 001 is not implemented")

    assert File.exists?(Path.join(context.root, "test/gb_emulings/001_exercise_test.exs"))
    assert {:error, message} = Runner.check(root: context.root, exercises: context.exercises)
    assert message =~ "exercise 001 still contains its TODO"
  end

  test "next commits the passing solution and scaffolds the next cumulative branch", context do
    assert {:ok, _result} =
             Runner.start("001", root: context.root, exercises: context.exercises)

    File.write!(
      Path.join(context.root, "lib/demo.ex"),
      """
      defmodule Demo do
        def first, do: 1
        def second, do: 2
      end
      """
    )

    assert {:ok, checked} = Runner.check(root: context.root, exercises: context.exercises)
    assert checked.exercise.id == "001"

    assert {:ok, result} = Runner.next(root: context.root, exercises: context.exercises)

    assert result.exercise.id == "002"
    assert result.branch == "codex/gbemulings/002-second-step"
    assert current_branch(context.root) == result.branch
    assert git_status(context.root) == ""

    source = File.read!(Path.join(context.root, "lib/demo.ex"))
    assert source =~ "def first, do: 1"
    assert source =~ "TODO: exercise 002"
    assert source =~ ~s(raise "GBEmulings exercise 002 is not implemented")

    log = git!(context.root, ["log", "--format=%s", "-3"])
    assert log =~ "Solve exercise 001: First step"
    assert log =~ "Start exercise 002: Second step"
  end

  test "start refuses to switch branches when the working tree is dirty", context do
    File.write!(Path.join(context.root, "notes.txt"), "uncommitted")

    assert {:error, message} =
             Runner.start("001", root: context.root, exercises: context.exercises)

    assert message =~ "working tree is not clean"
    assert current_branch(context.root) == "master"
  end

  test "next rejects changes to the generated exercise test", context do
    assert {:ok, _result} =
             Runner.start("001", root: context.root, exercises: context.exercises)

    File.write!(
      Path.join(context.root, "lib/demo.ex"),
      """
      defmodule Demo do
        def first, do: 1
        def second, do: 2
      end
      """
    )

    test_path = Path.join(context.root, "test/gb_emulings/001_exercise_test.exs")
    File.write!(test_path, File.read!(test_path) <> "\n# changed by learner\n")

    assert {:error, message} = Runner.next(root: context.root, exercises: context.exercises)
    assert message =~ "exercise test was changed"
    assert current_branch(context.root) == "codex/gbemulings/001-first-step"
  end

  test "resume switches back to an existing exercise branch and status identifies the next step",
       context do
    assert {:ok, started} =
             Runner.start("001", root: context.root, exercises: context.exercises)

    git!(context.root, ["switch", "master"])

    assert {:ok, resumed} =
             Runner.resume("001", root: context.root, exercises: context.exercises)

    assert resumed.branch == started.branch
    assert current_branch(context.root) == started.branch

    assert {:ok, status} = Runner.status(root: context.root, exercises: context.exercises)
    assert status.exercise.id == "001"
    assert status.next.id == "002"
    assert status.expected_branch == started.branch
    assert status.reference_commit != ""
  end

  test "next refuses to advance from a renamed exercise branch", context do
    assert {:ok, _result} =
             Runner.start("001", root: context.root, exercises: context.exercises)

    File.write!(
      Path.join(context.root, "lib/demo.ex"),
      """
      defmodule Demo do
        def first, do: 1
        def second, do: 2
      end
      """
    )

    git!(context.root, ["branch", "-m", "codex/renamed-exercise"])

    assert {:error, message} = Runner.next(root: context.root, exercises: context.exercises)
    assert message =~ "expected exercise branch"
    assert current_branch(context.root) == "codex/renamed-exercise"
  end

  defp exercise(id, title, anchor, check) do
    %{
      id: id,
      title: title,
      section: "test",
      goal: "Implement #{title}",
      files: ["lib/demo.ex"],
      checks: [["elixir", check]],
      hints: ["Keep the implementation small."],
      target: %{kind: :definition, file: "lib/demo.ex", anchor: anchor}
    }
  end

  defp current_branch(root), do: git!(root, ["branch", "--show-current"])
  defp git_status(root), do: git!(root, ["status", "--porcelain"])

  defp git!(root, args) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}):\n#{output}")
    end
  end
end
