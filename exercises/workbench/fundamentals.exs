defmodule GBEmulings.Fundamentals do
  import Bitwise

  def parse_hex_byte(text) do
    {value, ""} = Integer.parse(text, 16)
    value &&& 0xFF
  end

  def byte_to_bits(value) do
    for bit <- 7..0//-1, do: value >>> bit &&& 1
  end

  def wrap_byte(value), do: value &&& 0xFF

  def set_bit(value, bit), do: value ||| 1 <<< bit

  def clear_bit(value, bit), do: value &&& bnot(1 <<< bit) &&& 0xFF

  def little_endian_word(low, high), do: low ||| high <<< 8

  def read_binary_byte(binary, offset), do: :binary.at(binary, offset)

  def new_memory(size), do: :atomics.new(size, signed: false)

  def write_memory(memory, offset, value) do
    :atomics.put(memory, offset + 1, value &&& 0xFF)
    memory
  end

  def decode_tile_row(low, high) do
    for bit <- 7..0//-1 do
      (low >>> bit &&& 1) ||| (high >>> bit &&& 1) <<< 1
    end
  end
end
