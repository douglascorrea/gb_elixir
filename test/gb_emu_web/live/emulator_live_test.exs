defmodule GbEmuWeb.EmulatorLiveTest do
  use GbEmuWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GbEmu.UploadStore
  alias GbEmuWeb.DebuggerComponents

  test "renders upload controls", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Game ROM"
    assert html =~ "Boot ROM"
    assert html =~ "Upload game ROM"
    assert html =~ "Upload boot ROM"
    assert html =~ "Load uploads"
    assert html =~ "deleted after 2 hours"
  end

  test "renders an accessible debugger workbench with disabled no-ROM controls", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#debug-sidebar[data-debug-ui]")
    assert has_element?(view, "#debug-attach[disabled]")
    assert has_element?(view, "#debug-step[disabled]")
    assert has_element?(view, "#debug-step-10[disabled]")
    assert has_element?(view, "#debug-next-ppu[disabled]")
    assert has_element?(view, "#debug-next-scanline[disabled]")
    assert has_element?(view, "#debug-next-frame[disabled]")
    assert has_element?(view, "#debug-restart[disabled]")
    assert has_element?(view, "#debug-resume[disabled]")
    assert has_element?(view, "#debug-instruction")
    assert has_element?(view, "#debug-registers")
    assert has_element?(view, "#debug-memory-form")
    assert has_element?(view, "#debug-memory-grid")
    assert has_element?(view, "#debug-ppu")
    assert has_element?(view, "#debug-trace[phx-update=stream]")
  end

  test "the attached sidebar renders debugger data and enabled controls" do
    trace = representative_trace()

    html =
      render_component(&DebuggerComponents.sidebar/1,
        attached: true,
        available: true,
        snapshot: representative_snapshot(trace),
        error: nil,
        memory_form: Phoenix.Component.to_form(%{"address" => "0000"}, as: :memory),
        trace_stream: [{"debug-traces-7", trace}]
      )

    assert has_selector?(html, "#debug-sidebar[data-debug-ui]")
    assert has_selector?(html, "#debug-step")
    refute has_selector?(html, "#debug-step[disabled]")
    assert has_selector?(html, "#debug-resume")
    refute has_selector?(html, "#debug-resume[disabled]")
    assert has_selector?(html, "#debug-memory-form input[name='memory[address]']")
    assert has_selector?(html, "#debug-memory-submit")
    assert has_selector?(html, "#debug-memory-grid [data-address='0000']")

    assert has_selector?(
             html,
             ".debugger-memory-event[data-memory-operation='read_range'][data-memory-address='8000']"
           )

    assert has_selector?(
             html,
             ".debugger-memory-event[data-memory-operation='dma'][data-memory-address='C000']"
           )

    assert has_selector?(html, ".debugger-memory-event a[href$='#L88']")
    assert has_selector?(html, "#debug-trace #debug-traces-7")
    assert has_selector?(html, "#debug-instruction a[href*='lib/gb_emu/cpu.ex#L']")
  end

  test "reconciles retained partial history after a boundary command error", %{conn: conn} do
    conn = get(conn, ~p"/")
    upload_session_id = get_session(conn, "upload_session_id")

    on_exit(fn -> UploadStore.schedule_cleanup(upload_session_id, ttl_ms: 0) end)

    {:ok, view, _html} = live(conn)

    upload =
      file_input(view, "#rom-upload-form", :rom, [
        %{
          last_modified: 1_718_000_000_000,
          name: "debug-timeout.gb",
          content: boundary_limit_rom(),
          type: "application/octet-stream"
        }
      ])

    assert render_upload(upload, "debug-timeout.gb") =~ "100%"
    view |> form("#rom-upload-form") |> render_submit()

    assert has_element?(view, "#debug-attach:not([disabled])")
    view |> element("#debug-attach") |> render_click()
    view |> element("#debug-step-10") |> render_click()
    view |> element("#debug-next-ppu") |> render_click()
    assert has_element?(view, "#debug-error[role='alert']")

    view |> element("#debug-step") |> render_click()

    trace_count =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#debug-trace .debugger-trace-row")
      |> Enum.count()

    assert trace_count == 200
  end

  defp representative_snapshot(trace) do
    %{
      mode: :debugging,
      cpu: %{
        pc: 0x0000,
        registers: %{
          a: 0x01,
          f: 0xB0,
          b: 0,
          c: 0x13,
          d: 0,
          e: 0xD8,
          h: 1,
          l: 0x4D,
          sp: 0xFFFE,
          pc: 0
        },
        flags: %{z: true, n: false, h: true, c: true},
        ime: false,
        ime_pending: false,
        halted: false
      },
      boot: %{kind: :minimal, mode: :cold, overlay_enabled?: true, enabled: true},
      instruction: %{
        kind: :instruction,
        pc: 0,
        bytes: [0xC3, 0xFC, 0x00],
        mnemonic: "JP $00FC",
        operands: [0x00FC],
        handler: {:cpu, "defp exec(0xC3, gb)"}
      },
      next_instruction: %{pc: 3, bytes: [0], mnemonic: "NOP"},
      interrupts: %{ie: 0, if: 0, pending: 0},
      ppu: %{lcdc: 0, stat: 0, ly: 0, lyc: 0, ppu_dot: 12, ppu_mode: 2, frame_count: 0},
      timer: %{div_counter: 12, tima: 0, tma: 0, tac: 0},
      serial: %{data: 0, control: 0, cycles_remaining: nil, output_bytes: 0},
      joypad: %{joyp_select: 0x30, dpad: 0, btns: 0},
      cartridge: %{mbc: :none, rom_bank: 1, ram_bank: 0, ram_enabled: false},
      memory: %{
        start: 0,
        stop: 0xFF,
        bytes: [0xC3, 0xFC, 0x00],
        cells: [
          %{
            address: 0,
            value: 0xC3,
            region: :boot_rom,
            label: "Boot ROM",
            pc?: true,
            sp?: false,
            read?: true,
            write?: false,
            markers: [:pc, :read]
          },
          %{
            address: 1,
            value: 0xFC,
            region: :boot_rom,
            label: "Boot ROM",
            pc?: false,
            sp?: false,
            read?: true,
            write?: false,
            markers: [:read]
          },
          %{
            address: 2,
            value: 0x00,
            region: :boot_rom,
            label: "Boot ROM",
            pc?: false,
            sp?: false,
            read?: false,
            write?: false,
            markers: []
          }
        ],
        markers: %{pc: 0, sp: 0xFFFE, reads: [0, 1], writes: []}
      },
      newest_trace: trace,
      history: [trace]
    }
  end

  defp boundary_limit_rom do
    :binary.copy(<<0>>, 0x8000)
    |> put_byte(0x0100, 0x3E)
    |> put_byte(0x0101, 0x00)
    |> put_byte(0x0102, 0xE0)
    |> put_byte(0x0103, 0x40)
    |> put_byte(0x0104, 0x18)
    |> put_byte(0x0105, 0xFE)
    |> put_byte(0x0147, 0x00)
  end

  defp put_byte(binary, index, value) do
    prefix = binary_part(binary, 0, index)
    suffix = binary_part(binary, index + 1, byte_size(binary) - index - 1)
    prefix <> <<value>> <> suffix
  end

  defp representative_trace do
    %{
      id: 7,
      kind: :instruction,
      mnemonic: "JP $00FC",
      pc_before: 0,
      pc_after: 0x00FC,
      cycles: 16,
      register_deltas: %{pc: %{before: 0, after: 0x00FC}},
      memory: [
        %{
          operation: :read,
          address: 0,
          value: 0xC3,
          region: :boot_rom,
          label: "Boot ROM overlay",
          source_location: %{
            path: "lib/gb_emu/bus.ex",
            line: 88,
            label: "Bus",
            url: "https://github.com/douglascorrea/gb_elixir/blob/master/lib/gb_emu/bus.ex#L88"
          }
        },
        %{
          operation: :read_range,
          ranges: [%{start: 0x8000, stop: 0x801F, purpose: :tile_data}],
          region: :vram,
          label: "PPU tile fetch",
          source_location: %{
            path: "lib/gb_emu/ppu.ex",
            line: 144,
            label: "PPU",
            url: "https://github.com/douglascorrea/gb_elixir/blob/master/lib/gb_emu/ppu.ex#L144"
          }
        },
        %{
          operation: :dma,
          source: 0xC000..0xC09F,
          destination: 0xFE00..0xFE9F,
          region: :oam,
          label: "OAM DMA block transfer",
          source_location: %{
            path: "lib/gb_emu/bus.ex",
            line: 203,
            label: "Bus",
            url: "https://github.com/douglascorrea/gb_elixir/blob/master/lib/gb_emu/bus.ex#L203"
          }
        }
      ],
      sources: [
        %{
          path: "lib/gb_emu/cpu.ex",
          line: 122,
          label: "CPU",
          url: "https://github.com/douglascorrea/gb_elixir/blob/master/lib/gb_emu/cpu.ex#L122"
        }
      ]
    }
  end

  defp has_selector?(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.any?()
  end
end
