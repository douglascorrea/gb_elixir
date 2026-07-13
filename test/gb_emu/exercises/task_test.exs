defmodule Mix.Tasks.GbEmu.ExercisesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "help explains the branch-based red-green workflow" do
    output = run_task(["help"])

    assert output =~ "mix gb_emu.exercises start"
    assert output =~ "mix gb_emu.exercises check"
    assert output =~ "mix gb_emu.exercises next"
    assert output =~ "creates a Git branch"
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

  defp run_task(args) do
    Mix.Task.reenable("gb_emu.exercises")
    capture_io(fn -> Mix.Tasks.GbEmu.Exercises.run(args) end)
  end
end
