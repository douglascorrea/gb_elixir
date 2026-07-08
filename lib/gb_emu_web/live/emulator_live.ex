defmodule GbEmuWeb.EmulatorLive do
  use GbEmuWeb, :live_view

  alias GbEmu.{Emulator, EmulatorSessions, UploadStore}

  @buttons ~w(up down left right a b start select)
  @max_rom_size 8 * 1024 * 1024
  @max_boot_rom_size 1024
  @upload_keepalive_interval_ms :timer.minutes(5)

  @impl true
  def mount(_params, session, socket) do
    upload_session_id = upload_session_id(session)
    roms = list_roms()
    upload_paths = UploadStore.get_or_create_session(upload_session_id)
    {default_rom, default_rom_path} = default_rom(roms, upload_paths)

    socket =
      socket
      |> assign(
        upload_session_id: upload_session_id,
        upload_paths: upload_paths,
        roms: roms,
        rom_options: Enum.map(roms, &{&1, &1}),
        current_rom: default_rom,
        current_rom_path: default_rom_path,
        boot_rom_path: upload_paths.boot_path,
        uploaded_game?: not is_nil(upload_paths.game_path),
        uploaded_boot?: not is_nil(upload_paths.boot_path),
        fps: 0.0,
        paused: false,
        emulator: nil,
        emulator_status: :idle,
        max_sessions: EmulatorSessions.max_sessions(),
        upload_retention_label: format_duration(UploadStore.ttl_ms()),
        page_title: "Game Boy on the BEAM"
      )
      |> allow_upload(:rom,
        accept: ~w(.gb .gbc),
        max_entries: 1,
        max_file_size: @max_rom_size
      )
      |> allow_upload(:boot_rom,
        accept: ~w(.bin .rom),
        max_entries: 1,
        max_file_size: @max_boot_rom_size
      )

    socket =
      if connected?(socket) do
        schedule_upload_session_keepalive()

        if default_rom_path do
          start_emulator(socket, default_rom_path, upload_paths.boot_path)
        else
          socket
        end
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

  def handle_info(:upload_session_keepalive, socket) do
    UploadStore.touch_session(socket.assigns.upload_session_id)
    schedule_upload_session_keepalive()

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
      rom_path = rom_path(rom)
      Emulator.load_rom(socket.assigns.emulator, rom_path, socket.assigns.boot_rom_path)

      {:noreply,
       assign(socket,
         current_rom: rom,
         current_rom_path: rom_path,
         paused: false
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset", _params, socket) do
    if socket.assigns.emulator && socket.assigns.current_rom_path do
      Emulator.load_rom(
        socket.assigns.emulator,
        socket.assigns.current_rom_path,
        socket.assigns.boot_rom_path
      )
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

  def handle_event("validate_uploads", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"kind" => kind, "ref" => ref}, socket)
      when kind in ["rom", "boot_rom"] do
    upload_name = if kind == "rom", do: :rom, else: :boot_rom
    {:noreply, cancel_upload(socket, upload_name, ref)}
  end

  def handle_event("upload_roms", _params, socket) do
    current_rom_path = socket.assigns.current_rom_path
    {socket, boot_result} = consume_boot_upload(socket)
    {socket, game_result} = consume_game_upload(socket)
    upload_paths = UploadStore.touch_session(socket.assigns.upload_session_id)

    socket =
      socket
      |> assign(upload_paths: upload_paths)
      |> assign(uploaded_game?: not is_nil(upload_paths.game_path))
      |> assign(uploaded_boot?: not is_nil(upload_paths.boot_path))
      |> assign(boot_rom_path: upload_paths.boot_path)
      |> maybe_put_upload_flash(:boot_rom, boot_result)
      |> maybe_put_upload_flash(:rom, game_result)

    socket =
      maybe_load_uploads(socket, game_result, boot_result, upload_paths, current_rom_path)

    {:noreply, socket}
  end

  defp upload_session_id(%{"upload_session_id" => session_id}) when is_binary(session_id) do
    session_id
  end

  defp upload_session_id(_session) do
    Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  defp schedule_upload_session_keepalive do
    Process.send_after(self(), :upload_session_keepalive, @upload_keepalive_interval_ms)
  end

  defp list_roms do
    Path.join(:code.priv_dir(:gb_emu), "roms")
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".gb"))
    |> Enum.sort()
  end

  defp rom_path(name), do: Path.join([:code.priv_dir(:gb_emu), "roms", name])

  defp default_rom(_roms, %{game_path: game_path}) when is_binary(game_path) do
    {"Uploaded ROM", game_path}
  end

  defp default_rom(roms, _upload_paths) do
    case List.first(roms) do
      nil -> {nil, nil}
      rom -> {rom, rom_path(rom)}
    end
  end

  defp start_or_reload_emulator(
         %{assigns: %{emulator: emulator}} = socket,
         rom_path,
         boot_rom_path
       )
       when is_pid(emulator) do
    Emulator.load_rom(emulator, rom_path, boot_rom_path)
    assign(socket, emulator_status: :running)
  end

  defp start_or_reload_emulator(socket, rom_path, boot_rom_path) do
    start_emulator(socket, rom_path, boot_rom_path)
  end

  defp start_emulator(socket, rom_path, boot_rom_path) do
    case EmulatorSessions.start_emulator(
           subscriber: self(),
           rom_path: rom_path,
           boot_rom_path: boot_rom_path
         ) do
      {:ok, pid} ->
        assign(socket, emulator: pid, emulator_status: :running)

      {:error, :capacity} ->
        assign(socket, emulator_status: :capacity)

      {:error, _reason} ->
        assign(socket, emulator_status: :error)
    end
  end

  defp maybe_load_uploads(
         socket,
         :ok,
         _boot_result,
         %{game_path: game_path} = paths,
         _current_path
       )
       when is_binary(game_path) do
    socket
    |> assign(
      current_rom: "Uploaded ROM",
      current_rom_path: game_path,
      paused: false
    )
    |> start_or_reload_emulator(game_path, paths.boot_path)
  end

  defp maybe_load_uploads(socket, _game_result, :ok, paths, current_rom_path)
       when is_binary(current_rom_path) do
    socket
    |> assign(paused: false)
    |> start_or_reload_emulator(current_rom_path, paths.boot_path)
  end

  defp maybe_load_uploads(socket, _game_result, _boot_result, _paths, _current_path), do: socket

  defp format_duration(milliseconds) when is_integer(milliseconds) and milliseconds >= 0 do
    cond do
      milliseconds >= 3_600_000 and rem(milliseconds, 3_600_000) == 0 ->
        plural(div(milliseconds, 3_600_000), "hour")

      milliseconds >= 60_000 and rem(milliseconds, 60_000) == 0 ->
        plural(div(milliseconds, 60_000), "minute")

      milliseconds >= 1000 ->
        plural(ceil_div(milliseconds, 1000), "second")

      true ->
        "#{milliseconds} milliseconds"
    end
  end

  defp ceil_div(0, _denominator), do: 0
  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)

  defp plural(1, unit), do: "1 #{unit}"
  defp plural(count, unit), do: "#{count} #{unit}s"

  defp consume_game_upload(socket) do
    results =
      consume_uploaded_entries(socket, :rom, fn %{path: path}, _entry ->
        if valid_game_rom?(path) do
          {:ok, {:ok, UploadStore.put_game!(socket.assigns.upload_session_id, path)}}
        else
          {:ok, {:error, :invalid_rom}}
        end
      end)

    {socket, upload_result(results)}
  end

  defp consume_boot_upload(socket) do
    results =
      consume_uploaded_entries(socket, :boot_rom, fn %{path: path}, _entry ->
        if File.stat!(path).size == 0x100 do
          {:ok, {:ok, UploadStore.put_boot!(socket.assigns.upload_session_id, path)}}
        else
          {:ok, {:error, :invalid_boot_rom}}
        end
      end)

    {socket, upload_result(results)}
  end

  defp upload_result([]), do: :none
  defp upload_result([{:ok, _paths} | _rest]), do: :ok
  defp upload_result([{:error, reason} | _rest]), do: {:error, reason}

  defp valid_game_rom?(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size >= 0x150 and size <= @max_rom_size
      _ -> false
    end
  end

  defp maybe_put_upload_flash(socket, _kind, :none), do: socket
  defp maybe_put_upload_flash(socket, _kind, :ok), do: socket

  defp maybe_put_upload_flash(socket, :rom, {:error, :invalid_rom}) do
    put_flash(socket, :error, "Game ROM must be a valid .gb or .gbc file with a Game Boy header.")
  end

  defp maybe_put_upload_flash(socket, :boot_rom, {:error, :invalid_boot_rom}) do
    put_flash(socket, :error, "Boot ROM must be a 256-byte DMG boot ROM dump.")
  end

  defp upload_error_to_string(:too_large), do: "File is too large."
  defp upload_error_to_string(:too_many_files), do: "Upload only one file at a time."
  defp upload_error_to_string(:not_accepted), do: "File type is not accepted."

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
          :if={is_nil(@current_rom_path)}
          id="rom-empty-state"
          class="mt-6 max-w-lg rounded border border-slate-700 bg-slate-900/70 p-4 text-center text-sm text-slate-300"
        >
          No ROM is loaded. Upload a legally obtained homebrew ROM or personal cartridge dump to play in this browser session.
        </div>

        <form
          id="rom-upload-form"
          phx-change="validate_uploads"
          phx-submit="upload_roms"
          class="mt-6 w-full max-w-xl rounded border border-slate-700 bg-slate-900/70 p-4 text-sm text-slate-200"
        >
          <div class="grid gap-4 sm:grid-cols-2">
            <div phx-drop-target={@uploads.rom.ref}>
              <label for={@uploads.rom.ref} class="mb-2 block font-semibold text-lime-300">
                Game ROM
              </label>
              <.live_file_input upload={@uploads.rom} class="sr-only" />
              <label
                id="game-rom-upload-button"
                for={@uploads.rom.ref}
                class="inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded border border-lime-300/60 bg-lime-300 px-3 py-2 text-sm font-semibold text-slate-950 transition hover:bg-lime-200"
              >
                <.icon name="hero-arrow-up-tray" class="size-4" /> Upload game ROM
              </label>
              <div :for={entry <- @uploads.rom.entries} class="mt-2 text-xs text-slate-400">
                <div class="flex items-center justify-between gap-2">
                  <span>{entry.client_name}</span>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-kind="rom"
                    phx-value-ref={entry.ref}
                    class="text-slate-500 transition hover:text-slate-200"
                  >
                    Cancel
                  </button>
                </div>
                <progress class="h-1 w-full" value={entry.progress} max="100">
                  {entry.progress}%
                </progress>
                <p :for={err <- upload_errors(@uploads.rom, entry)} class="text-red-300">
                  {upload_error_to_string(err)}
                </p>
              </div>
              <p :for={err <- upload_errors(@uploads.rom)} class="mt-2 text-xs text-red-300">
                {upload_error_to_string(err)}
              </p>
            </div>

            <div phx-drop-target={@uploads.boot_rom.ref}>
              <label for={@uploads.boot_rom.ref} class="mb-2 block font-semibold text-lime-300">
                Boot ROM
              </label>
              <.live_file_input upload={@uploads.boot_rom} class="sr-only" />
              <label
                id="boot-rom-upload-button"
                for={@uploads.boot_rom.ref}
                class="inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded border border-lime-300/60 bg-lime-300 px-3 py-2 text-sm font-semibold text-slate-950 transition hover:bg-lime-200"
              >
                <.icon name="hero-arrow-up-tray" class="size-4" /> Upload boot ROM
              </label>
              <div :for={entry <- @uploads.boot_rom.entries} class="mt-2 text-xs text-slate-400">
                <div class="flex items-center justify-between gap-2">
                  <span>{entry.client_name}</span>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-kind="boot_rom"
                    phx-value-ref={entry.ref}
                    class="text-slate-500 transition hover:text-slate-200"
                  >
                    Cancel
                  </button>
                </div>
                <progress class="h-1 w-full" value={entry.progress} max="100">
                  {entry.progress}%
                </progress>
                <p :for={err <- upload_errors(@uploads.boot_rom, entry)} class="text-red-300">
                  {upload_error_to_string(err)}
                </p>
              </div>
              <p :for={err <- upload_errors(@uploads.boot_rom)} class="mt-2 text-xs text-red-300">
                {upload_error_to_string(err)}
              </p>
            </div>
          </div>

          <div class="mt-4 flex flex-wrap items-center justify-between gap-3 text-xs text-slate-400">
            <span>
              {if @uploaded_game?,
                do: "Game ROM stored for this browser session.",
                else: "No game ROM stored."}
              {if @uploaded_boot?, do: " Boot ROM stored.", else: " Using open boot stub."}
            </span>
            <button
              type="submit"
              class="rounded border border-lime-300/60 bg-lime-300 px-3 py-1.5 font-semibold text-slate-950 transition hover:bg-lime-200"
            >
              Load uploads
            </button>
          </div>
          <p class="mt-3 text-xs text-slate-500">
            Uploaded files are private to this signed browser session and are deleted after {@upload_retention_label} without this browser reconnecting.
          </p>
        </form>

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

        <div
          :if={@roms != [] or @current_rom_path}
          class="mt-6 flex flex-wrap items-center justify-center gap-3"
        >
          <form id="rom-select-form" phx-change="select_rom">
            <.input
              :if={@roms != []}
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
              this.keepSessionAlive = () => {
                fetch("/upload-session/keepalive", {
                  method: "GET",
                  credentials: "same-origin",
                  cache: "no-store",
                }).catch(() => {})
              }
              this.keepSessionAlive()
              this.keepaliveTimer = window.setInterval(this.keepSessionAlive, 5 * 60 * 1000)

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
              window.clearInterval(this.keepaliveTimer)
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
