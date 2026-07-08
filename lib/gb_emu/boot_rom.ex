defmodule GbEmu.BootRom do
  @moduledoc """
  Boot ROM handling for local emulator sessions.

  The project does not ship a copyrighted console BIOS. By default it uses a
  tiny open boot stub that unmaps the boot area and jumps to the cartridge
  entrypoint. Users who have a legally obtained DMG boot ROM can upload one
  or point `GB_EMU_BOOT_ROM` at their local copy.
  """

  @minimal_boot <<
    # ld a, 1
    0x3E,
    0x01,
    # ldh ($ff50), a
    0xE0,
    0x50,
    # jp $0100
    0xC3,
    0x00,
    0x01,
    0::size(8 * (0x100 - 7))
  >>

  @doc "Returns the built-in open boot stub."
  def minimal, do: @minimal_boot

  @doc "True when `boot` is the built-in open stub (not a real DMG BIOS)."
  def minimal?(boot) when is_binary(boot), do: boot == @minimal_boot

  @doc """
  Hardware state left by a finished DMG boot ROM. Used when skipping the
  real BIOS so commercial games see the registers they expect at `$0100`.
  """
  def post_boot_state do
    %{
      a: 0x01,
      f: 0xB0,
      b: 0x00,
      c: 0x13,
      d: 0x00,
      e: 0xD8,
      h: 0x01,
      l: 0x4D,
      sp: 0xFFFE,
      pc: 0x0100,
      ime: false,
      ime_pending: false,
      halted: false,
      boot_enabled: false,
      lcdc: 0x91,
      stat: 0x85,
      scy: 0,
      scx: 0,
      ly: 0,
      lyc: 0,
      bgp: 0xFC,
      obp0: 0xFF,
      obp1: 0xFF,
      wy: 0,
      wx: 0,
      div_counter: 0xABCC,
      tima: 0,
      tma: 0,
      tac: 0,
      joyp_select: 0x30,
      ppu_dot: 0,
      ppu_mode: 2,
      window_line: 0,
      if_: 0xE1,
      ie: 0x00
    }
  end

  @doc """
  Loads a user-supplied boot ROM from `GB_EMU_BOOT_ROM`, or returns the open
  boot stub when the variable is unset.
  """
  def load!(path \\ nil)

  def load!(path) when is_binary(path) and path != "" do
    path
    |> File.read!()
    |> validate_boot_rom!()
  end

  def load!(_path) do
    case System.get_env("GB_EMU_BOOT_ROM") do
      path when is_binary(path) and path != "" ->
        load!(path)

      _ ->
        minimal()
    end
  end

  defp validate_boot_rom!(boot) when byte_size(boot) == 0x100, do: boot

  defp validate_boot_rom!(boot) do
    raise ArgumentError,
          "expected a 256-byte DMG boot ROM, got #{byte_size(boot)} bytes"
  end
end
