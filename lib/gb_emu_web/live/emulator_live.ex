defmodule GbEmuWeb.EmulatorLive do
  use GbEmuWeb, :live_view

  alias GbEmu.{Emulator, EmulatorSessions}

  @buttons ~w(up down left right a b start select)

  @impl true
  def mount(_params, _session, socket) do
    roms = list_roms()
    default_rom = List.first(roms)

    socket =
      socket
      |> assign(
        roms: roms,
        rom_options: Enum.map(roms, &{&1, &1}),
        current_rom: default_rom,
        fps: 0.0,
        paused: false,
        emulator: nil,
        emulator_status: :idle,
        max_sessions: EmulatorSessions.max_sessions(),
        page_title: "Game Boy on the BEAM"
      )

    socket =
      if connected?(socket) && default_rom do
        start_emulator(socket, default_rom)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_info({:gb_frame, frame, fps}, socket) do
    socket =
      socket
      |> push_event("frame", %{d: Base.encode64(frame)})
      |> assign(fps: fps)

    {:noreply, socket}
  end

  @impl true
  def handle_event("joypad", %{"button" => btn, "down" => down}, socket)
      when btn in @buttons and is_boolean(down) do
    if socket.assigns.emulator do
      Emulator.button(socket.assigns.emulator, String.to_existing_atom(btn), down)
    end

    {:noreply, socket}
  end

  def handle_event("joypad", _params, socket), do: {:noreply, socket}

  def handle_event("select_rom", %{"rom" => rom}, socket) do
    if rom in socket.assigns.roms and socket.assigns.emulator do
      Emulator.load_rom(socket.assigns.emulator, rom_path(rom))
      {:noreply, assign(socket, current_rom: rom, paused: false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset", _params, socket) do
    if socket.assigns.emulator && socket.assigns.current_rom do
      Emulator.load_rom(socket.assigns.emulator, rom_path(socket.assigns.current_rom))
    end

    {:noreply, assign(socket, paused: false)}
  end

  def handle_event("toggle_pause", _params, socket) do
    paused = !socket.assigns.paused

    if socket.assigns.emulator do
      Emulator.set_paused(socket.assigns.emulator, paused)
    end

    {:noreply, assign(socket, paused: paused)}
  end

  defp list_roms do
    Path.join(:code.priv_dir(:gb_emu), "roms")
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".gb"))
    |> Enum.sort()
  end

  defp rom_path(name), do: Path.join([:code.priv_dir(:gb_emu), "roms", name])

  defp start_emulator(socket, rom) do
    case EmulatorSessions.start_emulator(subscriber: self(), rom_path: rom_path(rom)) do
      {:ok, pid} ->
        assign(socket, emulator: pid, emulator_status: :running)

      {:error, :capacity} ->
        assign(socket, emulator_status: :capacity)

      {:error, _reason} ->
        assign(socket, emulator_status: :error)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-[#17202a] text-slate-200 flex flex-col items-center py-8 px-4 select-none">
        <h1 class="text-2xl font-bold tracking-wide text-lime-300 mb-1">
          Game Boy <span class="text-slate-400 font-normal">on the BEAM</span>
        </h1>
        <p class="text-sm text-slate-400 mb-6">
          DMG emulated in Elixir &middot; frames streamed over LiveView
        </p>

        <div
          id="gameboy"
          phx-hook=".GameBoy"
          phx-update="ignore"
          class="rounded-2xl bg-[#c5c0bd] p-6 pb-10 shadow-2xl"
          tabindex="0"
        >
          <div class="rounded-lg bg-[#3f3f44] p-4">
            <canvas
              id="gb-screen"
              width="160"
              height="144"
              class="block w-[480px] max-w-full aspect-[160/144] bg-[#9bbc0f]"
              style="image-rendering: pixelated;"
            ></canvas>
          </div>
          <div class="mt-3 text-center text-[10px] font-bold tracking-widest text-[#2d2a6e]">
            GAME BOY <span class="italic">on Elixir</span>
          </div>
        </div>

        <div
          :if={@roms == []}
          id="rom-empty-state"
          class="mt-6 max-w-lg rounded border border-slate-700 bg-slate-900/70 p-4 text-center text-sm text-slate-300"
        >
          No local Game Boy ROMs were found. Add legally obtained homebrew or personal cartridge dumps to <code class="text-lime-300">priv/roms/</code>.
        </div>

        <div
          :if={@emulator_status == :capacity}
          id="emulator-capacity-state"
          class="mt-6 max-w-lg rounded border border-amber-400/40 bg-amber-950/40 p-4 text-center text-sm text-amber-100"
        >
          Emulator capacity is full. This instance allows {@max_sessions} concurrent sessions.
        </div>

        <div
          :if={@emulator_status == :error}
          id="emulator-error-state"
          class="mt-6 max-w-lg rounded border border-red-400/40 bg-red-950/40 p-4 text-center text-sm text-red-100"
        >
          The emulator could not start for this ROM.
        </div>

        <div :if={@roms != []} class="mt-6 flex flex-wrap items-center justify-center gap-3">
          <form id="rom-select-form" phx-change="select_rom">
            <.input
              id="rom-select"
              type="select"
              name="rom"
              options={@rom_options}
              value={@current_rom}
              class="rounded border border-slate-600 bg-slate-800 px-3 py-1.5 text-sm text-slate-200"
            />
          </form>
          <button
            id="reset-button"
            phx-click="reset"
            class="rounded border border-slate-600 bg-slate-700 px-3 py-1.5 text-sm text-slate-200 transition hover:bg-slate-600"
          >
            Reset
          </button>
          <button
            id="pause-button"
            phx-click="toggle_pause"
            class="rounded border border-slate-600 bg-slate-700 px-3 py-1.5 text-sm text-slate-200 transition hover:bg-slate-600"
          >
            {if @paused, do: "Resume", else: "Pause"}
          </button>
          <span class="text-xs text-slate-400 tabular-nums w-20">{@fps} fps</span>
        </div>

        <div class="mt-6 grid grid-cols-2 gap-x-10 gap-y-1 text-xs text-slate-400">
          <span><kbd class="rounded bg-slate-800 px-1.5 py-0.5 text-[10px]">←→↑↓</kbd> D-pad</span>
          <span><kbd class="rounded bg-slate-800 px-1.5 py-0.5 text-[10px]">Z</kbd> A</span>
          <span><kbd class="rounded bg-slate-800 px-1.5 py-0.5 text-[10px]">Enter</kbd> Start</span>
          <span><kbd class="rounded bg-slate-800 px-1.5 py-0.5 text-[10px]">X</kbd> B</span>
          <span><kbd class="rounded bg-slate-800 px-1.5 py-0.5 text-[10px]">Shift</kbd> Select</span>
          <span class="text-slate-500">Click the screen first for keyboard focus</span>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".GameBoy">
          const PALETTE = [
            [0xe0, 0xf8, 0xd0],
            [0x88, 0xc0, 0x70],
            [0x34, 0x68, 0x56],
            [0x08, 0x18, 0x20],
          ]

          const KEYMAP = {
            ArrowUp: "up",
            ArrowDown: "down",
            ArrowLeft: "left",
            ArrowRight: "right",
            z: "a",
            Z: "a",
            x: "b",
            X: "b",
            Enter: "start",
            Shift: "select",
            Backspace: "select",
          }

          export default {
            mounted() {
              const canvas = this.el.querySelector("canvas")
              this.ctx = canvas.getContext("2d")
              this.imageData = this.ctx.createImageData(160, 144)
              // opaque alpha once
              const px = this.imageData.data
              for (let i = 3; i < px.length; i += 4) px[i] = 255

              this.handleEvent("frame", ({d}) => this.draw(d))

              this.onKey = (e, down) => {
                const btn = KEYMAP[e.key]
                if (!btn) return
                e.preventDefault()
                if (e.repeat) return
                this.pushEvent("joypad", {button: btn, down})
              }
              this.keydown = (e) => this.onKey(e, true)
              this.keyup = (e) => this.onKey(e, false)
              window.addEventListener("keydown", this.keydown)
              window.addEventListener("keyup", this.keyup)
            },

            destroyed() {
              window.removeEventListener("keydown", this.keydown)
              window.removeEventListener("keyup", this.keyup)
            },

            draw(b64) {
              const raw = atob(b64)
              const px = this.imageData.data
              for (let i = 0; i < raw.length; i++) {
                const c = PALETTE[raw.charCodeAt(i) & 3]
                const o = i * 4
                px[o] = c[0]
                px[o + 1] = c[1]
                px[o + 2] = c[2]
              }
              this.ctx.putImageData(this.imageData, 0, 0)
            }
          }
        </script>
      </div>
    </Layouts.app>
    """
  end
end
