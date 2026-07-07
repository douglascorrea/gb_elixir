defmodule GbEmu.GB do
  @moduledoc """
  Full machine state for the DMG Game Boy: CPU registers, memory, IO
  registers and PPU/timer internals. The struct is threaded through every
  emulation step; bulk memory lives in `:atomics` arrays so most steps
  don't copy the struct's large fields.
  """

  import Bitwise

  defstruct [
    # CPU registers
    a: 0x00,
    f: 0x00,
    b: 0x00,
    c: 0x00,
    d: 0x00,
    e: 0x00,
    h: 0x00,
    l: 0x00,
    sp: 0x0000,
    pc: 0x0000,
    ime: false,
    ime_pending: false,
    halted: false,
    # Cartridge / boot ROM
    rom: <<>>,
    boot: <<>>,
    boot_enabled: true,
    mbc: :none,
    rom_bank: 1,
    rom_bank_mask: 1,
    ram_bank: 0,
    ram_enabled: false,
    mbc1_mode: 0,
    # Memory (:atomics, 1-indexed)
    vram: nil,
    wram: nil,
    oam: nil,
    hram: nil,
    extram: nil,
    io_misc: nil,
    # Interrupts
    if_: 0x00,
    ie: 0x00,
    # LCD registers
    lcdc: 0x00,
    stat: 0x00,
    scy: 0,
    scx: 0,
    ly: 0,
    lyc: 0,
    bgp: 0,
    obp0: 0,
    obp1: 0,
    wy: 0,
    wx: 0,
    # Timer
    div_counter: 0,
    tima_acc: 0,
    tima: 0,
    tma: 0,
    tac: 0,
    # Joypad: pressed-bit masks (1 = pressed)
    joyp_select: 0x30,
    dpad: 0x00,
    btns: 0x00,
    # PPU internals
    ppu_dot: 0,
    ppu_mode: 2,
    serial_out: [],
    window_line: 0,
    fb_lines: %{},
    frame: nil,
    frame_count: 0
  ]

  @doc "Create a fresh machine with the given boot ROM and cartridge ROM."
  def new(boot, rom) when is_binary(boot) and is_binary(rom) do
    ensure_decode_table()

    mbc =
      case :binary.at(rom, 0x147) do
        0x00 -> :none
        t when t in 0x01..0x03 -> :mbc1
        t when t in 0x19..0x1E -> :mbc5
        0x08 -> :none
        0x09 -> :none
        other -> raise "unsupported cartridge type 0x#{Integer.to_string(other, 16)}"
      end

    rom_banks = max(div(byte_size(rom), 0x4000), 2)

    %__MODULE__{
      rom: rom,
      boot: boot,
      mbc: mbc,
      rom_bank_mask: rom_banks - 1,
      vram: :atomics.new(0x2000, signed: false),
      wram: :atomics.new(0x2000, signed: false),
      oam: :atomics.new(0xA0, signed: false),
      hram: :atomics.new(0x7F, signed: false),
      extram: :atomics.new(0x8000, signed: false),
      io_misc: :atomics.new(0x80, signed: false)
    }
  end

  @doc """
  Tile row decode lookup: maps the two bytes of a tile row
  (`lo ||| hi <<< 8`) to a list of 8 color indices, leftmost pixel first.
  Stored in `:persistent_term` and built once.
  """
  def decode_table, do: :persistent_term.get(:gb_tile_decode)

  def ensure_decode_table do
    case :persistent_term.get(:gb_tile_decode, nil) do
      nil ->
        table =
          for pair <- 0..0xFFFF do
            lo = pair &&& 0xFF
            hi = pair >>> 8

            for bit <- 7..0//-1 do
              (lo >>> bit &&& 1) ||| (hi >>> bit &&& 1) <<< 1
            end
          end
          |> List.to_tuple()

        :persistent_term.put(:gb_tile_decode, table)
        :ok

      _ ->
        :ok
    end
  end
end
