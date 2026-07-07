# Front end: streaming frames over LiveView

## The Emulator GenServer (`lib/gb_emu/emulator.ex`)

One `GbEmu.Emulator` runs per admitted viewer. `GbEmu.EmulatorSessions` starts
workers under `GbEmu.EmulatorSupervisor`, monitors the LiveView subscriber, and
enforces the `GB_EMU_MAX_SESSIONS` concurrency limit before a new emulator is
created. The loop:

```
:tick -> Machine.run_frame(gb)
      -> send(subscriber, {:gb_frame, frame, fps})
      -> Process.send_after(self(), :tick, delay)
```

Pacing uses an absolute deadline (`next_frame_at + 16_742 µs` — the real
59.73 Hz frame period) rather than a fixed sleep, so timer jitter and
variable frame cost don't accumulate drift. If emulation falls more than
5 frames behind, the deadline is clamped forward instead of bursting to
catch up.

The emulator GenServer also owns input and lifecycle:

- `button/3` — presses/releases a button on the machine (cast, so input
  never blocks the frame loop).
- `load_rom/2` — builds a fresh machine from another `.gb` file; used by
  the ROM selector and the Reset button.
- `set_paused/2` — stops ticking (drops to a 100 ms idle poll).

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

Adding a legal local `.gb` file to `priv/roms/` makes it appear in the selector
after the app restarts (MBC0/MBC1/MBC5 carts supported). See [roms.md](roms.md)
before adding any binary fixture to the repository.

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

Keyboard handling maps arrows/Z/X/Enter/Shift to Game Boy buttons and
pushes `keydown`/`keyup` separately, so holding a direction works exactly
like holding a real D-pad. `e.repeat` events are dropped — the Game Boy
itself has no key repeat; games implement their own.

## Latency, honestly

Input takes: browser keydown → websocket → LiveView → GenServer cast →
next emulated frame → frame binary → websocket → canvas. On localhost
that's 1-2 frames of latency, comparable to a real console + TV. Over the
public internet it's your ping — this architecture is a deliberate trade:
zero game logic in the client, at the price of round-trip input latency.
