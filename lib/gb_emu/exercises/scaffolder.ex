defmodule GbEmu.Exercises.Scaffolder do
  @moduledoc false

  @definition_kinds [:def, :defp]

  def plan(root, exercise, mode \\ :active) when mode in [:active, :pending] do
    path = Path.join(root, exercise.target.file)

    with {:ok, source} <- File.read(path),
         {:ok, contents} <- rewrite(source, exercise, mode) do
      {:ok, build_plan(path, exercise.target.file, contents)}
    else
      {:error, reason} -> {:error, "could not scaffold exercise #{exercise.id}: #{reason}"}
    end
  end

  def curriculum_plan(root, exercises, active_id) do
    case Enum.find_index(exercises, &(&1.id == active_id)) do
      nil ->
        {:error, "exercise #{inspect(active_id)} was not found"}

      index ->
        exercises
        |> Enum.drop(index)
        |> plans_for_files(root, fn source, file_exercises ->
          file_exercises
          |> Enum.reverse()
          |> Enum.reduce_while({:ok, source}, fn exercise, {:ok, contents} ->
            mode = if exercise.id == active_id, do: :active, else: :pending

            case rewrite(contents, exercise, mode) do
              {:ok, rewritten} -> {:cont, {:ok, rewritten}}
              {:error, reason} -> {:halt, {:error, exercise_error(exercise, reason)}}
            end
          end)
        end)
    end
  end

  def hydration_plan(root, exercises, solution_sources) do
    plans_for_files(exercises, root, fn source, file_exercises ->
      file = hd(file_exercises).target.file

      with {:ok, solution} <- Map.fetch(solution_sources, file) do
        file_exercises
        |> Enum.reverse()
        |> Enum.reduce_while({:ok, source}, fn exercise, {:ok, contents} ->
          case restore(contents, solution, exercise.target) do
            {:ok, restored} -> {:cont, {:ok, restored}}
            {:error, reason} -> {:halt, {:error, exercise_error(exercise, reason)}}
          end
        end)
      else
        :error -> {:error, "reference solution for #{file} was not provided"}
      end
    end)
  end

  def marker(%{id: id}), do: "TODO: exercise #{id}"

  def not_implemented_message(%{id: id}) do
    "GBEmulings exercise #{id} is not implemented"
  end

  def locked_message(%{id: id}) do
    "GBEmulings exercise #{id} is locked until its turn"
  end

  defp plans_for_files(exercises, root, transform) do
    exercises
    |> Enum.group_by(& &1.target.file)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, []}, fn {file, file_exercises}, {:ok, plans} ->
      path = Path.join(root, file)

      with {:ok, source} <- File.read(path),
           {:ok, contents} <- transform.(source, file_exercises) do
        {:cont, {:ok, [build_plan(path, file, contents) | plans]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, plans} -> {:ok, Enum.reverse(plans)}
      error -> error
    end
  end

  defp rewrite(source, %{target: %{kind: :definition} = target} = exercise, mode) do
    with {:ok, definition} <- locate_definition(source, target.anchor) do
      replace_definition(source, definition, exercise, mode)
    end
  end

  defp rewrite(source, %{target: %{kind: :branch} = target} = exercise, mode) do
    replace_branch(source, target, exercise, mode)
  end

  defp rewrite(_source, %{target: %{kind: :file}} = exercise, :active) do
    {:ok,
     "# Exercise #{exercise.id}: #{exercise.title}\n\n" <>
       "<!-- TODO: exercise #{exercise.id} - #{exercise.title} -->\n"}
  end

  defp rewrite(_source, %{target: %{kind: :file}} = exercise, :pending) do
    {:ok,
     "# Exercise #{exercise.id} is locked\n\n" <>
       "#{locked_message(exercise)}. Complete the preceding exercises first.\n"}
  end

  defp rewrite(_source, %{target: target}, _mode) do
    {:error, "unsupported target #{inspect(target)}"}
  end

  defp restore(_source, solution, %{kind: :file}), do: {:ok, solution}

  defp restore(source, solution, %{kind: :definition, anchor: anchor}) do
    with {:ok, current} <- locate_definition(source, anchor),
         {:ok, reference} <- locate_definition(solution, anchor) do
      current_lines = String.split(source, "\n", trim: false)
      solution_lines = String.split(solution, "\n", trim: false)

      replacement =
        Enum.slice(
          solution_lines,
          reference.start_line - 1,
          reference.end_line - reference.start_line + 1
        )

      current_start_line = scaffold_start_line(current_lines, current.start_line)

      {:ok,
       current_lines
       |> Enum.take(current_start_line - 1)
       |> Kernel.++(replacement)
       |> Kernel.++(Enum.drop(current_lines, current.end_line))
       |> Enum.join("\n")}
    end
  end

  defp restore(source, solution, %{kind: :branch} = target) do
    current_lines = String.split(source, "\n", trim: false)
    solution_lines = String.split(solution, "\n", trim: false)

    with {:ok, current_start, current_stop} <- branch_span(current_lines, target),
         {:ok, solution_start, solution_stop} <- branch_span(solution_lines, target) do
      replacement = Enum.slice(solution_lines, solution_start, solution_stop - solution_start)
      restore_start = scaffold_start_line(current_lines, current_start + 1) - 1
      restore_stop = scaffold_start_line(current_lines, current_stop + 1) - 1

      {:ok,
       current_lines
       |> Enum.take(restore_start)
       |> Kernel.++(replacement)
       |> Kernel.++(Enum.drop(current_lines, restore_stop))
       |> Enum.join("\n")}
    end
  end

  defp locate_definition(source, anchor) do
    with {:ok, line} <- anchor_line(source, anchor),
         {:ok, definition} <- definition_at(source, line) do
      {:ok, definition}
    end
  end

  defp anchor_line(source, anchor) do
    source
    |> String.split("\n", trim: false)
    |> Enum.find_index(&(&1 |> String.trim_leading() |> String.starts_with?(anchor)))
    |> case do
      nil -> {:error, "definition anchor #{inspect(anchor)} was not found"}
      index -> {:ok, index + 1}
    end
  end

  defp definition_at(source, line) do
    with {:ok, quoted} <- Code.string_to_quoted(source, columns: true, token_metadata: true) do
      {_quoted, definitions} =
        Macro.prewalk(quoted, [], fn
          {kind, metadata, [_head, _body]} = node, definitions
          when kind in @definition_kinds ->
            if metadata[:line] == line do
              {node, [%{kind: kind, metadata: metadata} | definitions]}
            else
              {node, definitions}
            end

          node, definitions ->
            {node, definitions}
        end)

      case definitions do
        [definition] ->
          with {:ok, end_line} <- definition_end_line(definition.metadata) do
            {:ok,
             Map.merge(definition, %{
               start_line: definition.metadata[:line],
               end_line: end_line
             })}
          end

        [] ->
          {:error, "anchor on line #{line} does not identify a function definition"}

        _ ->
          {:error, "anchor on line #{line} identifies more than one function definition"}
      end
    else
      {:error, error} -> {:error, "Elixir parser error: #{inspect(error)}"}
    end
  end

  defp replace_definition(source, definition, exercise, mode) do
    lines = String.split(source, "\n", trim: false)
    original_line = Enum.at(lines, definition.start_line - 1)
    indentation = leading_whitespace(original_line)
    failure = failure_message(exercise, mode)

    replacement =
      case definition.metadata[:do] do
        nil ->
          with {:ok, signature} <- one_line_signature(original_line) do
            comment = one_line_comment(exercise, mode, indentation)
            short_failure = short_failure(exercise, mode)
            {:ok, [comment, "#{signature} raise(#{inspect(short_failure)})"]}
          end

        do_metadata ->
          header = definition_header(lines, definition.start_line, do_metadata)

          todo =
            if mode == :active,
              do: ["#{indentation}  # #{marker(exercise)} - #{exercise.title}"],
              else: []

          {:ok,
           header ++
             todo ++
             ["#{indentation}  raise #{inspect(failure)}", "#{indentation}end"]}
      end

    with {:ok, replacement} <- replacement do
      start_line = scaffold_start_line(lines, definition.start_line)

      {:ok,
       lines
       |> Enum.take(start_line - 1)
       |> Kernel.++(replacement)
       |> Kernel.++(Enum.drop(lines, definition.end_line))
       |> Enum.join("\n")}
    end
  end

  defp definition_header(lines, start_line, do_metadata) do
    do_line = do_metadata[:line]
    do_column = do_metadata[:column]
    header = Enum.slice(lines, start_line - 1, do_line - start_line + 1)
    last = List.last(header)
    prefix = binary_part(last, 0, do_column + 1)
    List.replace_at(header, -1, prefix)
  end

  defp one_line_signature(line) do
    case :binary.match(line, ", do:") do
      {index, 5} -> {:ok, binary_part(line, 0, index + 5)}
      :nomatch -> {:error, "one-line function definition does not contain , do:"}
    end
  end

  defp replace_branch(source, target, exercise, mode) do
    lines = String.split(source, "\n", trim: false)

    with {:ok, start_index, stop_index} <- branch_span(lines, target),
         {:ok, branch_head} <- branch_head(Enum.at(lines, start_index), target) do
      indentation = leading_whitespace(branch_head)
      original_line = Enum.at(lines, start_index)

      replacement =
        if one_line_branch?(original_line) do
          comment = one_line_comment(exercise, mode, indentation)
          short_failure = short_failure(exercise, mode)
          [comment, "#{branch_head} raise(#{inspect(short_failure)})"]
        else
          todo =
            if mode == :active,
              do: ["#{indentation}  # #{marker(exercise)} - #{exercise.title}"],
              else: []

          [branch_head] ++
            todo ++ ["#{indentation}  raise #{inspect(failure_message(exercise, mode))}", ""]
        end

      replace_start = scaffold_start_line(lines, start_index + 1) - 1
      replace_stop = scaffold_start_line(lines, stop_index + 1) - 1

      {:ok,
       lines
       |> Enum.take(replace_start)
       |> Kernel.++(replacement)
       |> Kernel.++(Enum.drop(lines, replace_stop))
       |> Enum.join("\n")}
    end
  end

  defp branch_span(lines, target) do
    with {:ok, offset} <- branch_offset(lines, target),
         {:ok, start_index} <- source_line(lines, target.start, offset),
         {:ok, stop_index} <- source_line(lines, target.stop, start_index + 1) do
      {:ok, start_index, stop_index}
    end
  end

  defp branch_offset(lines, %{after: anchor}) do
    with {:ok, index} <- source_line(lines, anchor, 0), do: {:ok, index + 1}
  end

  defp branch_offset(_lines, _target), do: {:ok, 0}

  defp source_line(lines, anchor, offset) do
    lines
    |> Enum.drop(offset)
    |> Enum.find_index(&(&1 |> String.trim_leading() |> String.starts_with?(anchor)))
    |> case do
      nil -> {:error, "branch anchor #{inspect(anchor)} was not found"}
      index -> {:ok, index + offset}
    end
  end

  defp branch_head(line, target) do
    indentation = leading_whitespace(line)

    case target[:replacement_head] do
      replacement when is_binary(replacement) ->
        {:ok, indentation <> replacement}

      nil ->
        case :binary.match(line, "->") do
          {index, 2} -> {:ok, line |> binary_part(0, index + 2) |> String.trim_trailing()}
          :nomatch -> {:error, "branch start #{inspect(target.start)} does not contain ->"}
        end
    end
  end

  defp one_line_branch?(line) do
    case :binary.match(line, "->") do
      {index, 2} ->
        line
        |> binary_part(index + 2, byte_size(line) - index - 2)
        |> String.trim()
        |> Kernel.!=("")

      :nomatch ->
        false
    end
  end

  defp failure_message(exercise, :active), do: not_implemented_message(exercise)
  defp failure_message(exercise, :pending), do: locked_message(exercise)

  defp short_failure(exercise, :active), do: "TODO #{exercise.id}"
  defp short_failure(exercise, :pending), do: "locked #{exercise.id}"

  defp one_line_comment(exercise, :active, indentation) do
    "#{indentation}# #{marker(exercise)} - #{exercise.title}"
  end

  defp one_line_comment(exercise, :pending, indentation) do
    "#{indentation}# #{locked_message(exercise)}"
  end

  defp scaffold_start_line(lines, definition_start_line) do
    previous = Enum.at(lines, definition_start_line - 2, "") |> String.trim()

    if String.starts_with?(previous, "# TODO: exercise ") or
         (String.starts_with?(previous, "# GBEmulings exercise ") and
            String.ends_with?(previous, " is locked until its turn")) do
      definition_start_line - 1
    else
      definition_start_line
    end
  end

  defp leading_whitespace(line) do
    line
    |> String.codepoints()
    |> Enum.take_while(&(&1 in [" ", "\t"]))
    |> Enum.join()
  end

  defp definition_end_line(metadata) do
    end_metadata = metadata[:end] || metadata[:end_of_expression]

    case end_metadata && end_metadata[:line] do
      line when is_integer(line) -> {:ok, line}
      _ -> {:error, "function definition has no end-line metadata"}
    end
  end

  defp exercise_error(exercise, reason),
    do: "could not scaffold exercise #{exercise.id}: #{reason}"

  defp build_plan(path, relative_path, contents) do
    %{path: path, relative_path: relative_path, contents: contents}
  end
end
