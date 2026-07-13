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
end
