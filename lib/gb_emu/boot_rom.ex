defmodule GbEmu.BootRom do
  @moduledoc """
  Boot ROM handling for local emulator sessions.

  The project does not ship a copyrighted console BIOS. By default it uses a
  tiny open boot stub that unmaps the boot area and jumps to the cartridge
  entrypoint. Users who have a legally obtained DMG boot ROM can point
  `GB_EMU_BOOT_ROM` at their local copy.
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
