definition = fn file, anchor, checks ->
  %{
    target: %{kind: :definition, file: file, anchor: anchor},
    checks: checks
  }
end

branch = fn file, after_anchor, start_anchor, stop_anchor, checks ->
  %{
    target: %{
      kind: :branch,
      file: file,
      after: after_anchor,
      start: start_anchor,
      stop: stop_anchor
    },
    checks: checks
  }
end

fundamentals = [["mix", "test", "test/gb_emulings/fundamentals_test.exs"]]
state_bus = [["mix", "test", "test/gb_emulings/state_bus_test.exs"]]
cpu = [["mix", "test", "test/gb_emulings/cpu_test.exs"]]
timing_ppu = [["mix", "test", "test/gb_emulings/timing_ppu_test.exs"]]
machine = [["mix", "test", "test/gb_emu/machine_test.exs"]]
debugger = [["mix", "test", "test/gb_emu/debugger_test.exs"]]
runtime = [["mix", "test", "test/gb_emu/emulator_debugger_test.exs"]]
sessions = [["mix", "test", "test/gb_emu/emulator_sessions_test.exs"]]
live_view = [["mix", "test", "test/gb_emu_web/live/emulator_live_test.exs"]]
uploads = [["mix", "test", "test/gb_emu/upload_store_test.exs"]]
release = [["mix", "test", "test/gb_emulings/release_test.exs"]]
policy = [["mix", "test", "test/gb_emulings/policy_test.exs"]]

targets = %{
  "001" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def parse_hex_byte(text) do",
      fundamentals
    ),
  "002" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def byte_to_bits(value) do",
      fundamentals
    ),
  "003" =>
    definition.("exercises/workbench/fundamentals.exs", "def wrap_byte(value), do:", fundamentals),
  "004" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def set_bit(value, bit), do:",
      fundamentals
    ),
  "005" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def clear_bit(value, bit), do:",
      fundamentals
    ),
  "006" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def little_endian_word(low, high), do:",
      fundamentals
    ),
  "007" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def read_binary_byte(binary, offset), do:",
      fundamentals
    ),
  "008" =>
    definition.("exercises/workbench/fundamentals.exs", "def new_memory(size), do:", fundamentals),
  "009" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def write_memory(memory, offset, value) do",
      fundamentals
    ),
  "010" =>
    definition.(
      "exercises/workbench/fundamentals.exs",
      "def decode_tile_row(low, high) do",
      fundamentals
    ),
  "011" => definition.("lib/gb_emu/gb.ex", "def new(boot, rom, opts \\\\ [])", machine),
  "012" => definition.("lib/gb_emu/gb.ex", "defp allocate_memory do", machine),
  "013" => definition.("lib/gb_emu/gb.ex", "defp build_decode_table do", machine),
  "014" => definition.("lib/gb_emu/gb.ex", "def ensure_decode_table do", machine),
  "015" => definition.("lib/gb_emu/boot_rom.ex", "def minimal, do:", machine),
  "016" => definition.("lib/gb_emu/boot_rom.ex", "def load!(path) when", machine),
  "017" => definition.("lib/gb_emu/boot_rom.ex", "def post_boot_state do", machine),
  "018" => definition.("lib/gb_emu/gb.ex", "defp cartridge_type(rom), do:", machine),
  "019" => definition.("lib/gb_emu/gb.ex", "defp mbc_for(type) when type in [0x00", machine),
  "020" => definition.("lib/gb_emu/gb.ex", "defp mbc_for(other) do", machine),
  "021" => %{
    target: %{
      kind: :branch,
      file: "lib/gb_emu/bus.ex",
      after: "def peek8(gb, addr) do",
      start: "addr < 0x4000 ->",
      stop: "addr < 0x8000 ->"
    },
    checks: debugger
  },
  "022" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "def peek8(gb, addr) do",
      "addr < 0x8000 ->",
      "addr < 0xA000 ->",
      debugger
    ),
  "023" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "def peek8(gb, addr) do",
      "addr < 0xA000 ->",
      "addr < 0xC000 ->",
      debugger
    ),
  "024" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "def peek8(gb, addr) do",
      "addr < 0xFE00 ->",
      "addr < 0xFEA0 ->",
      debugger
    ),
  "025" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "def peek8(gb, addr) do",
      "addr < 0xFEA0 ->",
      "addr < 0xFF00 ->",
      debugger
    ),
  "026" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "def peek8(gb, addr) do",
      "addr < 0xFF00 ->",
      "addr < 0xFF80 ->",
      debugger
    ),
  "027" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "def peek8(gb, addr) do",
      "addr < 0xFFFF ->",
      "true ->",
      debugger
    ),
  "028" => definition.("lib/gb_emu/bus.ex", "def read16(gb, addr), do:", debugger),
  "029" =>
    branch.("lib/gb_emu/bus.ex", "defp write_io(gb, addr, v) do", "0xFF50 ->", "_ ->", debugger),
  "030" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp write_io(gb, addr, v) do",
      "0xFF04 ->",
      "0xFF05 ->",
      debugger
    ),
  "031" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp write_io(gb, addr, v) do",
      "0xFF44 ->",
      "0xFF45 ->",
      debugger
    ),
  "032" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp write_io(gb, addr, v) do",
      "0xFF46 ->",
      "0xFF47 ->",
      debugger
    ),
  "033" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp mbc_write(%{mbc: :mbc1}",
      "addr < 0x2000 ->",
      "addr < 0x4000 ->",
      debugger
    ),
  "034" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp mbc_write(%{mbc: :mbc1}",
      "addr < 0x4000 ->",
      "addr < 0x6000 ->",
      debugger
    ),
  "035" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp mbc_write(%{mbc: :mbc1}",
      "addr < 0x6000 ->",
      "true ->",
      debugger
    ),
  "036" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp mbc_write(%{mbc: :mbc5}",
      "addr < 0x4000 ->",
      "addr < 0x6000 ->",
      debugger
    ),
  "037" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp mbc_write(%{mbc: :mbc5}",
      "addr < 0x6000 ->",
      "true ->",
      debugger
    ),
  "038" => definition.("lib/gb_emu/cpu.ex", "defp execute(gb) do", debugger),
  "039" => definition.("lib/gb_emu/cpu.ex", "defp fetch8(gb) do", debugger),
  "040" => definition.("lib/gb_emu/cpu.ex", "defp hl(gb), do:", debugger),
  "041" => definition.("lib/gb_emu/cpu.ex", "defp exec(0x01, gb) do", debugger),
  "042" => definition.("lib/gb_emu/cpu.ex", "defp exec(0x02, gb), do:", debugger),
  "043" => definition.("lib/gb_emu/cpu.ex", "defp exec(0x22, gb) do", debugger),
  "044" => definition.("lib/gb_emu/cpu.ex", "defp exec(op, gb) when op in 0x40..0x7F", debugger),
  "045" => definition.("lib/gb_emu/cpu.ex", "defp exec(op, gb) when op in [0x06", debugger),
  "046" => definition.("lib/gb_emu/cpu.ex", "defp exec(0xE0, gb) do", debugger),
  "047" => definition.("lib/gb_emu/cpu.ex", "defp exec(op, gb) when op in [0x04", debugger),
  "048" => definition.("lib/gb_emu/cpu.ex", "defp alu_add(gb, v, carry) do", debugger),
  "049" => definition.("lib/gb_emu/cpu.ex", "defp alu_sub(gb, v, carry, store) do", debugger),
  "050" => definition.("lib/gb_emu/cpu.ex", "defp alu(gb, 4, v) do", debugger),
  "051" => definition.("lib/gb_emu/cpu.ex", "defp exec(0x27, gb) do", debugger),
  "052" => definition.("lib/gb_emu/cpu.ex", "defp exec(0x18, gb) do", debugger),
  "053" => definition.("lib/gb_emu/cpu.ex", "defp exec(0xC3, gb) do", debugger),
  "054" => definition.("lib/gb_emu/cpu.ex", "defp exec(0xC9, gb) do", debugger),
  "055" => definition.("lib/gb_emu/cpu.ex", "defp push16(gb, v) do", debugger),
  "056" => definition.("lib/gb_emu/cpu.ex", "defp exec(0xF1, gb) do", debugger),
  "057" => definition.("lib/gb_emu/cpu.ex", "defp sp_add(sp, off) do", debugger),
  "058" => definition.("lib/gb_emu/cpu.ex", "defp exec(0x07, gb) do", debugger),
  "059" => definition.("lib/gb_emu/cpu.ex", "defp exec(0xCB, gb) do", debugger),
  "060" => definition.("lib/gb_emu/cpu.ex", "defp cb_execute_rotate(op, gb, idx) do", debugger),
  "061" => definition.("lib/gb_emu/cpu.ex", "defp cb_execute_bit(op, gb, idx) do", debugger),
  "062" => definition.("lib/gb_emu/cpu.ex", "defp cb_execute_update(op, gb, idx) do", debugger),
  "063" => definition.("lib/gb_emu/cpu.ex", "def boundary(gb) do", debugger),
  "064" => definition.("lib/gb_emu/cpu.ex", "defp exec(0xFB, gb), do:", debugger),
  "065" => definition.("lib/gb_emu/cpu.ex", "defp exec(0x76, gb), do:", debugger),
  "066" => definition.("lib/gb_emu/cpu.ex", "defp service_interrupt(gb, pending) do", debugger),
  "067" => definition.("lib/gb_emu/timer.ex", "def step(gb, cycles) do", machine),
  "068" => definition.("lib/gb_emu/timer.ex", "defp timer_period(tac), do:", machine),
  "069" => definition.("lib/gb_emu/timer.ex", "defp tick_tima(gb, period) do", machine),
  "070" =>
    definition.("lib/gb_emu/machine.ex", "defp step_serial(%{serial_cycles: nil}", machine),
  "071" => definition.("lib/gb_emu/machine.ex", "defp step_serial(gb, cycles) do", machine),
  "072" => definition.("lib/gb_emu/machine.ex", "defp button_location(button) do", machine),
  "073" => definition.("lib/gb_emu/bus.ex", "defp joyp_value(gb) do", machine),
  "074" => definition.("lib/gb_emu/machine.ex", "def set_button(gb, button, down) do", machine),
  "075" => definition.("lib/gb_emu/ppu.ex", "defp ppu_state(gb) do", debugger),
  "076" =>
    branch.(
      "lib/gb_emu/bus.ex",
      "defp write_io(gb, addr, v) do",
      "0xFF40 ->",
      "0xFF41 ->",
      machine
    ),
  "077" => definition.("lib/gb_emu/ppu.ex", "defp advance(gb) do", machine),
  "078" => definition.("lib/gb_emu/ppu.ex", "defp check_lyc(gb) do", machine),
  "079" => definition.("lib/gb_emu/ppu.ex", "defp req_stat(gb), do:", machine),
  "080" => definition.("lib/gb_emu/ppu.ex", "defp tile_row_pixels(gb, map_base, y) do", machine),
  "081" => definition.("lib/gb_emu/ppu.ex", "defp bg_window_line(gb, ly) do", machine),
  "082" => definition.("lib/gb_emu/ppu.ex", "defp tile_data_range(gb) do", debugger),
  "083" =>
    definition.(
      "lib/gb_emu/ppu.ex",
      "defp apply_sprites_and_palette(gb, ly, bg_indices) do",
      machine
    ),
  "084" => definition.("lib/gb_emu/ppu.ex", "defp scanline_ranges(gb, ly) do", debugger),
  "085" => definition.("lib/gb_emu/ppu.ex", "defp visible_sprites(gb, ly) do", machine),
  "086" => definition.("lib/gb_emu/ppu.ex", "defp sprite_overlay(gb, ly, sprites) do", machine),
  "087" => definition.("lib/gb_emu/ppu.ex", "defp render_scanline(gb) do", machine),
  "088" => definition.("lib/gb_emu/ppu.ex", "defp finish_frame(gb) do", machine),
  "089" => definition.("lib/gb_emu/machine.ex", "def step_instruction(gb) do", machine),
  "090" => definition.("lib/gb_emu/machine.ex", "def run_frame(gb) do", machine),
  "091" =>
    definition.(
      "lib/gb_emu/emulator.ex",
      "def handle_cast({:load_rom, rom_path, boot_rom_path}",
      runtime
    ),
  "092" => definition.("lib/gb_emu/emulator.ex", "def start_link(opts), do:", runtime),
  "093" =>
    definition.(
      "lib/gb_emu/emulator.ex",
      "def handle_info({:tick, token}, %{tick_token: token} = state) do",
      runtime
    ),
  "094" =>
    definition.("lib/gb_emu/emulator.ex", "def handle_cast({:pause, true}, state) do", runtime),
  "095" =>
    definition.(
      "lib/gb_emu/emulator_sessions.ex",
      "def handle_call({:start_emulator, opts}",
      sessions
    ),
  "096" =>
    definition.(
      "lib/gb_emu_web/live/emulator_live.ex",
      "def mount(_params, session, socket) do",
      live_view
    ),
  "097" =>
    definition.(
      "lib/gb_emu_web/live/emulator_live.ex",
      "def handle_info({:gb_frame, frame, fps}",
      live_view
    ),
  "098" =>
    definition.(
      "lib/gb_emu_web/live/emulator_live.ex",
      "def handle_event(\"joypad\", %{\"button\"",
      live_view
    ),
  "099" =>
    definition.(
      "lib/gb_emu_web/live/emulator_live.ex",
      "def handle_event(\"upload_roms\"",
      live_view
    ),
  "100" => definition.("lib/gb_emu_web/upload_session.ex", "def call(conn, _opts) do", live_view),
  "101" =>
    definition.(
      "lib/gb_emu/upload_store.ex",
      "def handle_call({:put_file, session_id, kind, source_path}",
      uploads
    ),
  "102" =>
    definition.(
      "lib/gb_emu/upload_store.ex",
      "defp cleanup_session(state, session_id, ttl_ms) do",
      uploads
    ),
  "103" =>
    definition.("lib/gb_emu/emulator.ex", "def debug_attach(pid, memory_start) when", runtime),
  "104" =>
    definition.("lib/gb_emu/debugger/snapshot.ex", "def build(gb, opts \\\\ []) do", debugger),
  "105" => definition.("lib/gb_emu/debugger/disassembler.ex", "def decode(gb) do", debugger),
  "106" =>
    definition.("lib/gb_emu/debugger/trace.ex", "def record(%{debug_trace?: true}", debugger),
  "107" =>
    definition.(
      "lib/gb_emu_web/components/debugger_components.ex",
      "def sidebar(assigns) do",
      live_view
    ),
  "108" =>
    definition.(
      "lib/gb_emu/debugger.ex",
      "defp run_to_boundary(gb, command, initial, limit",
      debugger
    ),
  "109" => %{
    target: %{kind: :file, file: "docs/roms.md"},
    checks: policy
  },
  "110" =>
    definition.(
      "exercises/workbench/release.exs",
      "def release_ready?(paths) do",
      release ++
        [
          ["mix", "precommit"],
          ["env", "MIX_ENV=prod", "mix", "assets.deploy"],
          ["env", "MIX_ENV=prod", "mix", "release", "--overwrite"]
        ]
    )
}

Map.new(targets, fn {id, config} ->
  number = String.to_integer(id)

  checks =
    cond do
      number in 11..37 -> state_bus
      number in 38..66 -> cpu
      number in 67..88 -> timing_ppu
      true -> config.checks
    end

  {id, Map.put(config, :checks, checks)}
end)
