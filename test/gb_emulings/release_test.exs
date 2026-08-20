Code.require_file("../../exercises/workbench/release.exs", __DIR__)

defmodule GBEmulings.ReleaseTest do
  use ExUnit.Case, async: true

  alias GBEmulings.Release

  test "recognizes a complete ROM policy" do
    policy = "Use only lawfully obtained ROM files. A boot ROM must also be lawful."
    assert Release.rom_policy_complete?(policy)
  end

  test "requires every release artifact" do
    root = File.cwd!()
    assert Release.release_ready?([Path.join(root, "README.md"), Path.join(root, "mix.exs")])
    refute Release.release_ready?([Path.join(root, "missing-release-file")])
  end
end
