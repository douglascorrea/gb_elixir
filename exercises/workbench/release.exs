defmodule GBEmulings.Release do
  def rom_policy_complete?(text) do
    required = ["lawfully", "ROM", "boot ROM"]
    Enum.all?(required, &String.contains?(text, &1))
  end

  def release_ready?(paths) do
    Enum.all?(paths, &File.exists?/1)
  end
end
