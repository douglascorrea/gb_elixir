defmodule Mix.Tasks.GbEmu.ExercisesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "help explains the branch-based red-green workflow" do
    output = run_task(["help"])

    assert output =~ "./gbemulings start"
    assert output =~ "./gbemulings check"
    assert output =~ "./gbemulings next"
    assert output =~ "creates a Git branch"
  end

  test "repository command is executable shell" do
    assert Bitwise.band(File.stat!("gbemulings").mode, 0o111) != 0
    assert {"", 0} = System.cmd("sh", ["-n", "gbemulings"], stderr_to_stdout: true)
  end

  test "show includes the concrete scaffold and executable checks" do
    output = run_task(["show", "048"])

    assert output =~ "048 Implement ADD and ADC"
    assert output =~ "Scaffold target:"
    assert output =~ "lib/gb_emu/cpu.ex"
    assert output =~ "mix test test/gb_emulings/cpu_test.exs"
  end

  test "show renders a branch-region scaffold" do
    output = run_task(["show", "021"])

    assert output =~ "Branch starting at:"
    assert output =~ "addr < 0x4000 ->"
  end

  test "show renders a whole-file policy scaffold" do
    output = run_task(["show", "109"])

    assert output =~ "109 Write the ROM and trademark policy"
    assert output =~ "docs/roms.md"
    assert output =~ "Entire file"
    assert output =~ "mix test test/gb_emulings/policy_test.exs"
  end

  defp run_task(args) do
    Mix.Task.reenable("gb_emu.exercises")
    capture_io(fn -> Mix.Tasks.GbEmu.Exercises.run(args) end)
  end
end
