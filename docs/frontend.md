# Front end: streaming frames over LiveView

## The Emulator GenServer (`lib/gb_emu/emulator.ex`)

One `GbEmu.Emulator` runs per admitted viewer. `GbEmu.EmulatorSessions` starts
workers under `GbEmu.EmulatorSupervisor`, monitors the LiveView subscriber, and
enforces the `GB_EMU_MAX_SESSIONS` concurrency limit before a new emulator is
created. The loop:

```
{:tick, token} -> Machine.run_frame(gb)
               -> send(subscriber, {:gb_frame, frame, fps})
               -> Process.send_after(self(), {:tick, next_token}, delay)
```

Pacing uses an absolute deadline (`next_frame_at + 16_742 µs` — the real
59.73 Hz frame period) rather than a fixed sleep, so timer jitter and
variable frame cost don't accumulate drift. If emulation falls more than
5 frames behind, the deadline is clamped forward instead of bursting to
catch up. Timer tokens make already-delivered stale messages harmless when
pause, attach, resume, or reload replaces the active timer.

The emulator GenServer also owns input and lifecycle:

- `button/3` — presses/releases a button on the machine (cast, so input
  never blocks the frame loop).
- `load_rom/2` — builds a fresh machine from another `.gb` file; used by
  the ROM selector, uploaded ROMs, uploaded boot ROMs, and the Reset button.
- `set_paused/2` — cancels ticking while paused; it cannot resume a debugger-
  attached machine.
- `debug_attach/2` — synchronously cancels pacing and returns a projected
  snapshot of the authoritative machine without resetting it.
- `debug_command/3` — runs a bounded instruction/PPU/scanline/frame/restart
  command while attached.
- `debug_memory/2` — reads another projected 256-byte memory window without
  advancing the machine.
- `debug_resume/1` — detaches tracing and starts exactly one paced timer chain.

## The LiveView (`lib/gb_emu_web/live/emulator_live.ex`)

The LiveView is intentionally thin. Frames arrive as messages and go
straight out as events; no frame data ever touches assigns (which would
diff and re-render the DOM):

```elixir
def handle_info({:gb_frame, frame, fps}, socket) do
  socket
  |> push_event("frame", %{d: Base.encode64(frame)})
  |> assign(fps: fps)
  ...
end
```

The wire format is 23,040 bytes of 2-bit shades, roughly 30 KB after base64 and
about 1.8 MB/s at 60 fps. That is reasonable for localhost/LAN study, but it is
why unrestricted public hosting needs authentication, upstream rate limits, or
another deployment-specific guard. Sending shades instead of RGBA keeps the
payload 4x smaller and leaves colorization to the client.

Events flowing the other way:

- `"joypad"` — `%{button: "a", down: true}` from the JS hook, validated
  against a whitelist and forwarded to the GenServer.
- `"select_rom"` / `"reset"` / `"toggle_pause"` — UI controls. ROM names
  are validated against the actual directory listing of `priv/roms/`, so
  the client can't request arbitrary file paths.
- `"upload_roms"` — stores a legal game ROM and optional 256-byte boot ROM
  through `GbEmu.UploadStore`, then starts or reloads the emulator from those
  session-scoped paths.
- `"debug_attach"`, `"debug_step"`, `"debug_step_10"`, `"debug_ppu"`,
  `"debug_scanline"`, `"debug_frame"`, `"debug_restart"`, `"debug_memory"`,
  and `"debug_resume"` — explicit synchronous debugger actions. Normal frame
  messages never build debugger snapshots.

Adding a legal local `.gb` file to `priv/roms/` makes it appear in the selector
after the app restarts (MBC0/MBC1/MBC5 carts supported). See [roms.md](roms.md)
before adding any binary fixture to the repository.

Page Reset, ROM selection, and uploads use the normal machine-construction path:
the minimal source fast-starts at `$0100`, while a file source executes from
`$0000`. Debugger `"debug_restart"` is deliberately different: it rebuilds the
active combination in cold mode at `$0000` and remains paused for stepping.

## Browser upload sessions

`GbEmuWeb.UploadSession` creates a random id in the signed Phoenix session.
`GbEmu.UploadStore` stores uploads below `GB_EMU_UPLOAD_ROOT` with `0700`
directories and `0600` files. The LiveView and a tiny browser keepalive endpoint
refresh the session's `.last_seen` marker while the page remains open in the
same browser.

`GB_EMU_UPLOAD_TTL_MS` is the deployment flag for the inactive-session window.
It controls both the signed browser-session cookie max age and the server-side
cleanup sweep. The default is `7200000` milliseconds (two hours), but downstream
deployments can choose their own value.

## The canvas hook (colocated JS in `emulator_live.ex`)

The hook is defined next to the markup with Phoenix 1.8's
`Phoenix.LiveView.ColocatedHook` — no separate JS file to keep in sync.
Its container has `phx-update="ignore"` so LiveView never repaints the
canvas DOM node out from under it.

Drawing path per frame:

1. `atob` the base64 payload (raw shade bytes).
2. Map each shade through the classic DMG green palette into a reusable
   `ImageData` (alpha initialized once).
3. `putImageData` onto the 160x144 canvas; CSS scales it up with
   `image-rendering: pixelated` for crisp fat pixels.

Keyboard handling maps arrows/Z/X to held Game Boy buttons and pushes their
`keydown`/`keyup` state separately, so holding a direction works like holding a
real D-pad. Start (`Enter`) and Select (`Shift`, with `Backspace` as a fallback)
are 180 ms pulses initiated on keydown; this prevents a dropped keyup from
leaving either button stuck in embedded browser/webview environments.
`e.repeat` events are dropped — the Game Boy itself has no key repeat; games
implement their own.

## The debugger sidebar

`GbEmuWeb.DebuggerComponents` renders a stateless sibling `<aside>` outside the
ignored `#gameboy` canvas container. It is sticky and independently scrollable
on desktop, then stacks below the console at narrower widths. The memory panel
is the largest surface; trace rows use a LiveView stream reconciled from the
authoritative, bounded snapshot history.

The aside carries `data-debug-ui`. The capture-phase keyboard handler checks
`target.closest("[data-debug-ui]")` before mapping a key, so arrows and Enter
used in memory fields or debugger buttons cannot become D-pad or Start input.

Instruction, trace, and memory-activity links come from compile-time
`GbEmu.Debugger.SourceMap` metadata. The client receives repository-relative
paths, positive line numbers, and GitHub URLs, not local absolute paths. See
[debugger.md](debugger.md) for control semantics, colors, source-link versioning,
and history limits.

## Latency, honestly

Input takes: browser keydown → websocket → LiveView → GenServer cast →
next emulated frame → frame binary → websocket → canvas. On localhost
that's 1-2 frames of latency, comparable to a real console + TV. Over the
public internet it's your ping — this architecture is a deliberate trade:
zero game logic in the client, at the price of round-trip input latency.
