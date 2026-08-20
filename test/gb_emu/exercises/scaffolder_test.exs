defmodule GbEmu.Exercises.ScaffolderTest do
  use ExUnit.Case, async: true

  alias GbEmu.Exercises.Scaffolder

  test "replaces one branch body while preserving adjacent branches" do
    root =
      Path.join(
        System.tmp_dir!(),
        "gbemulings-scaffolder-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "lib"))

    File.write!(
      Path.join(root, "lib/demo.ex"),
      """
      defmodule Demo do
        def value(kind) do
          case kind do
            :one -> 1
            :two ->
              2
            :three -> 3
          end
        end
      end
      """
    )

    exercise = %{
      id: "021",
      title: "Implement the second branch",
      target: %{
        kind: :branch,
        file: "lib/demo.ex",
        start: ":two ->",
        stop: ":three ->"
      }
    }

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, plan} = Scaffolder.plan(root, exercise)
    assert plan.contents =~ ":one -> 1"
    assert plan.contents =~ ":two ->\n        # TODO: exercise 021"
    assert plan.contents =~ ~s(raise "GBEmulings exercise 021 is not implemented")
    assert plan.contents =~ ":three -> 3"
    refute plan.contents =~ "\n      2\n"
  end

  test "scopes repeated branch anchors after a definition" do
    root =
      Path.join(
        System.tmp_dir!(),
        "gbemulings-scaffolder-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "lib"))

    File.write!(
      Path.join(root, "lib/demo.ex"),
      """
      defmodule Demo do
        def first(value) do
          case value do
            :target -> :first
            :stop -> :done
          end
        end

        def second(value) do
          case value do
            :target -> :second
            :stop -> :done
          end
        end
      end
      """
    )

    exercise = %{
      id: "022",
      title: "Scope a repeated branch",
      target: %{
        kind: :branch,
        file: "lib/demo.ex",
        after: "def second(value) do",
        start: ":target ->",
        stop: ":stop ->"
      }
    }

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:ok, plan} = Scaffolder.plan(root, exercise)
    assert plan.contents =~ ":target -> :first"
    refute plan.contents =~ ":target -> :second"
    assert plan.contents =~ "TODO: exercise 022"
  end

  test "keeps one-line branches formatter-stable and removes their scaffold comment on hydration" do
    root = temporary_root!()
    path = Path.join(root, "lib/demo.ex")

    solution =
      """
      defmodule Demo do
        def value(kind) do
          case kind do
            :one -> 1
            :two -> 2
            :three -> 3
          end
        end
      end
      """

    File.write!(path, solution)

    exercise = %{
      id: "025",
      title: "Implement a compact branch",
      target: %{
        kind: :branch,
        file: "lib/demo.ex",
        start: ":two ->",
        stop: ":three ->"
      }
    }

    assert {:ok, pending} = Scaffolder.plan(root, exercise, :pending)
    assert pending.contents =~ "# GBEmulings exercise 025 is locked until its turn"
    assert pending.contents =~ ":two -> raise(\"locked 025\")"

    formatted = pending.contents |> Code.format_string!() |> IO.iodata_to_binary()
    assert String.trim_trailing(pending.contents) == formatted

    File.write!(path, pending.contents)

    assert {:ok, [restored]} =
             Scaffolder.hydration_plan(root, [exercise], %{"lib/demo.ex" => solution})

    assert restored.contents == solution
  end

  test "reports malformed Elixir source without crashing" do
    root =
      Path.join(
        System.tmp_dir!(),
        "gbemulings-scaffolder-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "lib"))
    File.write!(Path.join(root, "lib/demo.ex"), "defmodule Demo do\n  def broken(\nend\n")

    exercise = %{
      id: "023",
      title: "Malformed source",
      target: %{kind: :definition, file: "lib/demo.ex", anchor: "def broken("}
    }

    on_exit(fn -> File.rm_rf!(root) end)

    assert {:error, message} = Scaffolder.plan(root, exercise)
    assert message =~ "could not scaffold exercise 023"
  end

  test "locks a future definition while preserving the exact anchor for activation" do
    root = temporary_root!()
    path = Path.join(root, "lib/demo.ex")

    File.write!(
      path,
      """
      defmodule Demo do
        def value(input), do: input + 1
      end
      """
    )

    exercise = %{
      id: "024",
      title: "Implement value",
      target: %{kind: :definition, file: "lib/demo.ex", anchor: "def value(input), do:"}
    }

    assert {:ok, pending} = Scaffolder.plan(root, exercise, :pending)
    assert pending.contents =~ "def value(input), do:"
    assert pending.contents =~ "GBEmulings exercise 024 is locked until its turn"
    refute pending.contents =~ "TODO: exercise 024"

    File.write!(path, pending.contents)

    assert {:ok, active} = Scaffolder.plan(root, exercise)
    assert active.contents =~ "# TODO: exercise 024 - Implement value"
    assert active.contents =~ "def value(input), do:"
    assert active.contents =~ "raise(\"TODO 024\")"
  end

  test "builds one active scaffold and locks every later target" do
    root = temporary_root!()
    path = Path.join(root, "lib/demo.ex")

    File.write!(
      path,
      """
      defmodule Demo do
        def first, do: 1
        def second, do: 2
        def third, do: 3
      end
      """
    )

    exercises = [
      definition_exercise("001", "First", "def first, do:"),
      definition_exercise("002", "Second", "def second, do:"),
      definition_exercise("003", "Third", "def third, do:")
    ]

    assert {:ok, [plan]} = Scaffolder.curriculum_plan(root, exercises, "001")
    assert plan.contents =~ "TODO: exercise 001"
    assert plan.contents =~ "exercise 002 is locked until its turn"
    assert plan.contents =~ "exercise 003 is locked until its turn"
    refute plan.contents =~ "def second, do: 2"
    refute plan.contents =~ "def third, do: 3"
    assert {:ok, _quoted} = Code.string_to_quoted(plan.contents)
  end

  test "hydrates future solutions without replacing learner code" do
    root = temporary_root!()
    path = Path.join(root, "lib/demo.ex")

    File.write!(
      path,
      """
      defmodule Demo do
        def first, do: 42
        def second, do: raise("GBEmulings exercise 002 is locked until its turn")
      end
      """
    )

    reference =
      """
      defmodule Demo do
        def first, do: 1
        def second, do: 2
      end
      """

    exercise = definition_exercise("002", "Second", "def second, do:")

    assert {:ok, [plan]} =
             Scaffolder.hydration_plan(root, [exercise], %{"lib/demo.ex" => reference})

    assert plan.contents =~ "def first, do: 42"
    assert plan.contents =~ "def second, do: 2"
    refute plan.contents =~ "locked until its turn"
  end

  defp temporary_root! do
    root =
      Path.join(
        System.tmp_dir!(),
        "gbemulings-scaffolder-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "lib"))
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp definition_exercise(id, title, anchor) do
    %{
      id: id,
      title: title,
      target: %{kind: :definition, file: "lib/demo.ex", anchor: anchor}
    }
  end
end
