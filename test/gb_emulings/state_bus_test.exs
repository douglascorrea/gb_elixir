defmodule GBEmulings.StateBusTest do
  use ExUnit.Case, async: false

  import Bitwise

  alias GbEmu.{BootRom, Bus, GB, Machine}

  test "creates the complete machine state" do
    gb = machine()

    assert %GB{} = gb
    assert gb.pc == 0x0100
    assert gb.boot_kind == :minimal
    assert gb.mbc == :none
  end

  test "allocates every atomics-backed memory region at its hardware size" do
    gb = machine()

    assert :atomics.info(gb.vram).size == 0x2000
    assert :atomics.info(gb.wram).size == 0x2000
    assert :atomics.info(gb.oam).size == 0xA0
    assert :atomics.info(gb.hram).size == 0x7F
    assert :atomics.info(gb.extram).size == 0x8000
    assert :atomics.info(gb.io_misc).size == 0x80
  end

  test "builds and caches the planar tile decode table" do
    GB.ensure_decode_table()
    first = GB.decode_table()
    GB.ensure_decode_table()

    assert GB.decode_table() === first
    assert elem(first, 0x4080) == [1, 2, 0, 0, 0, 0, 0, 0]
  end

  test "provides a lawful minimal boot stub and documented post-boot state" do
    assert byte_size(BootRom.minimal()) == 0x100
    assert BootRom.minimal?(BootRom.minimal())

    state = BootRom.post_boot_state()
    assert state.pc == 0x0100
    assert state.sp == 0xFFFE
    assert state.lcdc == 0x91
    refute state.boot_enabled
  end

  test "loads only a 256-byte optional boot ROM" do
    path =
      Path.join(System.tmp_dir!(), "gbemulings-boot-#{System.unique_integer([:positive])}.bin")

    valid = :binary.copy(<<0xEA>>, 0x100)

    on_exit(fn -> File.rm(path) end)

    File.write!(path, valid)
    assert BootRom.load!(path) == valid

    File.write!(path, <<0>>)
    assert_raise ArgumentError, ~r/256-byte DMG boot ROM/, fn -> BootRom.load!(path) end
  end

  test "classifies cartridge headers and rejects unsupported mappers" do
    assert machine(rom(0x00)).mbc == :none
    assert machine(rom(0x01)).mbc == :mbc1
    assert machine(rom(0x19)).mbc == :mbc5

    assert_raise RuntimeError, ~r/unsupported cartridge type/, fn -> machine(rom(0xFC)) end
  end

  test "reads fixed and switchable ROM banks" do
    gb = machine(rom(0x01, 4))

    assert Bus.read8(gb, 0x0200) == 0
    assert Bus.read8(gb, 0x4000) == 1

    gb = Bus.write8(gb, 0x2000, 2)
    assert Bus.read8(gb, 0x4000) == 2
  end

  test "maps VRAM, WRAM, echo RAM, OAM, open bus, HRAM, and IE" do
    gb = machine()
    gb = Bus.write8(gb, 0x8123, 0x11)
    gb = Bus.write8(gb, 0xC123, 0x22)
    gb = Bus.write8(gb, 0xFE20, 0x33)
    gb = Bus.write8(gb, 0xFF80, 0x44)
    gb = Bus.write8(gb, 0xFFFF, 0x55)

    assert Bus.read8(gb, 0x8123) == 0x11
    assert Bus.read8(gb, 0xC123) == 0x22
    assert Bus.read8(gb, 0xE123) == 0x22
    assert Bus.read8(gb, 0xFE20) == 0x33
    assert Bus.read8(gb, 0xFEA0) == 0xFF
    assert Bus.read8(gb, 0xFF80) == 0x44
    assert Bus.read8(gb, 0xFFFF) == 0x55
  end

  test "reads little-endian words across adjacent addresses" do
    gb = machine() |> Bus.write8(0xFF80, 0x34) |> Bus.write8(0xFF81, 0x12)
    assert Bus.read16(gb, 0xFF80) == 0x1234
  end

  test "unmaps the boot overlay and applies IO write side effects" do
    gb = Machine.new(:binary.copy(<<0xAA>>, 0x100), rom())
    assert gb.boot_enabled

    gb = Bus.write8(gb, 0xFF50, 1)
    refute gb.boot_enabled

    gb = %{gb | div_counter: 0xCAFE, ly: 42}
    gb = Bus.write8(gb, 0xFF04, 0xFF)
    gb = Bus.write8(gb, 0xFF44, 99)
    assert gb.div_counter == 0
    assert gb.ly == 42
  end

  test "copies a full OAM DMA block" do
    gb = machine()

    gb =
      Enum.reduce(0..0x9F, gb, fn offset, state ->
        Bus.write8(state, 0xC000 + offset, offset)
      end)

    gb = Bus.write8(gb, 0xFF46, 0xC0)

    assert Bus.read8(gb, 0xFE00) == 0
    assert Bus.read8(gb, 0xFE50) == 0x50
    assert Bus.read8(gb, 0xFE9F) == 0x9F
  end

  test "implements MBC1 RAM enable, ROM banking, upper bits, and RAM banking" do
    gb = machine(rom(0x01, 4))
    gb = Bus.write8(gb, 0x0000, 0x0A)
    assert gb.ram_enabled

    gb = Bus.write8(gb, 0xA000, 0x5A)
    assert Bus.read8(gb, 0xA000) == 0x5A

    gb = Bus.write8(gb, 0x2000, 0)
    assert gb.rom_bank == 1

    gb = Bus.write8(gb, 0x4000, 2)
    assert gb.rom_bank == 0x41

    gb = Bus.write8(gb, 0x6000, 1)
    gb = Bus.write8(gb, 0x4000, 3)
    assert gb.ram_bank == 3
  end

  test "implements MBC5 nine-bit ROM banks and four-bit RAM banks" do
    gb = machine(rom(0x19, 2))
    gb = Bus.write8(gb, 0x2000, 0x34)
    gb = Bus.write8(gb, 0x3000, 1)
    gb = Bus.write8(gb, 0x4000, 0x0F)

    assert gb.rom_bank == 0x134
    assert gb.ram_bank == 0x0F
  end

  defp machine(rom \\ rom()), do: Machine.new(BootRom.minimal(), rom)

  defp rom(type \\ 0x00, banks \\ 2) do
    binary =
      0..(banks - 1)
      |> Enum.map_join(fn bank -> :binary.copy(<<bank &&& 0xFF>>, 0x4000) end)

    put_byte(binary, 0x147, type)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end
end
