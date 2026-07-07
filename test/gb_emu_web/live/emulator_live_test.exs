defmodule GbEmuWeb.EmulatorLiveTest do
  use GbEmuWeb.ConnCase, async: true

  test "renders upload controls", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Game ROM"
    assert html =~ "Boot ROM"
    assert html =~ "Load uploads"
    assert html =~ "deleted after 2 hours"
  end
end
