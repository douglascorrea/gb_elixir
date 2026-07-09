defmodule GbEmu.Bus do
  @moduledoc """
  Memory bus: routes reads/writes across boot ROM, cartridge (with MBC1/MBC5
  banking), VRAM, WRAM, OAM, IO registers and HRAM.
  """

  import Bitwise
  alias GbEmu.{BootRom, GB}
  alias GbEmu.Debugger.Trace

  @spec read8(GB.t() | struct(), non_neg_integer()) :: non_neg_integer()
  def read8(%{debug_trace?: true} = gb, addr) do
    addr = addr &&& 0xFFFF
    value = peek8(gb, addr)
    region = region(gb, addr)

    Trace.record(gb, %{
      type: :memory,
      operation: :read,
      address: addr,
      value: value,
      region: region,
      label: label(gb, addr),
      source_location: {:bus, branch_selector(:read, region)}
    })

    value
  end

  def read8(gb, addr), do: peek8(gb, addr)

  @doc "Reads memory without producing a debugger trace event."
  @spec peek8(GB.t() | struct(), non_neg_integer()) :: non_neg_integer()
  def peek8(gb, addr) do
    addr = addr &&& 0xFFFF

    cond do
      addr < 0x0100 and gb.boot_enabled ->
        :binary.at(gb.boot, addr)

      addr < 0x4000 ->
        :binary.at(gb.rom, addr)

      addr < 0x8000 ->
        offset = (gb.rom_bank &&& gb.rom_bank_mask) * 0x4000 + (addr - 0x4000)
        if offset < byte_size(gb.rom), do: :binary.at(gb.rom, offset), else: 0xFF

      addr < 0xA000 ->
        :atomics.get(gb.vram, addr - 0x8000 + 1)

      addr < 0xC000 ->
        if gb.ram_enabled do
          :atomics.get(gb.extram, (gb.ram_bank &&& 0x03) * 0x2000 + (addr - 0xA000) + 1)
        else
          0xFF
        end

      addr < 0xE000 ->
        :atomics.get(gb.wram, addr - 0xC000 + 1)

      addr < 0xFE00 ->
        :atomics.get(gb.wram, addr - 0xE000 + 1)

      addr < 0xFEA0 ->
        :atomics.get(gb.oam, addr - 0xFE00 + 1)

      addr < 0xFF00 ->
        0xFF

      addr < 0xFF80 ->
        read_io(gb, addr)

      addr < 0xFFFF ->
        :atomics.get(gb.hram, addr - 0xFF80 + 1)

      true ->
        gb.ie
    end
  end

  def read16(gb, addr), do: read8(gb, addr) ||| read8(gb, addr + 1 &&& 0xFFFF) <<< 8

  @spec write8(struct(), non_neg_integer(), non_neg_integer()) :: struct()
  def write8(%{debug_trace?: true} = gb, addr, requested) do
    addr = addr &&& 0xFFFF
    before = peek8(gb, addr)
    value = requested &&& 0xFF
    result = do_write8(gb, addr, value)
    after_value = peek8(result, addr)
    side_effects = write_side_effects(gb, result, addr, value)
    region = write_region(addr)

    Trace.record(gb, %{
      type: :memory,
      operation: :write,
      address: addr,
      requested: requested,
      value: value,
      before: before,
      after: after_value,
      region: region,
      label: label(addr),
      side_effects: side_effects,
      source_location: {:bus, branch_selector(:write, region)}
    })

    trace_dma(gb, addr, value)
    result
  end

  def write8(gb, addr, value) do
    do_write8(gb, addr &&& 0xFFFF, value &&& 0xFF)
  end

  defp do_write8(gb, addr, v) do
    v = v &&& 0xFF

    cond do
      addr < 0x8000 ->
        mbc_write(gb, addr, v)

      addr < 0xA000 ->
        :atomics.put(gb.vram, addr - 0x8000 + 1, v)
        gb

      addr < 0xC000 ->
        if gb.ram_enabled do
          :atomics.put(gb.extram, (gb.ram_bank &&& 0x03) * 0x2000 + (addr - 0xA000) + 1, v)
        end

        gb

      addr < 0xE000 ->
        :atomics.put(gb.wram, addr - 0xC000 + 1, v)
        gb

      addr < 0xFE00 ->
        :atomics.put(gb.wram, addr - 0xE000 + 1, v)
        gb

      addr < 0xFEA0 ->
        :atomics.put(gb.oam, addr - 0xFE00 + 1, v)
        gb

      addr < 0xFF00 ->
        gb

      addr < 0xFF80 ->
        write_io(gb, addr, v)

      addr < 0xFFFF ->
        :atomics.put(gb.hram, addr - 0xFF80 + 1, v)
        gb

      true ->
        %{gb | ie: v}
    end
  end

  @doc "Returns the debugger region for an address in the current mapping."
  @spec region(GB.t() | struct(), non_neg_integer()) :: atom()
  def region(gb, addr) do
    addr = addr &&& 0xFFFF

    cond do
      addr < 0x0100 and gb.boot_enabled -> :boot
      addr < 0x4000 -> :rom0
      addr < 0x8000 -> :romx
      addr < 0xA000 -> :vram
      addr < 0xC000 -> :external_ram
      addr < 0xE000 -> :wram
      addr < 0xFE00 -> :echo_ram
      addr < 0xFEA0 -> :oam
      addr < 0xFF00 -> :unusable
      addr < 0xFF80 -> :io
      addr < 0xFFFF -> :hram
      true -> :ie
    end
  end

  @doc "Returns a compact semantic label for an address."
  @spec label(non_neg_integer()) :: String.t()
  def label(addr) do
    addr = addr &&& 0xFFFF

    case addr do
      0xFF00 -> "JOYP joypad input"
      0xFF01 -> "SB serial data"
      0xFF02 -> "SC serial control"
      0xFF04 -> "DIV divider"
      0xFF05 -> "TIMA timer counter"
      0xFF06 -> "TMA timer modulo"
      0xFF07 -> "TAC timer control"
      0xFF0F -> "IF interrupt flags"
      0xFF40 -> "LCDC display control"
      0xFF41 -> "STAT display status"
      0xFF42 -> "SCY scroll Y"
      0xFF43 -> "SCX scroll X"
      0xFF44 -> "LY scanline"
      0xFF45 -> "LYC scanline compare"
      0xFF46 -> "OAM DMA transfer"
      0xFF47 -> "BGP background palette"
      0xFF48 -> "OBP0 object palette 0"
      0xFF49 -> "OBP1 object palette 1"
      0xFF4A -> "WY window Y"
      0xFF4B -> "WX window X"
      0xFF50 -> "Boot ROM overlay control"
      0xFFFF -> "IE interrupt enable"
      _ -> region_label(addr)
    end
  end

  @doc "Returns an address label that accounts for the boot overlay mapping."
  @spec label(GB.t() | struct(), non_neg_integer()) :: String.t()
  def label(%{boot_enabled: true}, addr) when (addr &&& 0xFFFF) < 0x0100,
    do: "Boot ROM overlay"

  def label(_gb, addr), do: label(addr)

  defp trace_dma(gb, 0xFF46, source_high) do
    source_start = source_high <<< 8

    Trace.record(gb, %{
      type: :memory,
      operation: :dma,
      source: source_start..(source_start + 0x9F),
      destination: 0xFE00..0xFE9F,
      ranges: [
        %{start: source_start, stop: source_start + 0x9F, purpose: :dma_source},
        %{start: 0xFE00, stop: 0xFE9F, purpose: :oam_destination}
      ],
      region: :oam,
      label: "OAM DMA block transfer",
      source_location: {:bus, "defp oam_dma(gb, src_hi) do"}
    })
  end

  defp trace_dma(_gb, _addr, _value), do: :ok

  @side_effect_fields [
    :boot_enabled,
    :rom_bank,
    :ram_bank,
    :ram_enabled,
    :mbc1_mode,
    :serial_cycles,
    :div_counter,
    :tima,
    :tma,
    :tac,
    :if_,
    :ie,
    :joyp_select,
    :lcdc,
    :stat,
    :scy,
    :scx,
    :ly,
    :lyc,
    :bgp,
    :obp0,
    :obp1,
    :wy,
    :wx,
    :ppu_dot,
    :ppu_mode,
    :window_line
  ]

  defp write_side_effects(before, after_state, addr, value) do
    changes =
      Enum.reduce(@side_effect_fields, %{}, fn field, acc ->
        old = Map.fetch!(before, field)
        new = Map.fetch!(after_state, field)

        if old == new do
          acc
        else
          Map.put(acc, field, %{before: old, after: new})
        end
      end)

    effects =
      if map_size(changes) == 0 do
        []
      else
        [%{type: :state_change, changes: changes}]
      end

    cond do
      addr == 0xFF46 ->
        [%{type: :dma, source_start: value <<< 8, bytes: 160} | effects]

      addr == 0xFF50 and before.boot_enabled and not after_state.boot_enabled ->
        [%{type: :boot_handoff, compatibility?: before.boot_kind == :minimal} | effects]

      true ->
        effects
    end
  end

  defp region_label(addr) do
    cond do
      addr < 0x4000 -> "Cartridge ROM bank 0"
      addr < 0x8000 -> "Switchable cartridge ROM"
      addr < 0xA000 -> "Video RAM"
      addr < 0xC000 -> "External cartridge RAM"
      addr < 0xE000 -> "Work RAM"
      addr < 0xFE00 -> "Echo RAM"
      addr < 0xFEA0 -> "Object attribute memory"
      addr < 0xFF00 -> "Unusable memory"
      addr < 0xFF80 -> "I/O register"
      addr < 0xFFFF -> "High RAM"
      true -> "Interrupt enable"
    end
  end

  defp write_region(addr) do
    cond do
      addr < 0x4000 -> :rom0
      addr < 0x8000 -> :romx
      addr < 0xA000 -> :vram
      addr < 0xC000 -> :external_ram
      addr < 0xE000 -> :wram
      addr < 0xFE00 -> :echo_ram
      addr < 0xFEA0 -> :oam
      addr < 0xFF00 -> :unusable
      addr < 0xFF80 -> :io
      addr < 0xFFFF -> :hram
      true -> :ie
    end
  end

  defp branch_selector(operation, region) do
    "bus:#{operation}:#{region}"
  end

  # --- MBC control writes ---

  defp mbc_write(%{mbc: :none} = gb, _addr, _v), do: gb

  defp mbc_write(%{mbc: :mbc1} = gb, addr, v) do
    cond do
      addr < 0x2000 ->
        %{gb | ram_enabled: (v &&& 0x0F) == 0x0A}

      addr < 0x4000 ->
        low = if (v &&& 0x1F) == 0, do: 1, else: v &&& 0x1F
        %{gb | rom_bank: (gb.rom_bank &&& 0x60) ||| low}

      addr < 0x6000 ->
        if gb.mbc1_mode == 0 do
          %{gb | rom_bank: (gb.rom_bank &&& 0x1F) ||| (v &&& 0x03) <<< 5}
        else
          %{gb | ram_bank: v &&& 0x03}
        end

      true ->
        %{gb | mbc1_mode: v &&& 0x01}
    end
  end

  defp mbc_write(%{mbc: :mbc5} = gb, addr, v) do
    cond do
      addr < 0x2000 -> %{gb | ram_enabled: (v &&& 0x0F) == 0x0A}
      addr < 0x3000 -> %{gb | rom_bank: (gb.rom_bank &&& 0x100) ||| v}
      addr < 0x4000 -> %{gb | rom_bank: (gb.rom_bank &&& 0xFF) ||| (v &&& 0x01) <<< 8}
      addr < 0x6000 -> %{gb | ram_bank: v &&& 0x0F}
      true -> gb
    end
  end

  # --- IO registers ---

  defp read_io(gb, addr) do
    case addr do
      0xFF00 -> joyp_value(gb)
      0xFF04 -> gb.div_counter >>> 8 &&& 0xFF
      0xFF05 -> gb.tima
      0xFF06 -> gb.tma
      0xFF07 -> gb.tac ||| 0xF8
      0xFF0F -> gb.if_ ||| 0xE0
      0xFF40 -> gb.lcdc
      0xFF41 -> gb.stat ||| 0x80
      0xFF42 -> gb.scy
      0xFF43 -> gb.scx
      0xFF44 -> gb.ly
      0xFF45 -> gb.lyc
      0xFF47 -> gb.bgp
      0xFF48 -> gb.obp0
      0xFF49 -> gb.obp1
      0xFF4A -> gb.wy
      0xFF4B -> gb.wx
      0xFF50 -> if gb.boot_enabled, do: 0xFE, else: 0xFF
      _ -> :atomics.get(gb.io_misc, (addr &&& 0x7F) + 1)
    end
  end

  defp write_io(gb, addr, v) do
    case addr do
      0xFF00 ->
        %{gb | joyp_select: v &&& 0x30}

      0xFF02 ->
        # Serial transfer control.
        # Bit 7 = start, bit 0 = clock source (1 = internal, 0 = external).
        # With no link partner, external-clock transfers must stay pending —
        # completing them instantly breaks Tetris title-screen Start handling.
        # Internal-clock transfers (blargg tests, some games) complete after
        # ~4096 T-cycles via Machine.step_serial/2.
        :atomics.put(gb.io_misc, 0x02 + 1, v)

        cond do
          (v &&& 0x80) == 0 ->
            %{gb | serial_cycles: nil}

          (v &&& 0x01) != 0 ->
            %{gb | serial_cycles: 4096}

          true ->
            %{gb | serial_cycles: nil}
        end

      0xFF04 ->
        %{gb | div_counter: 0}

      0xFF05 ->
        %{gb | tima: v}

      0xFF06 ->
        %{gb | tma: v}

      0xFF07 ->
        %{gb | tac: v &&& 0x07}

      0xFF0F ->
        %{gb | if_: v &&& 0x1F}

      0xFF40 ->
        was_on = (gb.lcdc &&& 0x80) != 0
        now_on = (v &&& 0x80) != 0
        gb = %{gb | lcdc: v}

        cond do
          was_on and not now_on ->
            # LCD off: freeze the last frame and reset scanline state
            %{gb | ly: 0, ppu_dot: 0, ppu_mode: 0, stat: gb.stat &&& 0xFC, window_line: 0}

          not was_on and now_on ->
            # LCD on: start a fresh frame from OAM scan (mode 2)
            %{
              gb
              | ly: 0,
                ppu_dot: 0,
                ppu_mode: 2,
                stat: (gb.stat &&& 0xFC) ||| 2,
                window_line: 0,
                fb_lines: %{}
            }

          true ->
            gb
        end

      0xFF41 ->
        %{gb | stat: (gb.stat &&& 0x07) ||| (v &&& 0x78)}

      0xFF42 ->
        %{gb | scy: v}

      0xFF43 ->
        %{gb | scx: v}

      0xFF44 ->
        gb

      0xFF45 ->
        %{gb | lyc: v}

      0xFF46 ->
        oam_dma(gb, v)

      0xFF47 ->
        %{gb | bgp: v}

      0xFF48 ->
        %{gb | obp0: v}

      0xFF49 ->
        %{gb | obp1: v}

      0xFF4A ->
        %{gb | wy: v}

      0xFF4B ->
        %{gb | wx: v}

      0xFF50 ->
        cond do
          v == 0 ->
            gb

          gb.boot_enabled and gb.boot_kind == :minimal and gb.boot_mode == :cold ->
            compatibility_state = Map.delete(BootRom.post_boot_state(), :pc)
            struct!(gb, compatibility_state)

          true ->
            %{gb | boot_enabled: false}
        end

      _ ->
        :atomics.put(gb.io_misc, (addr &&& 0x7F) + 1, v)
        gb
    end
  end

  # Joypad: select bits are 0 = selected; pressed buttons read as 0.
  defp joyp_value(gb) do
    sel = gb.joyp_select
    base = 0xC0 ||| sel ||| 0x0F

    pressed =
      cond do
        (sel &&& 0x10) == 0 and (sel &&& 0x20) == 0 -> gb.dpad ||| gb.btns
        (sel &&& 0x10) == 0 -> gb.dpad
        (sel &&& 0x20) == 0 -> gb.btns
        true -> 0
      end

    base &&& bnot(pressed) &&& 0xFF
  end

  defp oam_dma(gb, src_hi) do
    base = src_hi <<< 8

    Enum.each(0..0x9F, fn i ->
      :atomics.put(gb.oam, i + 1, peek8(gb, base + i))
    end)

    gb
  end
end
