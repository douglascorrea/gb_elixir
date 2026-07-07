defmodule GbEmu.Timer do
  @moduledoc """
  DIV / TIMA timer unit. DIV increments at 16384 Hz (upper byte of a
  free-running 16-bit counter); TIMA increments at the TAC-selected rate and
  requests the timer interrupt on overflow.
  """

  import Bitwise

  @periods {1024, 16, 64, 256}

  def step(gb, cycles) do
    gb = %{gb | div_counter: gb.div_counter + cycles &&& 0xFFFF}

    if (gb.tac &&& 0x04) != 0 do
      period = elem(@periods, gb.tac &&& 0x03)
      tick_tima(%{gb | tima_acc: gb.tima_acc + cycles}, period)
    else
      gb
    end
  end

  defp tick_tima(gb, period) do
    if gb.tima_acc >= period do
      gb = %{gb | tima_acc: gb.tima_acc - period}

      gb =
        if gb.tima >= 0xFF do
          %{gb | tima: gb.tma, if_: gb.if_ ||| 0x04}
        else
          %{gb | tima: gb.tima + 1}
        end

      tick_tima(gb, period)
    else
      gb
    end
  end
end
