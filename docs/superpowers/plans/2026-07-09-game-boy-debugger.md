# Game Boy Debugger Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an integrated LiveView debugger that pauses the authoritative Game Boy machine, steps assembly from either boot source, and explains CPU, memory, PPU, timer, and Elixir source flow.

**Architecture:** Extract one coordinated instruction boundary in `GbEmu.Machine`, then wrap it with opt-in trace capture and compact debugger snapshots. Serialize debugger commands through the existing `GbEmu.Emulator` GenServer and render them in a responsive sibling sidebar outside the ignored canvas subtree.

**Tech Stack:** Elixir 1.15+, OTP GenServer, Phoenix 1.8, LiveView 1.2, HEEx, Tailwind CSS v4, ExUnit, LazyHTML.

## Global Constraints

- Preserve normal fast-start play at `$0100` when the open boot stub is used.
- A debugger step is one CPU instruction, interrupt service, or HALT boundary; it is not one T-cycle.
- Every instruction boundary advances PPU, timer, and serial state by the returned exact T-cycle count.
- Debug both the open boot stub and a 256-byte browser/env boot ROM from `$0000`.
- Never expose `%GbEmu.GB{}` or unbounded history to LiveView.
- Cap trace history at 200 instruction records and memory windows at 256 bytes.
- Do not add dependencies or proprietary ROM/BIOS fixtures.
- Do not add HTTP behavior; the debugger communicates through the existing LiveView connection.
- Use stable DOM ids and LiveView selector-based tests.
- Run `mix precommit` after all changes.

---

## File structure

- Create `lib/gb_emu/debugger.ex`: command runner, trace assembly, boundary limits, and public debugger facade.
- Create `lib/gb_emu/debugger/disassembler.ex`: SM83 instruction decoding and handler classification.
- Create `lib/gb_emu/debugger/source_map.ex`: compile-time source path/line resolution and GitHub URLs.
- Create `lib/gb_emu/debugger/trace.ex`: process-local, opt-in event collector.
- Create `lib/gb_emu/debugger/snapshot.ex`: compact CPU/peripheral/memory display data.
- Create `lib/gb_emu_web/components/debugger_components.ex`: stateless HEEx function components for the sidebar.
- Create `test/gb_emu/debugger_test.exs`: cold boot, tracing, disassembly, source, memory, and boundary tests.
- Create `test/gb_emu/emulator_debugger_test.exs`: serialized GenServer debugger API tests.
- Create `docs/debugger.md`: user and codebase learning guide.
- Modify `lib/gb_emu/boot_rom.ex`: executable end-of-overlay open stub layout.
- Modify `lib/gb_emu/gb.ex`: fast/cold boot mode and minimal-stub identity.
- Modify `lib/gb_emu/bus.ex`: peek path, opt-in memory events, and open-stub compatibility handoff.
- Modify `lib/gb_emu/cpu.ex`: expose enough step classification metadata for interrupt/HALT traces.
- Modify `lib/gb_emu/machine.ex`: shared instruction boundary and traced step.
- Modify `lib/gb_emu/ppu.ex`: grouped scanline memory activity and transition events.
- Modify `lib/gb_emu/emulator.ex`: attach/command/memory/resume calls and debug history.
- Modify `lib/gb_emu_web/live/emulator_live.ex`: debugger assigns/events, responsive layout, and keyboard isolation.
- Modify `test/gb_emu/machine_test.exs`: preserve fast boot and coordinated step contracts.
- Modify `test/gb_emu_web/live/emulator_live_test.exs`: debugger surface selectors.
- Modify `README.md`, `docs/README.md`, `docs/architecture.md`, `docs/frontend.md`, and `docs/roms.md`: debugger links and accurate boot behavior.

---

### Task 1: Shared instruction boundary and truthful cold boot

**Files:**
- Modify: `lib/gb_emu/boot_rom.ex`
- Modify: `lib/gb_emu/gb.ex`
- Modify: `lib/gb_emu/bus.ex`
- Modify: `lib/gb_emu/machine.ex`
- Modify: `test/gb_emu/machine_test.exs`
- Test: `test/gb_emu/debugger_test.exs`

**Interfaces:**
- Produces: `Machine.new(boot, rom, opts \\ []) :: GB.t()`.
- Produces: `Machine.step_instruction(gb) :: {GB.t(), pos_integer()}`.
- Produces: cold boot option `boot_mode: :cold`; default remains `:fast`.
- Produces: `%GB{boot_kind: :minimal | :file, boot_mode: :fast | :cold, debug_trace?: boolean()}`.
- Consumes: existing `CPU.step/1`, `PPU.step/2`, `Timer.step/2`, and serial behavior.

- [ ] **Step 1: Write failing cold-boot and shared-step tests**

Add tests that describe both preserved and new behavior:

```elixir
test "fast open boot preserves the existing post-boot start" do
  gb = Machine.new(BootRom.minimal(), test_rom())
  assert gb.pc == 0x0100
  refute gb.boot_enabled
end

test "cold open boot executes three instructions and hands off at 0100" do
  gb = Machine.new(BootRom.minimal(), test_rom(), boot_mode: :cold)
  assert gb.pc == 0x0000
  assert gb.boot_enabled

  {gb, 16} = Machine.step_instruction(gb)
  assert gb.pc == 0x00FC
  {gb, 8} = Machine.step_instruction(gb)
  assert gb.pc == 0x00FE
  {gb, 12} = Machine.step_instruction(gb)

  assert gb.pc == 0x0100
  refute gb.boot_enabled
  assert gb.sp == 0xFFFE
  assert gb.lcdc == 0x91
end
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `mix test test/gb_emu/machine_test.exs test/gb_emu/debugger_test.exs`

Expected: failure because `Machine.new/3` and `Machine.step_instruction/1` do not exist and the current stub bytes are not executable through unmap.

- [ ] **Step 3: Implement cold boot without changing the default**

Use this public shape:

```elixir
def new(boot, rom, opts \\ []), do: GB.new(boot, rom, opts)

def step_instruction(gb) do
  {gb, cycles} = CPU.step(gb)
  gb = PPU.step(gb, cycles)
  gb = Timer.step(gb, cycles)
  gb = step_serial(gb, cycles)
  {gb, cycles}
end
```

Make `run_frame/1` call `step_instruction/1`. Lay out the minimal stub as `JP $00FC`, `LD A,$01`, `LDH ($FF50),A`. In `GB.new/3`, only merge `BootRom.post_boot_state/0` when `boot_mode == :fast` and the boot binary is minimal. On the cold minimal `$FF50` write, merge the compatibility state while preserving `pc`, atomics, ROM, boot data, cartridge banking, frame storage, and the cold-boot identity fields.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `mix test test/gb_emu/machine_test.exs test/gb_emu/debugger_test.exs`

Expected: all focused tests pass; the existing fast-start assertion remains unchanged.

- [ ] **Step 5: Commit the execution seam**

```bash
git add lib/gb_emu/boot_rom.ex lib/gb_emu/gb.ex lib/gb_emu/bus.ex lib/gb_emu/machine.ex test/gb_emu/machine_test.exs test/gb_emu/debugger_test.exs
git commit -m "feat: add cold boot instruction stepping"
```

---

### Task 2: Disassembly, memory traces, snapshots, and source lines

**Files:**
- Create: `lib/gb_emu/debugger.ex`
- Create: `lib/gb_emu/debugger/disassembler.ex`
- Create: `lib/gb_emu/debugger/source_map.ex`
- Create: `lib/gb_emu/debugger/trace.ex`
- Create: `lib/gb_emu/debugger/snapshot.ex`
- Modify: `lib/gb_emu/bus.ex`
- Modify: `lib/gb_emu/cpu.ex`
- Modify: `lib/gb_emu/ppu.ex`
- Modify: `lib/gb_emu/machine.ex`
- Test: `test/gb_emu/debugger_test.exs`

**Interfaces:**
- Consumes: `Machine.step_instruction/1` from Task 1.
- Produces: `Debugger.step(gb) :: {GB.t(), map()}`.
- Produces: `Debugger.run(gb, command) :: {:ok, GB.t(), [map()], map()} | {:error, atom(), GB.t(), [map()], map()}`.
- Produces commands: `:instruction`, `{:steps, 10}`, `:ppu_event`, `:scanline`, and `:frame`.
- Produces: `Snapshot.build(gb, keyword()) :: map()` with a 256-byte memory window.
- Produces: `Disassembler.decode(gb) :: map()`.
- Produces: `SourceMap.location(component, selector) :: map()`.

- [ ] **Step 1: Write failing debugger facade tests**

Cover decoded assembly, register deltas, memory reads/writes, PPU/timer changes, source locations, window clamping, and history limits:

```elixir
test "a traced store explains instruction memory and source flow" do
  rom = test_rom() |> put_bytes(0x100, <<0xEA, 0x00, 0xC0>>)
  gb = %{Machine.new(BootRom.minimal(), rom) | a: 0x42}

  {gb, trace} = Debugger.step(gb)

  assert trace.pc_before == 0x0100
  assert trace.pc_after == 0x0103
  assert trace.mnemonic == "LD ($C000), A"
  assert trace.cycles == 16
  assert Enum.any?(trace.memory, &match?(%{operation: :write, address: 0xC000, after: 0x42}, &1))
  assert Enum.any?(trace.sources, &(&1.path == "lib/gb_emu/cpu.ex" and is_integer(&1.line)))
  assert Bus.read8(gb, 0xC000) == 0x42
end

test "snapshot clamps and aligns a 256-byte memory window" do
  snapshot = Snapshot.build(new_machine(), memory_start: 0xFFF8)
  assert snapshot.memory.start == 0xFF00
  assert length(snapshot.memory.bytes) == 256
end
```

- [ ] **Step 2: Run debugger tests and verify RED**

Run: `mix test test/gb_emu/debugger_test.exs`

Expected: failure because the debugger modules and trace API do not exist.

- [ ] **Step 3: Implement the opt-in trace collector and Bus events**

Use a process-local collector so nested CPU/Bus/PPU functions can emit ordered events without putting collector data into LiveView:

```elixir
def capture(fun) do
  Process.put(@key, [])

  try do
    result = fun.()
    {result, Process.get(@key, []) |> Enum.reverse()}
  after
    Process.delete(@key)
  end
end

def record(%{debug_trace?: true}, event) do
  Process.put(@key, [event | Process.get(@key, [])])
  :ok
end

def record(_gb, _event), do: :ok
```

Refactor `Bus.read8/2` around a non-tracing `peek8/2`. For traced reads record address, value, region, semantic label, and Bus source location. For writes capture old value, requested value, resulting value, region, and side effects. Emit grouped DMA and PPU scanline-range events rather than one primary row per pixel fetch.

- [ ] **Step 4: Implement disassembly and compile-time source mapping**

Decode regular and CB-prefixed SM83 opcodes algorithmically. Every decode returns at least:

```elixir
%{
  kind: :instruction,
  pc: 0x0100,
  opcode: 0xEA,
  bytes: [0xEA, 0x00, 0xC0],
  length: 3,
  mnemonic: "LD ($C000), A",
  handler: {:cpu, "defp exec(0xEA"}
}
```

`SourceMap` declares emulator source files as `@external_resource`, reads them at compile time, and embeds only selector-to-line maps. Raise during compilation if a required selector is absent so deployed source links cannot silently point to line zero.

- [ ] **Step 5: Implement traced stepping, deltas, runners, and snapshots**

`Debugger.step/1` captures the decoded instruction and before-state, temporarily enables `debug_trace?`, calls `Machine.step_instruction/1`, disables tracing, and builds the final trace. Classify interrupt and HALT boundaries from pre-step CPU state.

Boundary commands loop through `Debugger.step/1`, retain at most 200 traces, and enforce ceilings:

```elixir
@limits %{ppu_event: 10_000, scanline: 10_000, frame: 100_000}
@history_limit 200
```

`Snapshot.build/2` returns display maps only. It aligns/clamps the memory start, reads exactly 256 bytes using `Bus.peek8/2`, and marks PC, SP, newest reads, and newest writes.

- [ ] **Step 6: Run debugger and machine tests and verify GREEN**

Run: `mix test test/gb_emu/debugger_test.exs test/gb_emu/machine_test.exs`

Expected: all tests pass with no warnings.

- [ ] **Step 7: Commit the debugger core**

```bash
git add lib/gb_emu/debugger.ex lib/gb_emu/debugger lib/gb_emu/bus.ex lib/gb_emu/cpu.ex lib/gb_emu/ppu.ex lib/gb_emu/machine.ex test/gb_emu/debugger_test.exs
git commit -m "feat: trace Game Boy instructions and memory"
```

---

### Task 3: Serialize debugger commands through the emulator process

**Files:**
- Modify: `lib/gb_emu/emulator.ex`
- Test: `test/gb_emu/emulator_debugger_test.exs`

**Interfaces:**
- Consumes: `Debugger.run/2` and `Snapshot.build/2` from Task 2.
- Produces: `Emulator.debug_attach(pid, memory_start \\ 0x0000)`.
- Produces: `Emulator.debug_command(pid, command, memory_start \\ 0x0000)`.
- Produces: `Emulator.debug_memory(pid, memory_start)`.
- Produces: `Emulator.debug_resume(pid)`.
- Returns: `{:ok, %{snapshot: map(), traces: [map()], meta: map()}} | {:error, atom()}`.

- [ ] **Step 1: Write failing GenServer behavior tests**

Start the real emulator with `start_supervised!/1` and a temporary synthetic ROM. Assert attach pauses the machine, a step changes PC exactly once, restart chooses cold boot at `$0000`, memory navigation does not execute, history caps at 200, and resume exits debugging.

```elixir
test "attach step restart and resume operate on one authoritative machine", %{rom_path: path} do
  pid = start_supervised!({Emulator, subscriber: self(), rom_path: path})

  assert {:ok, attached} = Emulator.debug_attach(pid, 0x0100)
  assert attached.snapshot.mode == :debugging

  assert {:ok, stepped} = Emulator.debug_command(pid, :instruction, 0x0100)
  assert length(stepped.traces) == 1

  assert {:ok, restarted} = Emulator.debug_command(pid, :restart, 0x0000)
  assert restarted.snapshot.cpu.pc == 0x0000
  assert restarted.snapshot.boot.enabled

  assert :ok = Emulator.debug_resume(pid)
end
```

- [ ] **Step 2: Run the GenServer tests and verify RED**

Run: `mix test test/gb_emu/emulator_debugger_test.exs`

Expected: failure because the debugger client functions and call handlers do not exist.

- [ ] **Step 3: Implement the serialized debugger API**

Persist `rom_path`, `boot_rom_path`, `debug_attached`, and `debug_history` in emulator state. `debug_attach` sets `paused: true`; debug commands reject unattached calls. `:restart` rebuilds with `boot_mode: :cold` and clears history. Normal `load_rom` and Reset return to fast mode and clear stale debugger state. `debug_resume` clears attach state, sets `paused: false`, resets the pacing deadline, and schedules the next tick.

All public calls use finite timeouts. `:frame` may use a longer timeout than simple step/memory calls but remains bounded.

- [ ] **Step 4: Run focused GenServer and core tests and verify GREEN**

Run: `mix test test/gb_emu/emulator_debugger_test.exs test/gb_emu/debugger_test.exs`

Expected: all tests pass and no process leaks appear.

- [ ] **Step 5: Commit the debugger process API**

```bash
git add lib/gb_emu/emulator.ex test/gb_emu/emulator_debugger_test.exs
git commit -m "feat: expose serialized emulator debug commands"
```

---

### Task 4: Build the responsive LiveView debugger sidebar

**Files:**
- Create: `lib/gb_emu_web/components/debugger_components.ex`
- Modify: `lib/gb_emu_web.ex`
- Modify: `lib/gb_emu_web/live/emulator_live.ex`
- Modify: `assets/css/app.css`
- Modify: `test/gb_emu_web/live/emulator_live_test.exs`

**Interfaces:**
- Consumes: `Emulator.debug_attach/2`, `debug_command/3`, `debug_memory/2`, and `debug_resume/1`.
- Produces events: `debug_attach`, `debug_step`, `debug_step_10`, `debug_ppu`, `debug_scanline`, `debug_frame`, `debug_restart`, `debug_memory`, and `debug_resume`.
- Produces stable ids: `#debug-sidebar`, `#debug-attach`, `#debug-step`, `#debug-step-10`, `#debug-next-ppu`, `#debug-next-scanline`, `#debug-next-frame`, `#debug-restart`, `#debug-resume`, `#debug-instruction`, `#debug-registers`, `#debug-memory-form`, `#debug-memory-grid`, `#debug-ppu`, and `#debug-trace`.

- [ ] **Step 1: Write failing LiveView surface tests**

Use LiveView selectors rather than raw HTML assertions:

```elixir
test "renders an accessible debugger workbench", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/")

  assert has_element?(view, "#debug-sidebar[data-debug-ui]")
  assert has_element?(view, "#debug-attach")
  assert has_element?(view, "#debug-step[disabled]")
  assert has_element?(view, "#debug-memory-grid")
  assert has_element?(view, "#debug-ppu")
  assert has_element?(view, "#debug-trace[phx-update=stream]")
end
```

Keep command semantics in the GenServer tests from Task 3. In this file, test the no-ROM disabled state and render `DebuggerComponents.sidebar/1` with a representative snapshot to cover attached-state selectors without starting a second emulator lifecycle through LiveView.

- [ ] **Step 2: Run the LiveView tests and verify RED**

Run: `mix test test/gb_emu_web/live/emulator_live_test.exs`

Expected: selector failures because no debugger markup exists.

- [ ] **Step 3: Implement debugger assigns and event handlers**

Mount compact defaults and initialize an empty trace stream. Normalize debugger responses through one helper that assigns the snapshot and streams returned traces. Parse memory addresses as hexadecimal without `String.to_atom/1`. Invalid input leaves the previous snapshot visible and sets a concise error.

Use synchronous emulator calls only inside explicit user events; frame messages retain the existing direct canvas push path.

- [ ] **Step 4: Implement the function-component sidebar**

Keep the visual code out of the already large LiveView. Build stateless function components for toolbar, instruction, registers, memory, peripherals, source trail, and trace rows. Use a desktop sticky aside and stacked mobile layout. Make memory the largest panel and apply `select-text` to code/data surfaces.

Wrap the game column and `<aside>` in a responsive grid. Keep the sidebar outside `#gameboy[phx-update=ignore]`. Mark the aside with `data-debug-ui` and update `.GameBoy`'s `typingTarget`/keyboard guard to return true for `el.closest("[data-debug-ui]")`.

- [ ] **Step 5: Run LiveView tests and asset compilation**

Run: `mix test test/gb_emu_web/live/emulator_live_test.exs`

Expected: all LiveView tests pass.

Run: `mix assets.build`

Expected: Tailwind and esbuild exit successfully with no HEEx or colocated-hook compilation errors.

- [ ] **Step 6: Commit the debugger UI**

```bash
git add lib/gb_emu_web/components/debugger_components.ex lib/gb_emu_web.ex lib/gb_emu_web/live/emulator_live.ex assets/css/app.css test/gb_emu_web/live/emulator_live_test.exs
git commit -m "feat: add LiveView Game Boy debugger sidebar"
```

---

### Task 5: Documentation, regression verification, and local visual check

**Files:**
- Create: `docs/debugger.md`
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/frontend.md`
- Modify: `docs/roms.md`
- Review: all files changed in Tasks 1-4

**Interfaces:**
- Consumes: completed debugger behavior from Tasks 1-4.
- Produces: accurate user/developer documentation and a fully verified branch.

- [ ] **Step 1: Write the debugger guide and correct boot documentation**

Document:

- attach versus restart-from-boot;
- open stub versus file boot source;
- instruction boundary versus individual T-cycles;
- each execution control;
- register, PPU, memory colors, and source links;
- bounded trace/history behavior; and
- lawful ROM/BIOS policy.

Correct any wording that says normal fast start literally executes the open stub.

- [ ] **Step 2: Run focused tests while fixing any regressions**

Run: `mix test test/gb_emu/debugger_test.exs test/gb_emu/emulator_debugger_test.exs test/gb_emu/machine_test.exs test/gb_emu_web/live/emulator_live_test.exs`

Expected: all focused tests pass. If an existing test fails and its behavior was not intentionally changed, fix production code rather than weakening the test.

- [ ] **Step 3: Run the required full verification**

Run: `mix precommit`

Expected: compilation with warnings as errors succeeds, formatting is clean, unused dependencies are absent, and the full ExUnit suite reports zero failures.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 4: Perform a local browser check**

Start the app in a detached `tmux` session if no local server is running. Verify at desktop and narrow widths:

- existing upload/game controls remain usable;
- attach pauses without resetting;
- restart begins at `$0000` for the open stub;
- three open-stub steps reach `$0100` with the handoff called out;
- memory navigation changes the displayed 256-byte window without stepping;
- source links have paths and positive line numbers;
- debugger buttons do not send joypad Enter/arrows; and
- resume returns to frame updates.

- [ ] **Step 5: Commit documentation and verification fixes**

```bash
git add README.md docs lib test assets
git commit -m "docs: explain the integrated Game Boy debugger"
```

- [ ] **Step 6: Review the complete branch**

Inspect `git diff origin/master...HEAD`, verify every design goal maps to implementation/tests, and run the `code-review` skill. Address valid findings, rerun `mix precommit`, and commit any review fixes separately.
