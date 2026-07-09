defmodule GbEmu.Debugger.SourceMap do
  @moduledoc """
  Compile-time source selectors for debugger links.

  Only repository-relative paths and selector-to-line maps are embedded in the
  beam. Required selectors are validated while compiling, so a refactor cannot
  silently turn a source link into line zero.
  """

  @github_base "https://github.com/douglascorrea/gb_elixir/blob/master/"

  @source_specs %{
    cpu: %{
      absolute: Path.expand("../cpu.ex", __DIR__),
      path: "lib/gb_emu/cpu.ex",
      label: "CPU"
    },
    bus: %{
      absolute: Path.expand("../bus.ex", __DIR__),
      path: "lib/gb_emu/bus.ex",
      label: "Bus"
    },
    ppu: %{
      absolute: Path.expand("../ppu.ex", __DIR__),
      path: "lib/gb_emu/ppu.ex",
      label: "PPU"
    },
    timer: %{
      absolute: Path.expand("../timer.ex", __DIR__),
      path: "lib/gb_emu/timer.ex",
      label: "Timer"
    },
    machine: %{
      absolute: Path.expand("../machine.ex", __DIR__),
      path: "lib/gb_emu/machine.ex",
      label: "Machine"
    }
  }

  for {_component, spec} <- @source_specs do
    @external_resource spec.absolute
  end

  @bus_branch_specs [
    {"bus:read:boot", "def peek8(gb, addr) do", "addr < 0x0100 and gb.boot_enabled ->"},
    {"bus:read:rom0", "def peek8(gb, addr) do", "addr < 0x4000 ->"},
    {"bus:read:romx", "def peek8(gb, addr) do", "addr < 0x8000 ->"},
    {"bus:read:vram", "def peek8(gb, addr) do", "addr < 0xA000 ->"},
    {"bus:read:external_ram", "def peek8(gb, addr) do", "addr < 0xC000 ->"},
    {"bus:read:wram", "def peek8(gb, addr) do", "addr < 0xE000 ->"},
    {"bus:read:echo_ram", "def peek8(gb, addr) do", "addr < 0xFE00 ->"},
    {"bus:read:oam", "def peek8(gb, addr) do", "addr < 0xFEA0 ->"},
    {"bus:read:unusable", "def peek8(gb, addr) do", "addr < 0xFF00 ->"},
    {"bus:read:io", "def peek8(gb, addr) do", "addr < 0xFF80 ->"},
    {"bus:read:hram", "def peek8(gb, addr) do", "addr < 0xFFFF ->"},
    {"bus:read:ie", "def peek8(gb, addr) do", "true ->"},
    {"bus:write:rom0", "defp do_write8(gb, addr, v) do", "addr < 0x8000 ->"},
    {"bus:write:romx", "defp do_write8(gb, addr, v) do", "addr < 0x8000 ->"},
    {"bus:write:vram", "defp do_write8(gb, addr, v) do", "addr < 0xA000 ->"},
    {"bus:write:external_ram", "defp do_write8(gb, addr, v) do", "addr < 0xC000 ->"},
    {"bus:write:wram", "defp do_write8(gb, addr, v) do", "addr < 0xE000 ->"},
    {"bus:write:echo_ram", "defp do_write8(gb, addr, v) do", "addr < 0xFE00 ->"},
    {"bus:write:oam", "defp do_write8(gb, addr, v) do", "addr < 0xFEA0 ->"},
    {"bus:write:unusable", "defp do_write8(gb, addr, v) do", "addr < 0xFF00 ->"},
    {"bus:write:io", "defp do_write8(gb, addr, v) do", "addr < 0xFF80 ->"},
    {"bus:write:hram", "defp do_write8(gb, addr, v) do", "addr < 0xFFFF ->"},
    {"bus:write:ie", "defp do_write8(gb, addr, v) do", "true ->"}
  ]

  @bus_branch_selectors Enum.map(@bus_branch_specs, &elem(&1, 0))

  @bus_branch_lines Map.new(@bus_branch_specs, fn {key, function_selector, branch_selector} ->
                      lines =
                        @source_specs.bus.absolute
                        |> File.read!()
                        |> String.split("\n")
                        |> Enum.with_index(1)

                      function_index =
                        Enum.find_index(lines, fn {line, _number} ->
                          String.contains?(line, function_selector)
                        end)

                      if is_nil(function_index) do
                        raise CompileError,
                          description:
                            "required Bus function selector #{inspect(function_selector)} is absent"
                      end

                      matches =
                        lines
                        |> Enum.drop(function_index + 1)
                        |> Enum.take_while(fn {line, _number} ->
                          trimmed = String.trim(line)
                          not String.starts_with?(trimmed, ["def ", "defp "])
                        end)
                        |> Enum.filter(fn {line, _number} ->
                          String.contains?(line, branch_selector)
                        end)

                      case matches do
                        [{_line, number}] ->
                          {key, number}

                        _ ->
                          raise CompileError,
                            description:
                              "required Bus branch #{inspect(branch_selector)} in #{inspect(function_selector)} matched #{length(matches)} lines"
                      end
                    end)

  @source_lines Map.new(@source_specs, fn {component, spec} ->
                  selectors =
                    spec.absolute
                    |> File.read!()
                    |> String.split("\n")
                    |> Enum.with_index(1)
                    |> Enum.reduce(%{}, fn {line, number}, acc ->
                      selector = String.trim(line)

                      if String.starts_with?(selector, ["def ", "defp "]) do
                        Map.put(acc, selector, number)
                      else
                        acc
                      end
                    end)

                  selectors =
                    if component == :bus do
                      Map.merge(selectors, @bus_branch_lines)
                    else
                      selectors
                    end

                  {component, %{path: spec.path, label: spec.label, selector_lines: selectors}}
                end)

  @literal_cpu_opcodes [
    0x00,
    0x01,
    0x02,
    0x03,
    0x07,
    0x08,
    0x0A,
    0x0B,
    0x0F,
    0x10,
    0x11,
    0x12,
    0x13,
    0x17,
    0x18,
    0x1A,
    0x1B,
    0x1F,
    0x21,
    0x22,
    0x23,
    0x27,
    0x2A,
    0x2B,
    0x2F,
    0x31,
    0x32,
    0x33,
    0x37,
    0x3A,
    0x3B,
    0x3F,
    0x76,
    0xC1,
    0xC3,
    0xC5,
    0xC9,
    0xCB,
    0xCD,
    0xD1,
    0xD5,
    0xD9,
    0xE0,
    0xE1,
    0xE2,
    0xE5,
    0xE8,
    0xE9,
    0xEA,
    0xF0,
    0xF1,
    0xF2,
    0xF3,
    0xF5,
    0xF8,
    0xF9,
    0xFA,
    0xFB
  ]

  @literal_cpu_selectors Enum.map(@literal_cpu_opcodes, fn opcode ->
                           hex =
                             opcode
                             |> Integer.to_string(16)
                             |> String.upcase()
                             |> String.pad_leading(2, "0")

                           "defp exec(0x#{hex}, gb)"
                         end)

  @required %{
    cpu:
      @literal_cpu_selectors ++
        [
          "def boundary(gb) do",
          "def step(gb) do",
          "defp execute(gb) do",
          "defp service_interrupt(gb, pending) do",
          "defp exec_cb(op, gb) do",
          "defp exec(_op, gb), do: {gb, 4}",
          "defp exec(op, gb) when op in [0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C] do",
          "defp exec(op, gb) when op in [0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D] do",
          "defp exec(op, gb) when op in [0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E] do",
          "defp exec(op, gb) when op in [0x09, 0x19, 0x29, 0x39] do",
          "defp exec(op, gb) when op in [0x20, 0x28, 0x30, 0x38] do",
          "defp exec(op, gb) when op in 0x40..0x7F do",
          "defp exec(op, gb) when op in 0x80..0xBF do",
          "defp exec(op, gb) when op in [0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE] do",
          "defp exec(op, gb) when op in [0xC0, 0xC8, 0xD0, 0xD8] do",
          "defp exec(op, gb) when op in [0xC2, 0xCA, 0xD2, 0xDA] do",
          "defp exec(op, gb) when op in [0xC4, 0xCC, 0xD4, 0xDC] do",
          "defp exec(op, gb) when op in [0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF] do"
        ],
    bus:
      @bus_branch_selectors ++
        [
          "def read8(%{debug_trace?: true} = gb, addr) do",
          "def peek8(gb, addr) do",
          "def write8(%{debug_trace?: true} = gb, addr, requested) do",
          "defp do_write8(gb, addr, v) do",
          "defp oam_dma(gb, src_hi) do"
        ],
    ppu: [
      "def step(%{debug_trace?: true} = gb, cycles) do",
      "defp advance(gb) do",
      "defp finish_frame(gb) do",
      "defp render_scanline(gb) do"
    ],
    timer: ["def step(gb, cycles) do"],
    machine: [
      "def step_instruction(%{debug_trace?: true} = gb) do",
      "defp step_serial(%{serial_cycles: nil} = gb, _cycles), do: gb",
      "defp step_serial(gb, cycles) do"
    ]
  }

  for {component, selectors} <- @required, selector <- selectors do
    %{selector_lines: selector_lines} = Map.fetch!(@source_lines, component)

    matches =
      Enum.filter(selector_lines, fn {line, _number} -> String.contains?(line, selector) end)

    if length(matches) != 1 do
      raise CompileError,
        description:
          "required debugger source selector #{inspect(selector)} for #{component} matched #{length(matches)} lines"
    end
  end

  @doc "Resolves a component selector to repository-relative source metadata."
  @spec location(atom(), String.t()) :: map()
  def location(component, selector) when is_atom(component) and is_binary(selector) do
    case Map.fetch(@source_lines, component) do
      {:ok, source} -> build_location(component, selector, source)
      :error -> raise ArgumentError, "unknown debugger source component: #{inspect(component)}"
    end
  end

  defp build_location(component, selector, source) do
    case Map.fetch(source.selector_lines, selector) do
      {:ok, number} ->
        location_map(component, selector, source, number)

      :error ->
        matches =
          Enum.filter(source.selector_lines, fn {line, _number} ->
            String.contains?(line, selector)
          end)

        case matches do
          [{_line, number}] ->
            location_map(component, selector, source, number)

          [] ->
            raise ArgumentError,
                  "unknown debugger source selector #{inspect(selector)} for #{inspect(component)}"

          _ ->
            raise ArgumentError,
                  "ambiguous debugger source selector #{inspect(selector)} for #{inspect(component)}"
        end
    end
  end

  defp location_map(component, selector, source, number) do
    %{
      component: component,
      selector: selector,
      path: source.path,
      line: number,
      label: source.label,
      url: @github_base <> source.path <> "#L#{number}"
    }
  end
end
