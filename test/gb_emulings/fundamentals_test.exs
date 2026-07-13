Code.require_file("../../exercises/workbench/fundamentals.exs", __DIR__)

defmodule GBEmulings.FundamentalsTest do
  use ExUnit.Case, async: true

  alias GBEmulings.Fundamentals

  test "parses hexadecimal bytes" do
    assert Fundamentals.parse_hex_byte("FF") == 0xFF
    assert Fundamentals.parse_hex_byte("1A") == 0x1A
  end

  test "expands a byte from most-significant to least-significant bit" do
    assert Fundamentals.byte_to_bits(0b1010_0001) == [1, 0, 1, 0, 0, 0, 0, 1]
  end

  test "wraps unsigned byte arithmetic" do
    assert Fundamentals.wrap_byte(0x100) == 0
    assert Fundamentals.wrap_byte(-1) == 0xFF
  end

  test "sets and clears individual bits" do
    assert Fundamentals.set_bit(0, 5) == 0x20
    assert Fundamentals.clear_bit(0xFF, 5) == 0xDF
  end

  test "constructs little-endian words" do
    assert Fundamentals.little_endian_word(0x34, 0x12) == 0x1234
  end

  test "reads immutable binary data" do
    assert Fundamentals.read_binary_byte(<<0x10, 0x20, 0x30>>, 1) == 0x20
  end

  test "allocates and writes atomics-backed memory" do
    memory = Fundamentals.new_memory(4)
    assert :atomics.get(Fundamentals.write_memory(memory, 2, 0x1FF), 3) == 0xFF
  end

  test "decodes a two-plane Game Boy tile row" do
    assert Fundamentals.decode_tile_row(0b1000_0000, 0b0100_0000) == [1, 2, 0, 0, 0, 0, 0, 0]
  end
end
