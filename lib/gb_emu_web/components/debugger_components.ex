defmodule GbEmuWeb.DebuggerComponents do
  @moduledoc """
  Stateless display components for the educational Game Boy debugger.
  """

  use Phoenix.Component

  import GbEmuWeb.CoreComponents, only: [icon: 1, input: 1]

  alias GbEmu.Debugger.SourceMap

  attr :attached, :boolean, required: true
  attr :available, :boolean, required: true
  attr :snapshot, :map, default: nil
  attr :error, :string, default: nil
  attr :memory_form, :any, required: true
  attr :trace_stream, :any, required: true

  def sidebar(assigns) do
    boot = snapshot_value(assigns.snapshot, :boot, %{})
    assigns = assign(assigns, :boot, boot)

    ~H"""
    <aside
      id="debug-sidebar"
      data-debug-ui
      aria-label="Game Boy debugger"
      class="debugger-shell min-w-0 select-text xl:sticky xl:top-4 xl:max-h-[calc(100vh-2rem)] xl:overflow-y-auto"
    >
      <header class="debugger-mast">
        <div>
          <p class="debugger-kicker">DMG // BEAM LOGIC ANALYZER</p>
          <h2 class="debugger-title">Instruction workbench</h2>
          <p class="mt-1 font-mono text-[9px] uppercase tracking-[0.12em] text-slate-500">
            Boot {boot_summary(@boot)}
          </p>
        </div>
        <div class="flex items-center gap-2" aria-live="polite">
          <span class={status_light_class(@attached, @available)}></span>
          <span class="font-mono text-[10px] font-bold uppercase tracking-[0.18em] text-slate-300">
            {status_label(@attached, @available)}
          </span>
        </div>
      </header>

      <div
        :if={@error}
        id="debug-error"
        role="alert"
        class="mx-3 mt-3 border border-rose-400/40 bg-rose-950/70 px-3 py-2 font-mono text-xs text-rose-100"
      >
        {@error}
      </div>

      <.toolbar attached={@attached} available={@available} />
      <.instruction snapshot={@snapshot} />
      <.registers snapshot={@snapshot} />
      <.memory attached={@attached} snapshot={@snapshot} form={@memory_form} />
      <.peripherals snapshot={@snapshot} />
      <.source_trail snapshot={@snapshot} />
      <.trace_timeline trace_stream={@trace_stream} />
    </aside>
    """
  end

  attr :attached, :boolean, required: true
  attr :available, :boolean, required: true

  def toolbar(assigns) do
    assigns = assign(assigns, :run_disabled, not assigns.attached)

    ~H"""
    <section aria-label="Debugger controls" class="debugger-toolbar">
      <.control
        id="debug-attach"
        event="debug_attach"
        label="Attach"
        icon="hero-bolt"
        disabled={!@available or @attached}
        accent="lime"
      />
      <.control
        id="debug-step"
        event="debug_step"
        label="Step"
        icon="hero-forward"
        disabled={@run_disabled}
        accent="amber"
      />
      <.control
        id="debug-step-10"
        event="debug_step_10"
        label="×10"
        icon="hero-forward"
        disabled={@run_disabled}
      />
      <.control
        id="debug-next-ppu"
        event="debug_ppu"
        label="PPU"
        icon="hero-square-3-stack-3d"
        disabled={@run_disabled}
      />
      <.control
        id="debug-next-scanline"
        event="debug_scanline"
        label="Line"
        icon="hero-bars-3-bottom-left"
        disabled={@run_disabled}
      />
      <.control
        id="debug-next-frame"
        event="debug_frame"
        label="Frame"
        icon="hero-photo"
        disabled={@run_disabled}
      />
      <.control
        id="debug-restart"
        event="debug_restart"
        label="Boot"
        icon="hero-arrow-path"
        disabled={@run_disabled}
        accent="rose"
      />
      <.control
        id="debug-resume"
        event="debug_resume"
        label="Resume"
        icon="hero-play"
        disabled={@run_disabled}
        accent="lime"
      />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :event, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :disabled, :boolean, default: false
  attr :accent, :string, default: "slate"

  defp control(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={@event}
      disabled={@disabled}
      class={[
        "debugger-control group",
        @accent == "lime" && "debugger-control-lime",
        @accent == "amber" && "debugger-control-amber",
        @accent == "rose" && "debugger-control-rose"
      ]}
    >
      <.icon name={@icon} class="size-3.5 transition-transform group-hover:translate-x-px" />
      <span>{@label}</span>
    </button>
    """
  end

  attr :snapshot, :map, default: nil

  def instruction(assigns) do
    instruction = snapshot_value(assigns.snapshot, :instruction, nil)
    source = instruction_source(instruction)

    assigns =
      assigns
      |> assign(:instruction, instruction)
      |> assign(:source, source)

    ~H"""
    <section id="debug-instruction" class="debugger-panel debugger-instruction-panel">
      <.panel_heading index="01" title="Current instruction" signal="CPU" />

      <%= if @instruction do %>
        <div class="grid gap-3 sm:grid-cols-[7rem_minmax(0,1fr)]">
          <div class="debugger-address-block">
            <span class="text-[9px] uppercase tracking-[0.2em] text-slate-500">Program counter</span>
            <strong class="mt-1 block font-mono text-2xl text-amber-300">
              ${hex16(Map.get(@instruction, :pc, 0))}
            </strong>
          </div>
          <div class="min-w-0">
            <p class="font-mono text-lg font-bold tracking-tight text-amber-100">
              {Map.get(@instruction, :mnemonic, "—")}
            </p>
            <p class="mt-1 font-mono text-[11px] tracking-[0.14em] text-slate-400">
              {format_bytes(Map.get(@instruction, :bytes, []))}
            </p>
            <a
              :if={@source}
              href={@source.url}
              target="_blank"
              rel="noreferrer"
              class="mt-2 inline-flex max-w-full items-center gap-1 truncate font-mono text-[10px] text-cyan-300 transition hover:text-cyan-100"
            >
              <.icon name="hero-code-bracket" class="size-3" />
              <span class="truncate">{@source.path}:L{@source.line}</span>
            </a>
          </div>
        </div>
      <% else %>
        <.empty_state>Attach to freeze the live machine at an instruction boundary.</.empty_state>
      <% end %>
    </section>
    """
  end

  attr :snapshot, :map, default: nil

  def registers(assigns) do
    cpu = snapshot_value(assigns.snapshot, :cpu, %{})
    registers = Map.get(cpu, :registers, %{})
    flags = Map.get(cpu, :flags, %{})

    assigns =
      assigns
      |> assign(:registers, registers)
      |> assign(:flags, flags)
      |> assign(:cpu, cpu)

    ~H"""
    <section id="debug-registers" class="debugger-panel">
      <.panel_heading index="02" title="CPU register file" signal="SM83" />
      <%= if map_size(@registers) > 0 do %>
        <div class="grid grid-cols-5 gap-px overflow-hidden border border-white/5 bg-white/5">
          <.register
            :for={name <- [:a, :f, :b, :c, :d, :e, :h, :l]}
            name={name}
            value={Map.get(@registers, name, 0)}
          />
          <.register name={:sp} value={Map.get(@registers, :sp, 0)} wide />
          <.register name={:pc} value={Map.get(@registers, :pc, 0)} wide />
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-2">
          <span :for={flag <- [:z, :n, :h, :c]} class={flag_class(Map.get(@flags, flag, false))}>
            {String.upcase(Atom.to_string(flag))}
          </span>
          <span class="ml-auto font-mono text-[10px] text-slate-500">
            IME {on_off(Map.get(@cpu, :ime, false))} · HALT {on_off(Map.get(@cpu, :halted, false))}
          </span>
        </div>
      <% else %>
        <.empty_state>Register values appear after attach.</.empty_state>
      <% end %>
    </section>
    """
  end

  attr :name, :atom, required: true
  attr :value, :integer, required: true
  attr :wide, :boolean, default: false

  defp register(assigns) do
    ~H"""
    <div class="bg-[#10161a] px-2 py-2 text-center">
      <span class="block font-mono text-[9px] font-bold uppercase tracking-widest text-slate-500">
        {@name}
      </span>
      <strong class="mt-0.5 block font-mono text-xs text-lime-300">
        {if @wide, do: hex16(@value), else: hex8(@value)}
      </strong>
    </div>
    """
  end

  attr :attached, :boolean, required: true
  attr :snapshot, :map, default: nil
  attr :form, :any, required: true

  def memory(assigns) do
    memory = snapshot_value(assigns.snapshot, :memory, nil)
    cells = if memory, do: Map.get(memory, :cells, []), else: []
    trace = snapshot_value(assigns.snapshot, :newest_trace, nil)
    activity = if trace, do: Map.get(trace, :memory, []), else: []

    assigns =
      assigns
      |> assign(:memory, memory)
      |> assign(:cells, cells)
      |> assign(:activity, Enum.take(activity, -16))

    ~H"""
    <section class="debugger-panel debugger-memory-panel">
      <.panel_heading index="03" title="Address space" signal="64 KiB BUS" />

      <.form
        for={@form}
        id="debug-memory-form"
        phx-submit="debug_memory"
        class="mb-3 flex items-end gap-2"
      >
        <.input
          field={@form[:address]}
          type="text"
          label="Hex window start"
          disabled={!@attached}
          autocomplete="off"
          spellcheck="false"
          maxlength="6"
          placeholder="C000"
          class="h-9 w-full border border-slate-600 bg-[#0a0f12] px-3 font-mono text-sm uppercase text-lime-200 outline-none transition placeholder:text-slate-700 focus:border-lime-300 focus:ring-1 focus:ring-lime-300/30 disabled:cursor-not-allowed disabled:opacity-40"
        />
        <button
          id="debug-memory-submit"
          type="submit"
          disabled={!@attached}
          class="h-9 border border-cyan-400/40 bg-cyan-400/10 px-3 font-mono text-[10px] font-bold uppercase tracking-widest text-cyan-200 transition hover:bg-cyan-400/20 disabled:cursor-not-allowed disabled:opacity-30"
        >
          Read
        </button>
      </.form>

      <div class="mb-2 flex flex-wrap items-center justify-between gap-2 font-mono text-[10px] text-slate-500">
        <span>
          <%= if @memory do %>
            ${hex16(@memory.start)}—${hex16(@memory.stop)}
          <% else %>
            $0000—$00FF
          <% end %>
        </span>
        <div class="flex items-center gap-3">
          <span class="text-amber-300">● PC</span>
          <span class="text-cyan-300">● READ</span>
          <span class="text-fuchsia-300">● WRITE</span>
        </div>
      </div>

      <div
        id="debug-memory-grid"
        role="grid"
        aria-label="Selected 256-byte memory window"
        class="debugger-memory-grid"
      >
        <%= if @cells == [] do %>
          <div class="col-span-16 flex min-h-44 items-center justify-center px-4 text-center font-mono text-xs text-slate-600">
            Attach to inspect a live 256-byte memory window.
          </div>
        <% else %>
          <span
            :for={cell <- @cells}
            role="gridcell"
            data-address={hex16(cell.address)}
            data-marker={Enum.map_join(cell.markers, ",", &Atom.to_string/1)}
            title={"$#{hex16(cell.address)} · #{cell.label} · #{human_atom(cell.region)}"}
            class={memory_cell_class(cell)}
          >
            {hex8(cell.value)}
          </span>
        <% end %>
      </div>

      <div class="mt-3 border-t border-white/5 pt-3">
        <p class="mb-2 font-mono text-[9px] font-bold uppercase tracking-[0.2em] text-slate-500">
          Latest bus activity
        </p>
        <div class="max-h-36 space-y-1 overflow-y-auto pr-1">
          <div :if={@activity == []} class="font-mono text-[10px] text-slate-600">
            No reads or writes recorded yet.
          </div>
          <div
            :for={event <- @activity}
            class="debugger-memory-event"
            data-memory-operation={Map.get(event, :operation, :unknown)}
            data-memory-address={hex16(memory_event_address(event))}
          >
            <div class="flex min-w-0 items-center gap-2">
              <span class={memory_operation_class(Map.get(event, :operation))}>
                {memory_operation_label(Map.get(event, :operation))}
              </span>
              <span class="text-slate-300">${hex16(memory_event_address(event))}</span>
              <span class="truncate text-slate-500">
                {human_atom(Map.get(event, :region, :bus))}
              </span>
              <span class="ml-auto shrink-0 text-slate-300">{memory_event_value(event)}</span>
            </div>
            <div class="mt-1 flex min-w-0 items-center gap-2 border-t border-white/[0.035] pt-1 text-[9px]">
              <span class="min-w-0 flex-1 truncate text-slate-600">
                {Map.get(event, :label, "Memory bus access")}
              </span>
              <.source_link source={Map.get(event, :source_location)} />
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :snapshot, :map, default: nil

  def peripherals(assigns) do
    assigns =
      assigns
      |> assign(:ppu, snapshot_value(assigns.snapshot, :ppu, %{}))
      |> assign(:timer, snapshot_value(assigns.snapshot, :timer, %{}))
      |> assign(:interrupts, snapshot_value(assigns.snapshot, :interrupts, %{}))
      |> assign(:boot, snapshot_value(assigns.snapshot, :boot, %{}))
      |> assign(:cartridge, snapshot_value(assigns.snapshot, :cartridge, %{}))

    ~H"""
    <section id="debug-ppu" class="debugger-panel">
      <.panel_heading index="04" title="Peripheral clocks" signal="PPU / TIMER" />
      <%= if map_size(@ppu) > 0 do %>
        <div class="grid gap-2 sm:grid-cols-3">
          <.telemetry title="PPU">
            <.metric label="Mode" value={Map.get(@ppu, :ppu_mode, 0)} />
            <.metric label="LY / LYC" value={"#{Map.get(@ppu, :ly, 0)} / #{Map.get(@ppu, :lyc, 0)}"} />
            <.metric label="Dot" value={Map.get(@ppu, :ppu_dot, 0)} />
            <.metric label="Frame" value={Map.get(@ppu, :frame_count, 0)} />
          </.telemetry>
          <.telemetry title="Timer / IRQ">
            <.metric label="DIV" value={hex16(Map.get(@timer, :div_counter, 0))} />
            <.metric label="TIMA" value={hex8(Map.get(@timer, :tima, 0))} />
            <.metric label="IE" value={hex8(Map.get(@interrupts, :ie, 0))} />
            <.metric label="IF" value={hex8(Map.get(@interrupts, :if, 0))} />
          </.telemetry>
          <.telemetry title="Boot / Cart">
            <.metric label="Boot" value={human_atom(Map.get(@boot, :kind, :unknown))} />
            <.metric label="Overlay" value={on_off(Map.get(@boot, :overlay_enabled?, false))} />
            <.metric label="MBC" value={human_atom(Map.get(@cartridge, :mbc, :none))} />
            <.metric label="ROM bank" value={Map.get(@cartridge, :rom_bank, 0)} />
          </.telemetry>
        </div>
      <% else %>
        <.empty_state>PPU, timer, interrupt, and cartridge signals appear here.</.empty_state>
      <% end %>
    </section>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp telemetry(assigns) do
    ~H"""
    <div class="border border-white/5 bg-[#10161a] p-2.5">
      <p class="mb-2 font-mono text-[9px] font-bold uppercase tracking-[0.18em] text-cyan-300">
        {@title}
      </p>
      <div class="space-y-1">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp metric(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 font-mono text-[10px]">
      <span class="text-slate-600">{@label}</span>
      <span class="text-slate-300">{@value}</span>
    </div>
    """
  end

  attr :snapshot, :map, default: nil

  def source_trail(assigns) do
    sources = newest_sources(assigns.snapshot)
    assigns = assign(assigns, :sources, sources)

    ~H"""
    <section class="debugger-panel">
      <.panel_heading index="05" title="Elixir source trail" signal="FILE / LINE" />
      <div class="space-y-1.5">
        <a
          :for={source <- @sources}
          href={source.url}
          target="_blank"
          rel="noreferrer"
          class="group flex min-w-0 items-center gap-2 border border-white/5 bg-[#10161a] px-2.5 py-2 font-mono text-[10px] text-slate-400 transition hover:border-cyan-400/30 hover:text-cyan-200"
        >
          <span class="w-12 shrink-0 text-cyan-400">{source.label}</span>
          <span class="truncate">{source.path}</span>
          <span class="ml-auto shrink-0 text-slate-600 group-hover:text-cyan-300">L{source.line}</span>
        </a>
        <div :if={@sources == []} class="font-mono text-[10px] text-slate-600">
          Step once to map the interpreter path back to Elixir.
        </div>
      </div>
    </section>
    """
  end

  attr :trace_stream, :any, required: true

  def trace_timeline(assigns) do
    ~H"""
    <section class="debugger-panel">
      <.panel_heading index="06" title="Execution trace" signal="LAST 200" />
      <div id="debug-trace" phx-update="stream" class="max-h-80 space-y-1 overflow-y-auto pr-1">
        <div
          id="debug-trace-empty"
          class="hidden only:block border border-dashed border-slate-700 px-3 py-6 text-center font-mono text-[10px] text-slate-600"
        >
          No debugger steps recorded.
        </div>
        <article
          :for={{dom_id, trace} <- @trace_stream}
          id={dom_id}
          class="debugger-trace-row"
        >
          <div class="flex items-start gap-2">
            <span class="mt-0.5 shrink-0 text-[9px] font-bold uppercase tracking-widest text-amber-400">
              {human_atom(Map.get(trace, :kind, :step))}
            </span>
            <div class="min-w-0 flex-1">
              <p class="truncate font-mono text-[11px] font-bold text-slate-200">
                {Map.get(trace, :mnemonic, "Instruction")}
              </p>
              <p class="mt-0.5 font-mono text-[9px] text-slate-600">
                ${hex16(Map.get(trace, :pc_before, 0))} → ${hex16(Map.get(trace, :pc_after, 0))} · {Map.get(
                  trace,
                  :cycles,
                  0
                )}T
              </p>
            </div>
            <.source_link source={first_trace_source(trace)} compact />
          </div>
        </article>
      </div>
    </section>
    """
  end

  attr :index, :string, required: true
  attr :title, :string, required: true
  attr :signal, :string, required: true

  defp panel_heading(assigns) do
    ~H"""
    <div class="debugger-panel-heading">
      <span class="font-mono text-[9px] text-slate-600">{@index}</span>
      <h3 class="font-mono text-[10px] font-bold uppercase tracking-[0.16em] text-slate-300">
        {@title}
      </h3>
      <span class="ml-auto font-mono text-[8px] uppercase tracking-[0.16em] text-lime-400/70">
        {@signal}
      </span>
    </div>
    """
  end

  slot :inner_block, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="border border-dashed border-slate-700 bg-black/10 px-3 py-5 text-center font-mono text-[10px] leading-relaxed text-slate-600">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :source, :map, default: nil
  attr :compact, :boolean, default: false

  defp source_link(assigns) do
    ~H"""
    <a
      :if={@source}
      href={@source.url}
      target="_blank"
      rel="noreferrer"
      class={[
        "inline-flex shrink-0 items-center gap-1 font-mono text-cyan-400 transition hover:text-cyan-200",
        if(@compact, do: "text-[9px]", else: "text-[8px]")
      ]}
      aria-label={"Open #{@source.path} line #{@source.line}"}
    >
      <span>{@source.label}:L{@source.line}</span>
      <.icon name="hero-arrow-top-right-on-square" class="size-2.5" />
    </a>
    """
  end

  defp snapshot_value(snapshot, key, default) when is_map(snapshot),
    do: Map.get(snapshot, key, default)

  defp snapshot_value(_snapshot, _key, default), do: default

  defp newest_sources(snapshot) do
    case snapshot_value(snapshot, :newest_trace, nil) do
      %{sources: sources} when is_list(sources) -> sources
      _ -> []
    end
  end

  defp instruction_source(%{handler: {component, selector}})
       when is_atom(component) and is_binary(selector) do
    SourceMap.location(component, selector)
  rescue
    ArgumentError -> nil
  end

  defp instruction_source(_instruction), do: nil

  defp first_trace_source(%{sources: sources}) when is_list(sources), do: List.first(sources)
  defp first_trace_source(_trace), do: nil

  defp status_label(true, _available), do: "Debugging"
  defp status_label(false, true), do: "Live / ready"
  defp status_label(false, false), do: "No machine"

  defp status_light_class(true, _available),
    do: "size-2 rounded-full bg-lime-300 shadow-[0_0_12px_rgba(190,242,100,0.9)]"

  defp status_light_class(false, true), do: "size-2 rounded-full bg-amber-300 animate-pulse"
  defp status_light_class(false, false), do: "size-2 rounded-full bg-slate-700"

  defp boot_summary(boot) when map_size(boot) > 0 do
    kind = boot |> Map.get(:kind, :unknown) |> human_atom()
    mode = boot |> Map.get(:mode, :unknown) |> human_atom()
    overlay = if Map.get(boot, :overlay_enabled?, false), do: "OVERLAY ON", else: "OVERLAY OFF"
    "#{kind} / #{mode} / #{overlay}"
  end

  defp boot_summary(_boot), do: "SOURCE / UNKNOWN"

  defp flag_class(true),
    do:
      "border border-lime-300/40 bg-lime-300/10 px-2 py-0.5 font-mono text-[9px] font-bold text-lime-300"

  defp flag_class(false),
    do:
      "border border-slate-700 bg-slate-900/60 px-2 py-0.5 font-mono text-[9px] font-bold text-slate-600"

  defp memory_cell_class(cell) do
    [
      "debugger-memory-cell",
      cell.pc? && "debugger-memory-pc",
      cell.sp? && "debugger-memory-sp",
      cell.read? && "debugger-memory-read",
      cell.write? && "debugger-memory-write"
    ]
  end

  defp memory_operation_class(operation) when operation in [:write, :dma], do: "text-fuchsia-300"
  defp memory_operation_class(_operation), do: "text-cyan-300"

  defp memory_operation_label(:read), do: "RD"
  defp memory_operation_label(:write), do: "WR"
  defp memory_operation_label(:read_range), do: "RNG"
  defp memory_operation_label(:dma), do: "DMA"
  defp memory_operation_label(operation), do: operation |> human_atom() |> String.slice(0, 3)

  defp memory_event_address(%{address: address}), do: address
  defp memory_event_address(%{source_start: address}), do: address
  defp memory_event_address(%{start: address}), do: address
  defp memory_event_address(%{source: %Range{first: address}}), do: address

  defp memory_event_address(%{ranges: [first_range | _rest]}) do
    memory_range_start(first_range)
  end

  defp memory_event_address(_event), do: 0

  defp memory_range_start(%Range{first: address}) when is_integer(address), do: address
  defp memory_range_start(%{start: address}) when is_integer(address), do: address
  defp memory_range_start(_range), do: 0

  defp memory_event_value(%{before: before, after: after_value}),
    do: "#{hex8(before)}→#{hex8(after_value)}"

  defp memory_event_value(%{value: value}) when is_integer(value), do: hex8(value)
  defp memory_event_value(%{requested: value}) when is_integer(value), do: hex8(value)
  defp memory_event_value(_event), do: "—"

  defp format_bytes([]), do: "NO OPCODE BYTES"
  defp format_bytes(bytes), do: Enum.map_join(bytes, " ", &hex8/1)

  defp hex8(value) when is_integer(value),
    do:
      value
      |> band(0xFF)
      |> Integer.to_string(16)
      |> String.pad_leading(2, "0")
      |> String.upcase()

  defp hex8(_value), do: "00"

  defp hex16(value) when is_integer(value),
    do:
      value
      |> band(0xFFFF)
      |> Integer.to_string(16)
      |> String.pad_leading(4, "0")
      |> String.upcase()

  defp hex16(_value), do: "0000"

  defp band(value, mask), do: Bitwise.band(value, mask)

  defp human_atom(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()

  defp human_atom(value), do: to_string(value)

  defp on_off(true), do: "ON"
  defp on_off(false), do: "OFF"
  defp on_off(_value), do: "—"
end
