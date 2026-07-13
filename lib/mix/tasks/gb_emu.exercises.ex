defmodule Mix.Tasks.GbEmu.Exercises do
  @moduledoc """
  Runs the branch-based GBEmulings learning track.

  ## Examples

      mix gb_emu.exercises start
      mix gb_emu.exercises check
      mix gb_emu.exercises next
      mix gb_emu.exercises status
      mix gb_emu.exercises hint
      mix gb_emu.exercises resume 048
      mix gb_emu.exercises list
      mix gb_emu.exercises show 048
  """

  use Mix.Task

  alias GbEmu.Exercises
  alias GbEmu.Exercises.Runner

  @shortdoc "Run the branch-based GBEmulings exercise track"
  @requirements []

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [list: :boolean, section: :string, show: :string, help: :boolean],
        aliases: [l: :list, s: :show, h: :help]
      )

    if invalid != [] do
      Mix.raise("unknown option(s): #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end

    exercises = Exercises.all()

    cond do
      opts[:help] -> print_help()
      id = opts[:show] -> show!(exercises, id)
      section = opts[:section] -> list(exercises, section)
      opts[:list] -> list(exercises)
      true -> dispatch(positional, exercises)
    end
  end

  defp dispatch([], exercises), do: print_overview(exercises)
  defp dispatch(["help"], _exercises), do: print_help()
  defp dispatch(["list"], exercises), do: list(exercises)
  defp dispatch(["list", section], exercises), do: list(exercises, section)
  defp dispatch(["show", id], exercises), do: show!(exercises, id)
  defp dispatch(["start"], exercises), do: start!(List.first(exercises).id)
  defp dispatch(["start", id], _exercises), do: start!(id)
  defp dispatch(["check"], _exercises), do: check!()
  defp dispatch(["next"], _exercises), do: next!()
  defp dispatch(["status"], _exercises), do: status!()
  defp dispatch(["hint"], exercises), do: hint_current!(exercises)
  defp dispatch(["hint", id], exercises), do: hint!(exercises, id)
  defp dispatch(["resume", id], _exercises), do: resume!(id)
  defp dispatch([id], exercises), do: show!(exercises, id)

  defp dispatch(args, _exercises) do
    Mix.raise("unknown command: #{Enum.join(args, " ")}; run `mix gb_emu.exercises help`")
  end

  defp start!(id) do
    case Runner.start(id) do
      {:ok, result} -> print_started(result)
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp check! do
    case Runner.check() do
      {:ok, result} ->
        Mix.shell().info(
          "\nExercise #{result.exercise.id} passes. Run `mix gb_emu.exercises next`."
        )

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp next! do
    case Runner.next() do
      {:ok, %{complete?: true} = result} ->
        Mix.shell().info("""

        GBEmulings complete.
        Final branch: #{result.branch}

        You have carried every passing exercise forward into the complete emulator.
        """)

      {:ok, result} ->
        print_started(result)

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp resume!(id) do
    case Runner.resume(id) do
      {:ok, result} ->
        Mix.shell().info("Resumed #{result.exercise.id} on #{result.branch}.")
        show_exercise(result.exercise)

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp status! do
    case Runner.status() do
      {:ok, status} ->
        next =
          if status.next, do: "#{status.next.id} #{status.next.title}", else: "track complete"

        Mix.shell().info("""
        Current branch: #{status.branch}
        Expected branch: #{status.expected_branch}
        Exercise: #{status.exercise.id} #{status.exercise.title}
        Next: #{next}
        """)

      {:error, reason} ->
        Mix.raise(reason)
    end
  end

  defp hint_current!(exercises) do
    case Runner.status() do
      {:ok, status} -> hint!(exercises, status.exercise.id, status.reference_commit)
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp hint!(exercises, id), do: hint!(exercises, id, "master")

  defp hint!(exercises, id, reference) do
    exercise = find!(exercises, id)

    Mix.shell().info("""
    Hints for #{exercise.id} #{exercise.title}:
    #{Enum.map_join(exercise.hints, "\n", &"  - #{&1}")}

    The completed implementation remains on the reference branch. Try the hints
    and focused checks before comparing it with
    `git show #{reference}:#{exercise.target.file}`.
    """)
  end

  defp print_started(result) do
    Mix.shell().info("""

    Switched to #{result.branch}
    Exercise #{result.exercise.id}: #{result.exercise.title}

    A committed failing scaffold is now in #{result.exercise.target.file}.
    Replace the TODO implementation, then run:

      mix gb_emu.exercises check
      mix gb_emu.exercises next
    """)
  end

  defp print_help do
    Mix.shell().info("""
    Usage:
      mix gb_emu.exercises start [ID]
      mix gb_emu.exercises check
      mix gb_emu.exercises next
      mix gb_emu.exercises status
      mix gb_emu.exercises hint [ID]
      mix gb_emu.exercises resume ID
      mix gb_emu.exercises list [SECTION]
      mix gb_emu.exercises show ID

    `start` creates a Git branch with one real implementation replaced by a
    TODO, later targets locked, and a failing exercise test. `check` validates
    the current solution in a disposable hydrated worktree. `next` commits the
    passing learner solution, creates the next branch from it, and installs the
    next failing scaffold.

    `next` stages and commits all changes on the dedicated exercise branch.
    Keep unrelated work out of GBEmulings branches.
    """)
  end

  defp print_overview(exercises) do
    sections = exercises |> Enum.map(& &1.section) |> Enum.uniq()
    first = List.first(exercises)

    Mix.shell().info("""
    GBEmulings: #{length(exercises)} cumulative branch exercises

    Sections:
    #{Enum.map_join(sections, "\n", &"  - #{&1}")}

    First exercise:
      #{first.id} #{first.title}

    Run `mix gb_emu.exercises start` to create and switch to the first broken branch.
    Run `mix gb_emu.exercises help` for the complete command loop.
    """)
  end

  defp list(exercises, section \\ nil) do
    sections =
      if section do
        [section]
      else
        exercises |> Enum.map(& &1.section) |> Enum.uniq()
      end

    Enum.each(sections, fn section ->
      entries = Enum.filter(exercises, &(&1.section == section))

      if entries == [] do
        Mix.raise("section #{inspect(section)} was not found")
      end

      Mix.shell().info("\n#{section}")
      Enum.each(entries, &Mix.shell().info("  #{&1.id} #{&1.title}"))
    end)
  end

  defp show!(exercises, id), do: exercises |> find!(id) |> show_exercise()

  defp show_exercise(exercise) do
    Mix.shell().info("""
    #{exercise.id} #{exercise.title}
    Section: #{exercise.section}

    Goal:
      #{exercise.goal}

    Scaffold target:
      #{exercise.target.file}
    #{target_description(exercise.target)}

    Checks:
    #{Enum.map_join(exercise.checks, "\n", &"  - #{Enum.join(&1, " ")}")}

    Hints:
    #{Enum.map_join(exercise.hints, "\n", &"  - #{&1}")}
    """)
  end

  defp find!(exercises, id) do
    Enum.find(exercises, &(&1.id == id)) || Mix.raise("exercise #{inspect(id)} was not found")
  end

  defp target_description(%{kind: :definition, anchor: anchor}) do
    "  Definition: #{anchor}"
  end

  defp target_description(%{kind: :branch, start: start, stop: stop} = target) do
    scope = if target[:after], do: "\n  After: #{target.after}", else: ""
    "  Branch starting at: #{start}\n  Before: #{stop}#{scope}"
  end

  defp target_description(%{kind: :file}), do: "  Entire file"
end
