defmodule GbEmu.Bus do
  @moduledoc """
  Memory bus: routes reads/writes across boot ROM, cartridge (with MBC1/MBC5
  banking), VRAM, WRAM, OAM, IO registers and HRAM.
  """

  import Bitwise
  alias GbEmu.GB

  @spec read8(GB.t() | struct(), non_neg_integer()) :: non_neg_integer()
  def read8(gb, addr) do
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
  def write8(gb, addr, v) do
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
        if v != 0, do: %{gb | boot_enabled: false}, else: gb

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
      :atomics.put(gb.oam, i + 1, read8(gb, base + i))
    end)

    gb
  end
end
