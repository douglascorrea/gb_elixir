defmodule GbEmu.PPU do
  @moduledoc """
  Pixel Processing Unit. Advances the LCD state machine by elapsed CPU
  cycles, renders scanlines (background, window, sprites) into per-line
  binaries of 2-bit shades, and assembles a full 160x144 frame at VBlank.
  """

  import Bitwise
  alias GbEmu.GB

  @screen_w 160
  @line_dots 456
  @mode3_end 252

  def step(gb, cycles) do
    if (gb.lcdc &&& 0x80) == 0 do
      gb
    else
      advance(%{gb | ppu_dot: gb.ppu_dot + cycles})
    end
  end

  defp advance(gb) do
    case gb.ppu_mode do
      2 ->
        if gb.ppu_dot >= 80 do
          advance(%{gb | ppu_mode: 3, stat: (gb.stat &&& 0xFC) ||| 3})
        else
          gb
        end

      3 ->
        if gb.ppu_dot >= @mode3_end do
          gb = render_scanline(gb)
          gb = %{gb | ppu_mode: 0, stat: gb.stat &&& 0xFC}
          gb = if (gb.stat &&& 0x08) != 0, do: req_stat(gb), else: gb
          advance(gb)
        else
          gb
        end

      0 ->
        if gb.ppu_dot >= @line_dots do
          gb = %{gb | ppu_dot: gb.ppu_dot - @line_dots, ly: gb.ly + 1}
          gb = check_lyc(gb)

          if gb.ly == 144 do
            gb = finish_frame(gb)
            gb = %{gb | ppu_mode: 1, stat: (gb.stat &&& 0xFC) ||| 1, if_: gb.if_ ||| 0x01}
            gb = if (gb.stat &&& 0x10) != 0, do: req_stat(gb), else: gb
            advance(gb)
          else
            gb = %{gb | ppu_mode: 2, stat: (gb.stat &&& 0xFC) ||| 2}
            gb = if (gb.stat &&& 0x20) != 0, do: req_stat(gb), else: gb
            advance(gb)
          end
        else
          gb
        end

      1 ->
        if gb.ppu_dot >= @line_dots do
          gb = %{gb | ppu_dot: gb.ppu_dot - @line_dots, ly: gb.ly + 1}

          if gb.ly > 153 do
            gb = %{gb | ly: 0, window_line: 0, ppu_mode: 2, stat: (gb.stat &&& 0xFC) ||| 2}
            gb = check_lyc(gb)
            gb = if (gb.stat &&& 0x20) != 0, do: req_stat(gb), else: gb
            advance(gb)
          else
            advance(check_lyc(gb))
          end
        else
          gb
        end
    end
  end

  defp req_stat(gb), do: %{gb | if_: gb.if_ ||| 0x02}

  defp check_lyc(gb) do
    if gb.ly == gb.lyc do
      gb = %{gb | stat: gb.stat ||| 0x04}
      if (gb.stat &&& 0x40) != 0, do: req_stat(gb), else: gb
    else
      %{gb | stat: gb.stat &&& bnot(0x04)}
    end
  end

  defp finish_frame(gb) do
    blank = :binary.copy(<<0>>, @screen_w)

    frame =
      Enum.map(0..143, fn y -> Map.get(gb.fb_lines, y, blank) end)
      |> IO.iodata_to_binary()

    %{gb | frame: frame, frame_count: gb.frame_count + 1, fb_lines: %{}}
  end

  # ---------------------------------------------------------------
  # Scanline rendering
  # ---------------------------------------------------------------

  defp render_scanline(gb) do
    ly = gb.ly
    {bg_indices, gb} = bg_window_line(gb, ly)
    {line, gb} = apply_sprites_and_palette(gb, ly, bg_indices)
    %{gb | fb_lines: Map.put(gb.fb_lines, ly, line)}
  end

  # Returns {160-element list of BG/window color indices (0..3), gb}
  defp bg_window_line(gb, ly) do
    lcdc = gb.lcdc

    bg =
      if (lcdc &&& 0x01) != 0 do
        map_base = if (lcdc &&& 0x08) != 0, do: 0x1C00, else: 0x1800
        y = ly + gb.scy &&& 0xFF
        row = tile_row_pixels(gb, map_base, y)
        scx = gb.scx
        # take 160 pixels starting at scx with wraparound (row has 256)
        row_t = List.to_tuple(row)
        for x <- 0..(@screen_w - 1), do: elem(row_t, scx + x &&& 0xFF)
      else
        List.duplicate(0, @screen_w)
      end

    window_visible =
      (lcdc &&& 0x20) != 0 and (lcdc &&& 0x01) != 0 and ly >= gb.wy and gb.wx <= 166

    if window_visible do
      map_base = if (lcdc &&& 0x40) != 0, do: 0x1C00, else: 0x1800
      row = tile_row_pixels(gb, map_base, gb.window_line &&& 0xFF)
      row_t = List.to_tuple(row)
      wx = gb.wx - 7

      line =
        bg
        |> Enum.with_index()
        |> Enum.map(fn {px, x} ->
          if x >= wx and x - wx <= 255, do: elem(row_t, x - wx), else: px
        end)

      # The window keeps its own line counter that only advances on lines
      # where it was actually rendered.
      {line, %{gb | window_line: gb.window_line + 1}}
    else
      {bg, gb}
    end
  end

  # Renders one full 256-pixel row of a 32x32 tile map. `y` is the row
  # within the 256px map space.
  defp tile_row_pixels(gb, map_base, y) do
    tile_row = y >>> 3
    py = y &&& 7
    signed = (gb.lcdc &&& 0x10) == 0
    table = GB.decode_table()
    vram = gb.vram
    row_base = map_base + tile_row * 32

    Enum.flat_map(0..31, fn tx ->
      tile_id = :atomics.get(vram, row_base + tx + 1)

      data_addr =
        if signed do
          0x1000 + if(tile_id > 127, do: tile_id - 256, else: tile_id) * 16
        else
          tile_id * 16
        end

      lo = :atomics.get(vram, data_addr + py * 2 + 1)
      hi = :atomics.get(vram, data_addr + py * 2 + 2)
      elem(table, lo ||| hi <<< 8)
    end)
  end

  # Applies sprites over BG indices, maps everything through palettes and
  # returns the final line as a binary of shades (0..3).
  defp apply_sprites_and_palette(gb, ly, bg_indices) do
    bgp = gb.bgp

    sprites =
      if (gb.lcdc &&& 0x02) != 0 do
        visible_sprites(gb, ly)
      else
        []
      end

    if sprites == [] do
      line = for idx <- bg_indices, into: <<>>, do: <<bgp >>> (idx * 2) &&& 3>>
      {line, gb}
    else
      overlay = sprite_overlay(gb, ly, sprites)

      line =
        bg_indices
        |> Enum.with_index()
        |> Enum.map(fn {bg_idx, x} ->
          case Map.get(overlay, x) do
            nil ->
              bgp >>> (bg_idx * 2) &&& 3

            {color, pal, behind} ->
              if behind and bg_idx != 0 do
                bgp >>> (bg_idx * 2) &&& 3
              else
                pal >>> (color * 2) &&& 3
              end
          end
        end)
        |> :erlang.list_to_binary()

      {line, gb}
    end
  end

  # Selects up to 10 sprites for this scanline, in DMG priority order
  # (lower X wins, then lower OAM index).
  defp visible_sprites(gb, ly) do
    height = if (gb.lcdc &&& 0x04) != 0, do: 16, else: 8
    oam = gb.oam

    for(
      i <- 0..39,
      sy = :atomics.get(oam, i * 4 + 1) - 16,
      ly >= sy and ly < sy + height,
      do: %{
        idx: i,
        y: sy,
        x: :atomics.get(oam, i * 4 + 2) - 8,
        tile: :atomics.get(oam, i * 4 + 3),
        attr: :atomics.get(oam, i * 4 + 4)
      }
    )
    |> Enum.take(10)
    |> Enum.sort_by(fn s -> {s.x, s.idx} end)
  end

  # Builds map of x -> {color_index, palette, behind_bg}. Sprites are folded
  # lowest-priority first so higher-priority pixels overwrite.
  defp sprite_overlay(gb, ly, sprites) do
    height = if (gb.lcdc &&& 0x04) != 0, do: 16, else: 8
    table = GB.decode_table()
    vram = gb.vram

    sprites
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn s, acc ->
      row = ly - s.y
      row = if (s.attr &&& 0x40) != 0, do: height - 1 - row, else: row

      tile =
        if height == 16 do
          (s.tile &&& 0xFE) ||| row >>> 3
        else
          s.tile
        end

      py = row &&& 7
      lo = :atomics.get(vram, tile * 16 + py * 2 + 1)
      hi = :atomics.get(vram, tile * 16 + py * 2 + 2)
      pixels = elem(table, lo ||| hi <<< 8)
      pixels = if (s.attr &&& 0x20) != 0, do: Enum.reverse(pixels), else: pixels
      pal = if (s.attr &&& 0x10) != 0, do: gb.obp1, else: gb.obp0
      behind = (s.attr &&& 0x80) != 0

      pixels
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {color, dx}, acc2 ->
        x = s.x + dx

        if color != 0 and x >= 0 and x < @screen_w do
          Map.put(acc2, x, {color, pal, behind})
        else
          acc2
        end
      end)
    end)
  end
end
