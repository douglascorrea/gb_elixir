defmodule GbEmu.Exercises.Scaffolder do
  @moduledoc false

  @definition_kinds [:def, :defp]

  def plan(root, %{id: id, title: title, target: %{kind: :definition} = target}) do
    path = Path.join(root, target.file)

    with {:ok, source} <- File.read(path),
         {:ok, line} <- anchor_line(source, target.anchor),
         {:ok, definition} <- definition_at(source, line),
         {:ok, contents} <- replace_definition(source, definition, id, title) do
      {:ok, %{path: path, relative_path: target.file, contents: contents}}
    else
      {:error, reason} -> {:error, "could not scaffold exercise #{id}: #{reason}"}
    end
  end

  def plan(root, %{id: id, title: title, target: %{kind: :branch} = target}) do
    path = Path.join(root, target.file)

    with {:ok, source} <- File.read(path),
         {:ok, contents} <- replace_branch(source, target, id, title) do
      {:ok, %{path: path, relative_path: target.file, contents: contents}}
    else
      {:error, reason} -> {:error, "could not scaffold exercise #{id}: #{reason}"}
    end
  end

  def plan(_root, %{id: id, target: target}) do
    {:error, "could not scaffold exercise #{id}: unsupported target #{inspect(target)}"}
  end

  def marker(%{id: id}), do: "TODO: exercise #{id}"

  def not_implemented_message(%{id: id}) do
    "GBEmulings exercise #{id} is not implemented"
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
          {kind, metadata, [head, _body]} = node, definitions
          when kind in @definition_kinds ->
            if metadata[:line] == line do
              {node, [{kind, metadata, head} | definitions]}
            else
              {node, definitions}
            end

          node, definitions ->
            {node, definitions}
        end)

      case definitions do
        [definition] -> {:ok, definition}
        [] -> {:error, "anchor on line #{line} does not identify a function definition"}
        _ -> {:error, "anchor on line #{line} identifies more than one function definition"}
      end
    else
      {:error, error} -> {:error, "Elixir parser error: #{inspect(error)}"}
    end
  end

  defp replace_definition(source, {kind, metadata, head}, id, title) do
    start_line = metadata[:line]

    with {:ok, end_line} <- definition_end_line(metadata) do
      lines = String.split(source, "\n", trim: false)
      original_line = Enum.at(lines, start_line - 1)
      indentation = leading_whitespace(original_line)
      function_head = Macro.to_string(head)

      replacement = [
        "#{indentation}#{kind} #{function_head} do",
        "#{indentation}  # TODO: exercise #{id} - #{title}",
        "#{indentation}  raise #{inspect("GBEmulings exercise #{id} is not implemented")}",
        "#{indentation}end"
      ]

      contents =
        lines
        |> Enum.take(start_line - 1)
        |> Kernel.++(replacement)
        |> Kernel.++(Enum.drop(lines, end_line))
        |> Enum.join("\n")

      {:ok, contents}
    end
  end

  defp replace_branch(source, target, id, title) do
    lines = String.split(source, "\n", trim: false)

    with {:ok, offset} <- branch_offset(lines, target),
         {:ok, start_index} <- source_line(lines, target.start, offset),
         {:ok, stop_index} <- source_line(lines, target.stop, start_index + 1),
         {:ok, branch_head} <- branch_head(Enum.at(lines, start_index), target) do
      indentation = leading_whitespace(branch_head)

      replacement = [
        branch_head,
        "#{indentation}  # TODO: exercise #{id} - #{title}",
        "#{indentation}  raise #{inspect("GBEmulings exercise #{id} is not implemented")}"
      ]

      contents =
        lines
        |> Enum.take(start_index)
        |> Kernel.++(replacement)
        |> Kernel.++(Enum.drop(lines, stop_index))
        |> Enum.join("\n")

      {:ok, contents}
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
end
