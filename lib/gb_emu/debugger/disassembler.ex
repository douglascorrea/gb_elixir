defmodule GbEmu.Debugger.Disassembler do
  @moduledoc """
  Algorithmic SM83 disassembly for the instruction at the machine's current PC.

  Decoding uses non-tracing bus peeks, so previews never appear as CPU memory
  accesses in a debugger trace.
  """

  import Bitwise

  alias GbEmu.{Bus, GB}

  @r8 {"B", "C", "D", "E", "H", "L", "(HL)", "A"}
  @rp {"BC", "DE", "HL", "SP"}
  @rp2 {"BC", "DE", "HL", "AF"}
  @rp_mem {"(BC)", "(DE)", "(HL+)", "(HL-)"}
  @cc {"NZ", "Z", "NC", "C"}
  @alu {"ADD A", "ADC A", "SUB", "SBC A", "AND", "XOR", "OR", "CP"}
  @rot {"RLCA", "RRCA", "RLA", "RRA", "DAA", "CPL", "SCF", "CCF"}
  @cb_rot {"RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL"}
  @invalid [0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD]

  @type decoded :: map()

  @doc "Decodes the instruction currently selected by `gb.pc`."
  @spec decode(GB.t()) :: decoded()
  def decode(gb) do
    pc = gb.pc &&& 0xFFFF
    opcode = Bus.peek8(gb, pc)

    if opcode == 0xCB do
      decode_cb(gb, pc)
    else
      {length, mnemonic, operands} = decode_regular(gb, pc, opcode)

      %{
        kind: :instruction,
        pc: pc,
        opcode: opcode,
        bytes: bytes(gb, pc, length),
        length: length,
        mnemonic: mnemonic,
        operands: operands,
        handler: {:cpu, handler_selector(opcode)}
      }
    end
  end

  defp decode_cb(gb, pc) do
    opcode = Bus.peek8(gb, pc + 1 &&& 0xFFFF)
    x = opcode >>> 6
    y = opcode >>> 3 &&& 0x07
    z = opcode &&& 0x07
    register = elem(@r8, z)

    {mnemonic, operands} =
      case x do
        0 -> {"#{elem(@cb_rot, y)} #{register}", []}
        1 -> {"BIT #{y}, #{register}", [y]}
        2 -> {"RES #{y}, #{register}", [y]}
        3 -> {"SET #{y}, #{register}", [y]}
      end

    %{
      kind: :instruction,
      pc: pc,
      opcode: 0xCB,
      cb_opcode: opcode,
      bytes: [0xCB, opcode],
      length: 2,
      mnemonic: mnemonic,
      operands: operands,
      handler: {:cpu, "defp exec_cb(op, gb) do"}
    }
  end

  defp decode_regular(gb, pc, opcode) do
    x = opcode >>> 6
    y = opcode >>> 3 &&& 0x07
    z = opcode &&& 0x07
    p = y >>> 1
    q = y &&& 0x01
    byte = Bus.peek8(gb, pc + 1 &&& 0xFFFF)
    word = byte ||| Bus.peek8(gb, pc + 2 &&& 0xFFFF) <<< 8

    case x do
      0 -> decode_x0(pc, y, z, p, q, byte, word)
      1 -> decode_x1(y, z)
      2 -> decode_x2(y, z)
      3 -> decode_x3(opcode, y, z, p, q, byte, word)
    end
  end

  defp decode_x0(pc, y, 0, _p, _q, byte, word) do
    case y do
      0 -> {1, "NOP", []}
      1 -> {3, "LD (#{hex16(word)}), SP", [word]}
      2 -> {2, "STOP", [byte]}
      3 -> relative("JR", pc, byte)
      condition -> relative("JR #{elem(@cc, condition - 4)},", pc, byte)
    end
  end

  defp decode_x0(_pc, _y, 1, p, 0, _byte, word),
    do: {3, "LD #{elem(@rp, p)}, #{hex16(word)}", [word]}

  defp decode_x0(_pc, _y, 1, p, 1, _byte, _word),
    do: {1, "ADD HL, #{elem(@rp, p)}", []}

  defp decode_x0(_pc, _y, 2, p, 0, _byte, _word),
    do: {1, "LD #{elem(@rp_mem, p)}, A", []}

  defp decode_x0(_pc, _y, 2, p, 1, _byte, _word),
    do: {1, "LD A, #{elem(@rp_mem, p)}", []}

  defp decode_x0(_pc, _y, 3, p, 0, _byte, _word), do: {1, "INC #{elem(@rp, p)}", []}
  defp decode_x0(_pc, _y, 3, p, 1, _byte, _word), do: {1, "DEC #{elem(@rp, p)}", []}
  defp decode_x0(_pc, y, 4, _p, _q, _byte, _word), do: {1, "INC #{elem(@r8, y)}", []}
  defp decode_x0(_pc, y, 5, _p, _q, _byte, _word), do: {1, "DEC #{elem(@r8, y)}", []}

  defp decode_x0(_pc, y, 6, _p, _q, byte, _word),
    do: {2, "LD #{elem(@r8, y)}, #{hex8(byte)}", [byte]}

  defp decode_x0(_pc, y, 7, _p, _q, _byte, _word), do: {1, elem(@rot, y), []}

  defp decode_x1(6, 6), do: {1, "HALT", []}
  defp decode_x1(y, z), do: {1, "LD #{elem(@r8, y)}, #{elem(@r8, z)}", []}

  defp decode_x2(y, z), do: {1, alu_mnemonic(elem(@alu, y), elem(@r8, z)), []}

  defp decode_x3(_opcode, y, 0, _p, _q, byte, _word) do
    case y do
      condition when condition < 4 -> {1, "RET #{elem(@cc, condition)}", []}
      4 -> {2, "LDH (#{high_address(byte)}), A", [0xFF00 + byte]}
      5 -> {2, "ADD SP, #{signed_operand(byte)}", [signed8(byte)]}
      6 -> {2, "LDH A, (#{high_address(byte)})", [0xFF00 + byte]}
      7 -> {2, "LD HL, SP#{signed_offset(byte)}", [signed8(byte)]}
    end
  end

  defp decode_x3(_opcode, _y, 1, p, 0, _byte, _word),
    do: {1, "POP #{elem(@rp2, p)}", []}

  defp decode_x3(_opcode, _y, 1, p, 1, _byte, _word) do
    case p do
      0 -> {1, "RET", []}
      1 -> {1, "RETI", []}
      2 -> {1, "JP HL", []}
      3 -> {1, "LD SP, HL", []}
    end
  end

  defp decode_x3(_opcode, y, 2, _p, _q, _byte, word) do
    case y do
      condition when condition < 4 -> {3, "JP #{elem(@cc, condition)}, #{hex16(word)}", [word]}
      4 -> {1, "LD ($FF00+C), A", []}
      5 -> {3, "LD (#{hex16(word)}), A", [word]}
      6 -> {1, "LD A, ($FF00+C)", []}
      7 -> {3, "LD A, (#{hex16(word)})", [word]}
    end
  end

  defp decode_x3(opcode, y, 3, _p, _q, _byte, word) do
    case y do
      0 -> {3, "JP #{hex16(word)}", [word]}
      6 -> {1, "DI", []}
      7 -> {1, "EI", []}
      _ -> undefined(opcode)
    end
  end

  defp decode_x3(_opcode, y, 4, _p, _q, _byte, word) when y < 4,
    do: {3, "CALL #{elem(@cc, y)}, #{hex16(word)}", [word]}

  defp decode_x3(opcode, _y, 4, _p, _q, _byte, _word), do: undefined(opcode)

  defp decode_x3(_opcode, _y, 5, p, 0, _byte, _word),
    do: {1, "PUSH #{elem(@rp2, p)}", []}

  defp decode_x3(_opcode, _y, 5, 0, 1, _byte, word), do: {3, "CALL #{hex16(word)}", [word]}
  defp decode_x3(opcode, _y, 5, _p, 1, _byte, _word), do: undefined(opcode)

  defp decode_x3(_opcode, y, 6, _p, _q, byte, _word),
    do: {2, alu_mnemonic(elem(@alu, y), hex8(byte)), [byte]}

  defp decode_x3(_opcode, y, 7, _p, _q, _byte, _word) do
    vector = y * 8
    {1, "RST #{hex16(vector)}", [vector]}
  end

  defp relative(prefix, pc, byte) do
    target = pc + 2 + signed8(byte) &&& 0xFFFF
    {2, "#{prefix} #{hex16(target)}", [target]}
  end

  defp undefined(opcode), do: {1, "UNDEFINED #{hex8(opcode)} (NOP)", []}

  defp alu_mnemonic(operation, operand) when operation in ["SUB", "AND", "XOR", "OR", "CP"],
    do: "#{operation} #{operand}"

  defp alu_mnemonic(operation, operand), do: "#{operation}, #{operand}"

  defp handler_selector(opcode) do
    cond do
      opcode in @invalid ->
        "defp exec(_op, gb), do: {gb, 4}"

      opcode in [0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C] ->
        "defp exec(op, gb) when op in [0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C] do"

      opcode in [0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D] ->
        "defp exec(op, gb) when op in [0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D] do"

      opcode in [0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E] ->
        "defp exec(op, gb) when op in [0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E] do"

      opcode in [0x09, 0x19, 0x29, 0x39] ->
        "defp exec(op, gb) when op in [0x09, 0x19, 0x29, 0x39] do"

      opcode in [0x20, 0x28, 0x30, 0x38] ->
        "defp exec(op, gb) when op in [0x20, 0x28, 0x30, 0x38] do"

      opcode in 0x40..0x7F and opcode != 0x76 ->
        "defp exec(op, gb) when op in 0x40..0x7F do"

      opcode in 0x80..0xBF ->
        "defp exec(op, gb) when op in 0x80..0xBF do"

      opcode in [0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE] ->
        "defp exec(op, gb) when op in [0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE] do"

      opcode in [0xC0, 0xC8, 0xD0, 0xD8] ->
        "defp exec(op, gb) when op in [0xC0, 0xC8, 0xD0, 0xD8] do"

      opcode in [0xC2, 0xCA, 0xD2, 0xDA] ->
        "defp exec(op, gb) when op in [0xC2, 0xCA, 0xD2, 0xDA] do"

      opcode in [0xC4, 0xCC, 0xD4, 0xDC] ->
        "defp exec(op, gb) when op in [0xC4, 0xCC, 0xD4, 0xDC] do"

      opcode in [0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF] ->
        "defp exec(op, gb) when op in [0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF] do"

      true ->
        "defp exec(0x#{opcode |> Integer.to_string(16) |> String.upcase() |> String.pad_leading(2, "0")}"
    end
  end

  defp bytes(gb, pc, length) do
    for offset <- 0..(length - 1), do: Bus.peek8(gb, pc + offset &&& 0xFFFF)
  end

  defp signed8(value), do: if(value > 0x7F, do: value - 0x100, else: value)
  defp signed_operand(value), do: value |> signed8() |> signed_text()

  defp signed_offset(value) do
    value
    |> signed8()
    |> signed_text()
  end

  defp signed_text(value) when value < 0, do: "-#{hex8(abs(value))}"
  defp signed_text(value), do: "+#{hex8(value)}"
  defp high_address(byte), do: hex16(0xFF00 + byte)
  defp hex8(value), do: "$" <> padded_hex(value &&& 0xFF, 2)
  defp hex16(value), do: "$" <> padded_hex(value &&& 0xFFFF, 4)

  defp padded_hex(value, width) do
    value
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(width, "0")
  end
end
