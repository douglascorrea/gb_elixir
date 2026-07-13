defmodule GbEmu.Exercises.Runner do
  @moduledoc """
  Drives the cumulative, branch-based GBEmulings exercise workflow.

  Each scaffold branch is committed in an intentionally failing state. After
  the learner fixes it, `next/1` checks and commits that solution before
  creating the next branch from it.
  """

  alias GbEmu.Exercises.Scaffolder

  @state_path ".gbemulings/current.json"
  @branch_prefix "codex/gbemulings"

  def start(id, opts \\ []) do
    root = root(opts)
    exercises = exercises(opts)

    with {:ok, exercise} <- fetch_exercise(exercises, id),
         :ok <- ensure_git_repository(root),
         :ok <- ensure_clean(root),
         {:ok, reference} <- git(root, ["rev-parse", "HEAD"]),
         branch = branch_name(exercise, opts),
         :ok <- ensure_branch_missing(root, branch),
         {:ok, plans} <- Scaffolder.curriculum_plan(root, exercises, exercise.id),
         :ok <- create_scaffold_branch(root, reference, branch, exercise, reference, plans) do
      {:ok, result(exercise, branch)}
    end
  end

  def check(opts \\ []) do
    root = root(opts)
    exercises = exercises(opts)

    with {:ok, state} <- read_state(root),
         {:ok, exercise} <- fetch_exercise(exercises, state["exercise_id"]),
         {:ok, branch} <- git(root, ["branch", "--show-current"]),
         :ok <- ensure_expected_branch(branch, state["branch"]),
         :ok <- ensure_test_unchanged(root, exercise),
         :ok <- ensure_todo_removed(root, exercise),
         :ok <- ensure_formatted(root),
         :ok <- run_hydrated_checks(root, exercises, exercise, state) do
      {:ok, result(exercise, state["branch"])}
    end
  end

  def next(opts \\ []) do
    root = root(opts)
    exercises = exercises(opts)

    with {:ok, state} <- read_state(root),
         {:ok, current} <- fetch_exercise(exercises, state["exercise_id"]),
         {:ok, branch} <- git(root, ["branch", "--show-current"]),
         :ok <- ensure_expected_branch(branch, state["branch"]),
         {:ok, _checked} <- check(Keyword.put(opts, :root, root)),
         :ok <- commit_solution(root, current) do
      case next_exercise(exercises, current.id) do
        nil ->
          {:ok, result(current, state["branch"]) |> Map.put(:complete?, true)}

        exercise ->
          branch = branch_name(exercise, opts)

          with :ok <- ensure_branch_missing(root, branch),
               {:ok, plan} <- Scaffolder.plan(root, exercise),
               {:ok, parent} <- git(root, ["rev-parse", "HEAD"]),
               :ok <-
                 create_scaffold_branch(
                   root,
                   parent,
                   branch,
                   exercise,
                   state["reference_commit"],
                   [plan]
                 ) do
            {:ok, result(exercise, branch)}
          end
      end
    end
  end

  def resume(id, opts \\ []) do
    root = root(opts)
    exercises = exercises(opts)

    with {:ok, exercise} <- fetch_exercise(exercises, id),
         :ok <- ensure_git_repository(root),
         :ok <- ensure_clean(root),
         branch = branch_name(exercise, opts),
         :ok <- ensure_branch_exists(root, branch),
         {:ok, state} <- read_state(root, branch),
         :ok <- ensure_state_matches(state, exercise, branch),
         :ok <- git_ok(root, ["switch", branch]) do
      {:ok, result(exercise, branch)}
    end
  end

  def status(opts \\ []) do
    root = root(opts)
    exercises = exercises(opts)

    with {:ok, state} <- read_state(root),
         {:ok, exercise} <- fetch_exercise(exercises, state["exercise_id"]),
         {:ok, branch} <- git(root, ["branch", "--show-current"]) do
      {:ok,
       result(exercise, branch)
       |> Map.put(:expected_branch, state["branch"])
       |> Map.put(:reference_commit, state["reference_commit"])
       |> Map.put(:next, next_exercise(exercises, exercise.id))}
    end
  end

  def branch_name(exercise, opts \\ []) do
    prefix = Keyword.get(opts, :branch_prefix, @branch_prefix)
    "#{prefix}/#{exercise.id}-#{slug(exercise.title)}"
  end

  defp create_scaffold_branch(root, parent, branch, exercise, reference, plans) do
    with :ok <-
           with_temporary_worktree(root, parent, fn worktree ->
             with :ok <- write_scaffold(worktree, exercise, branch, reference, plans),
                  :ok <- commit_scaffold(worktree, exercise),
                  {:ok, commit} <- git(worktree, ["rev-parse", "HEAD"]),
                  :ok <- git_ok(root, ["branch", branch, commit]) do
               :ok
             end
           end) do
      git_ok(root, ["switch", branch])
    end
  end

  defp write_scaffold(root, exercise, branch, reference, plans) do
    state_path = Path.join(root, @state_path)
    test_path = exercise_test_path(root, exercise)

    with :ok <- mkdir(Path.dirname(state_path)),
         :ok <- mkdir(Path.dirname(test_path)),
         :ok <- write_plans(root, plans),
         :ok <- write(state_path, state_json(exercise, branch, reference)),
         :ok <- write(test_path, exercise_test(exercise)) do
      :ok
    end
  end

  defp commit_scaffold(root, exercise) do
    with :ok <- git_ok(root, ["add", "--all"]),
         :ok <-
           git_ok(root, [
             "commit",
             "--no-verify",
             "-m",
             "Start exercise #{exercise.id}: #{exercise.title}"
           ]) do
      :ok
    end
  end

  defp commit_solution(root, exercise) do
    with {:ok, status} <- git(root, ["status", "--porcelain"]) do
      if status == "" do
        :ok
      else
        with :ok <- git_ok(root, ["add", "--all"]),
             :ok <-
               git_ok(root, ["commit", "-m", "Solve exercise #{exercise.id}: #{exercise.title}"]) do
          :ok
        end
      end
    end
  end

  defp ensure_todo_removed(root, exercise) do
    path = Path.join(root, exercise.target.file)
    marker = Scaffolder.marker(exercise)
    not_implemented = Scaffolder.not_implemented_message(exercise)

    with {:ok, source} <- File.read(path) do
      cond do
        String.contains?(source, marker) ->
          {:error, "exercise #{exercise.id} still contains its TODO in #{exercise.target.file}"}

        String.contains?(source, not_implemented) ->
          {:error,
           "exercise #{exercise.id} still raises its not-implemented error in #{exercise.target.file}"}

        true ->
          :ok
      end
    else
      {:error, reason} -> {:error, "could not read #{exercise.target.file}: #{inspect(reason)}"}
    end
  end

  defp ensure_formatted(root) do
    if File.exists?(Path.join(root, "mix.exs")) do
      case System.cmd("mix", ["format", "--check-formatted", "--no-compile"],
             cd: root,
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          print_command_output(output)
          :ok

        {output, status} ->
          print_command_output(output)
          {:error, "exercise source is not formatted (#{status}): mix format --check-formatted"}
      end
    else
      :ok
    end
  end

  defp run_hydrated_checks(root, exercises, exercise, state) do
    future = exercises_after(exercises, exercise.id)

    with_temporary_worktree(root, "HEAD", fn worktree ->
      with :ok <- copy_changed_files(root, worktree),
           {:ok, solutions} <- solution_sources(root, future, state["reference_commit"]),
           {:ok, plans} <- Scaffolder.hydration_plan(worktree, future, solutions),
           :ok <- write_plans(worktree, plans),
           :ok <- run_checks(worktree, exercise, root) do
        :ok
      end
    end)
  end

  defp run_checks(check_root, exercise, source_root) do
    marker_test = exercise_test_relative_path(exercise)

    commands =
      if File.exists?(Path.join(check_root, "mix.exs")) do
        [["mix", "test", marker_test] | exercise.checks]
      else
        exercise.checks
      end

    normalized_commands = Enum.map(commands, &normalize_command/1)

    with :ok <- prepare_grader_builds(source_root, normalized_commands) do
      Enum.reduce_while(normalized_commands, :ok, fn [executable | args] = command, :ok ->
        case System.cmd(executable, args,
               cd: check_root,
               env: command_environment(command, source_root),
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            print_command_output(output)
            {:cont, :ok}

          {output, status} ->
            print_command_output(output)

            {:halt,
             {:error,
              "exercise #{exercise.id} check failed (#{status}): #{Enum.join([executable | args], " ")}"}}
        end
      end)
    end
  end

  defp ensure_test_unchanged(root, exercise) do
    test_path = exercise_test_relative_path(exercise)

    with {:ok, changed} <- changed_files(root) do
      if test_path in changed do
        {:error, "the exercise test was changed; restore #{test_path} and fix the implementation"}
      else
        :ok
      end
    end
  end

  defp changed_files(root) do
    commands = [
      ["diff", "--name-only"],
      ["diff", "--cached", "--name-only"],
      ["ls-files", "--others", "--exclude-standard"]
    ]

    Enum.reduce_while(commands, {:ok, []}, fn args, {:ok, files} ->
      case git(root, args) do
        {:ok, output} ->
          names = if output == "", do: [], else: String.split(output, "\n")
          {:cont, {:ok, Enum.uniq(files ++ names)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp read_state(root) do
    path = Path.join(root, @state_path)

    with {:ok, contents} <- File.read(path),
         {:ok, state} <- Jason.decode(contents) do
      {:ok, state}
    else
      {:error, :enoent} ->
        {:error, "no active GBEmulings exercise; run `mix gb_emu.exercises start` first"}

      {:error, reason} ->
        {:error, "could not read GBEmulings state: #{inspect(reason)}"}
    end
  end

  defp read_state(root, branch) do
    with {:ok, contents} <- git(root, ["show", "#{branch}:#{@state_path}"]),
         {:ok, state} <- Jason.decode(contents) do
      {:ok, state}
    else
      {:error, reason} ->
        {:error, "could not read GBEmulings state from #{branch}: #{inspect(reason)}"}
    end
  end

  defp state_json(exercise, branch, reference) do
    Jason.encode!(
      %{
        exercise_id: exercise.id,
        branch: branch,
        reference_commit: reference
      },
      pretty: true
    ) <> "\n"
  end

  defp exercise_test(exercise) do
    module_suffix = String.to_integer(exercise.id)
    relative_path = exercise.target.file
    marker = Scaffolder.marker(exercise)
    not_implemented = Scaffolder.not_implemented_message(exercise)

    """
    defmodule GbEmu.GBEmulings.Exercise#{module_suffix}Test do
      use ExUnit.Case, async: true

      @root Path.expand("../..", __DIR__)
      @source Path.join(@root, #{inspect(relative_path)})

      test #{inspect("exercise #{exercise.id} no longer contains its scaffold")} do
        source = File.read!(@source)

        refute source =~ #{inspect(marker)}
        refute source =~ #{inspect(not_implemented)}
      end
    end
    """
  end

  defp exercise_test_path(root, exercise) do
    Path.join(root, exercise_test_relative_path(exercise))
  end

  defp exercise_test_relative_path(exercise) do
    "test/gb_emulings/#{exercise.id}_exercise_test.exs"
  end

  defp next_exercise(exercises, id) do
    case Enum.find_index(exercises, &(&1.id == id)) do
      nil -> nil
      index -> Enum.at(exercises, index + 1)
    end
  end

  defp exercises_after(exercises, id) do
    case Enum.find_index(exercises, &(&1.id == id)) do
      nil -> []
      index -> Enum.drop(exercises, index + 1)
    end
  end

  defp fetch_exercise(exercises, id) do
    case Enum.find(exercises, &(&1.id == id)) do
      nil -> {:error, "exercise #{inspect(id)} was not found"}
      exercise -> {:ok, exercise}
    end
  end

  defp ensure_git_repository(root) do
    case git(root, ["rev-parse", "--is-inside-work-tree"]) do
      {:ok, "true"} -> :ok
      _ -> {:error, "#{root} is not a Git working tree"}
    end
  end

  defp ensure_clean(root) do
    with {:ok, status} <- git(root, ["status", "--porcelain"]) do
      if status == "" do
        :ok
      else
        {:error, "working tree is not clean; commit or stash changes before starting an exercise"}
      end
    end
  end

  defp ensure_branch_missing(root, branch) do
    case branch_exists?(root, branch) do
      {:ok, false} -> :ok
      {:ok, true} -> {:error, "branch #{branch} already exists; use the resume command"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_branch_exists(root, branch) do
    case branch_exists?(root, branch) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, "branch #{branch} does not exist; use the start command"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp branch_exists?(root, branch) do
    case System.cmd(
           "git",
           ["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"],
           cd: root,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> {:ok, true}
      {_output, 1} -> {:ok, false}
      {output, status} -> {:error, "could not inspect branch #{branch} (#{status}): #{output}"}
    end
  end

  defp ensure_state_matches(state, exercise, branch) do
    if state["exercise_id"] == exercise.id and state["branch"] == branch do
      :ok
    else
      {:error, "branch #{branch} does not contain the expected exercise state"}
    end
  end

  defp ensure_expected_branch(branch, branch), do: :ok

  defp ensure_expected_branch(actual, expected) do
    {:error, "expected exercise branch #{expected}, but the current branch is #{actual}"}
  end

  defp normalize_command(command) when is_binary(command), do: OptionParser.split(command)
  defp normalize_command(command) when is_list(command), do: command

  defp command_environment(command, source_root) do
    mix_env = effective_mix_env(command)

    [
      {"MIX_DEPS_PATH", Path.join(source_root, "deps")},
      {"MIX_BUILD_PATH", grader_build_path(source_root, mix_env)}
    ]
  end

  defp prepare_grader_builds(source_root, commands) do
    commands
    |> Enum.map(&effective_mix_env/1)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn mix_env, :ok ->
      build_path = grader_build_path(source_root, mix_env)

      case reset_project_build(build_path) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp grader_build_path(source_root, mix_env) do
    Path.join([source_root, "_build", "gbemulings", mix_env])
  end

  defp reset_project_build(build_path) do
    app = Mix.Project.config() |> Keyword.fetch!(:app) |> Atom.to_string()

    [Path.join([build_path, "lib", app]), Path.join(build_path, "consolidated")]
    |> Enum.reduce_while(:ok, fn path, :ok ->
      case File.rm_rf(path) do
        {:ok, _paths} ->
          {:cont, :ok}

        {:error, reason, failed_path} ->
          {:halt, {:error, "could not reset grader build at #{failed_path}: #{inspect(reason)}"}}
      end
    end)
  end

  defp effective_mix_env(["env" | args]) do
    {assignments, command} = Enum.split_while(args, &String.contains?(&1, "="))

    Enum.find_value(assignments, fn assignment ->
      case String.split(assignment, "=", parts: 2) do
        ["MIX_ENV", value] -> value
        _ -> nil
      end
    end) || effective_mix_env(command)
  end

  defp effective_mix_env(["mix", task | _args]) when task in ["test", "precommit"], do: "test"
  defp effective_mix_env(_command), do: System.get_env("MIX_ENV") || "dev"

  defp print_command_output(""), do: :ok
  defp print_command_output(output), do: IO.write(output)

  defp mkdir(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, "could not create #{path}: #{inspect(reason)}"}
    end
  end

  defp write(path, contents) do
    case File.write(path, contents) do
      :ok -> :ok
      {:error, reason} -> {:error, "could not write #{path}: #{inspect(reason)}"}
    end
  end

  defp write_plans(root, plans) do
    Enum.reduce_while(plans, :ok, fn plan, :ok ->
      path = Path.join(root, plan.relative_path)

      with :ok <- mkdir(Path.dirname(path)),
           :ok <- write(path, plan.contents) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp solution_sources(root, exercises, reference) do
    exercises
    |> Enum.map(& &1.target.file)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, %{}}, fn file, {:ok, sources} ->
      case git(root, ["show", "#{reference}:#{file}"]) do
        {:ok, source} -> {:cont, {:ok, Map.put(sources, file, source <> "\n")}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp copy_changed_files(source_root, target_root) do
    with {:ok, files} <- changed_files(source_root) do
      Enum.reduce_while(files, :ok, fn relative_path, :ok ->
        source = Path.join(source_root, relative_path)
        target = Path.join(target_root, relative_path)

        result =
          case File.lstat(source) do
            {:ok, %{type: :directory}} ->
              with :ok <- mkdir(Path.dirname(target)),
                   {:ok, _paths} <- File.cp_r(source, target) do
                :ok
              end

            {:ok, _stat} ->
              with :ok <- mkdir(Path.dirname(target)), do: File.cp(source, target)

            {:error, :enoent} ->
              case File.rm_rf(target) do
                {:ok, _paths} -> :ok
                {:error, reason, _path} -> {:error, reason}
              end

            {:error, reason} ->
              {:error, reason}
          end

        case result do
          :ok ->
            {:cont, :ok}

          {:error, reason} ->
            {:halt, {:error, "could not copy #{relative_path}: #{inspect(reason)}"}}
        end
      end)
    end
  end

  defp add_temporary_worktree(root, reference) do
    path =
      Path.join(
        System.tmp_dir!(),
        "gbemulings-worktree-#{System.unique_integer([:positive, :monotonic])}"
      )

    case git_ok(root, ["worktree", "add", "--detach", path, reference]) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_temporary_worktree(root, reference, callback) do
    case add_temporary_worktree(root, reference) do
      {:ok, worktree} ->
        outcome =
          try do
            callback.(worktree)
          rescue
            exception ->
              {:error, "temporary worktree operation failed: #{Exception.message(exception)}"}
          catch
            kind, reason ->
              {:error, "temporary worktree operation #{kind}: #{inspect(reason)}"}
          end

        merge_cleanup(outcome, remove_temporary_worktree(root, worktree))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_temporary_worktree(root, path) do
    git_result = git(root, ["worktree", "remove", "--force", path])
    file_result = File.rm_rf(path)

    case {git_result, file_result} do
      {{:ok, _output}, {:ok, _paths}} ->
        :ok

      {{:error, reason}, _file_result} ->
        _ = git(root, ["worktree", "prune"])
        {:error, "temporary worktree cleanup failed: #{reason}"}

      {_git_result, {:error, reason, failed_path}} ->
        {:error, "temporary worktree cleanup failed at #{failed_path}: #{inspect(reason)}"}
    end
  end

  defp merge_cleanup(outcome, :ok), do: outcome
  defp merge_cleanup(:ok, {:error, cleanup}), do: {:error, cleanup}

  defp merge_cleanup({:error, reason}, {:error, cleanup}) do
    {:error, "#{reason}; #{cleanup}"}
  end

  defp git_ok(root, args) do
    case git(root, args) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp git(root, args) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {output, status} ->
        {:error, "git #{Enum.join(args, " ")} failed (#{status}): #{String.trim(output)}"}
    end
  end

  defp result(exercise, branch), do: %{exercise: exercise, branch: branch, complete?: false}

  defp slug(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp root(opts), do: opts |> Keyword.get(:root, File.cwd!()) |> Path.expand()

  defp exercises(opts) do
    Keyword.get_lazy(opts, :exercises, fn -> GbEmu.Exercises.all() end)
  end
end
